/// 音高识别服务（音频引擎核心层）
///
/// 封装 [麦克风采集 record] + [YIN 音高识别 pitch_detector_dart]，
/// 向上层暴露统一的音高事件流。
/// 这是 MVP 的技术心脏，对应 TDD §3.4 三层音频引擎的 L1+L2 抽象。
///
/// 设计目标（TDD §3.1）：
/// - 端到端延迟 < 100ms（目标）/ < 150ms（MVP 可接受）
/// - 音高精度误差 < ±5 cents
/// - 支持 C3(130Hz)–C6(1047Hz)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

import 'sr_probe.dart';

/// 音高识别结果事件
@immutable
class PitchResult {
  /// 识别到的频率（Hz），为 null 表示未检测到有效音高（太安静/噪声）
  final double? frequency;

  /// YIN 置信度（0~1），越接近 0 越可信
  final double? probability;

  /// 音频 RMS 能量（0~1），用于噪声门限判断
  final double energy;

  /// 原始 PCM 样本（Float32 归一化），供下游做 FFT/和弦识别
  final Float32List? samples;

  /// 时间戳（启动后的毫秒）
  final int timestampMs;

  const PitchResult({
    required this.frequency,
    required this.probability,
    required this.energy,
    required this.timestampMs,
    this.samples,
  });

  /// 是否有有效音高：频率 > 0 且能量超过门限（过滤环境噪声）
  bool get hasPitch => frequency != null && frequency! > 0 && energy > 0.01;

  @override
  String toString() =>
      'PitchResult(f=${frequency?.toStringAsFixed(1)}Hz, p=$probability)';
}

/// 音高识别服务
///
/// 使用方式：
/// ```dart
/// final svc = ref.read(pitchServiceProvider);
/// await svc.start();              // 开始采集+识别
/// svc.pitchStream.listen((r){}); // 监听音高
/// await svc.stop();
/// ```
class PitchDetectionService {
  static const int _sampleRate = 44100;
  static const int _bufferSize = 2048; // YIN 窗口（约 46ms@44.1k）

  /// 实际采样率（Web 上 AudioContext 可能用 48000 而非请求的 44100，
  /// Chroma 识别必须用真实采样率否则频率计算整体偏移）。
  int _actualSampleRate = _sampleRate;
  int get actualSampleRate => _actualSampleRate;

  final AudioRecorder _recorder = AudioRecorder();
  // 延迟创建：等探测到实际采样率后，用正确的采样率构造 YIN 识别器
  PitchDetector? _detector;

  StreamSubscription? _audioSub;
  final _pitchController = StreamController<PitchResult>.broadcast();

  bool _isRunning = false;

  // 诊断计数（真机调试用）
  int _audioPackets = 0; // 收到的音频数据包数
  int _detectCalls = 0;  // 识别调用次数
  int get audioPackets => _audioPackets;
  int get detectCalls => _detectCalls;

  /// 音高事件流（广播，可多订阅）
  Stream<PitchResult> get pitchStream => _pitchController.stream;

  bool get isRunning => _isRunning;

  /// 开始采集麦克风并实时输出音高
  Future<void> start() async {
    if (_isRunning) return;

    // 权限处理（平台分流）：
    // - Android/iOS：必须先调 hasPermission() 触发系统授权弹窗，
    //   否则 startStream 在无权限下静默失败、无数据。
    // - Web：hasPermission() 的 permissions.query 在 Chrome 不稳定，
    //   跳过预检查，直接 startStream() 由 getUserMedia 弹授权框。
    if (!kIsWeb) {
      final granted = await _recorder.hasPermission();
      if (!granted) {
        throw const PitchServiceException(
            '麦克风权限被拒绝，请到系统设置 → 应用 → 尤克里里 → 权限，允许麦克风后重试');
      }
    }

    _isRunning = true;

    // 探测 Web AudioContext 真实采样率（Chroma 和弦识别必须用对，否则频率偏移）
    _actualSampleRate = detectActualSampleRate(_sampleRate);
    // 用实际采样率创建 YIN 识别器（采样率不匹配会导致频率系统性偏移！）
    _detector = PitchDetector(
      audioSampleRate: _actualSampleRate.toDouble(),
      bufferSize: _bufferSize,
    );

    Stream<List<int>> stream;
    try {
      stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
    } catch (e) {
      _isRunning = false;
      throw PitchServiceException('无法访问麦克风：$e');
    }

    // 累积 PCM16 字节到一帧窗口再识别。
    // 用索引追踪消费位置，避免 removeRange（头部删除 O(n) 会卡顿）。
    final frameBuffer = <int>[];
    final frameByteLen = _bufferSize * 2; // 一帧字节数（每样本 2 字节）
    var consumeOffset = 0; // 已消费到的字节偏移
    _audioPackets = 0;
    _detectCalls = 0;
    _audioSub = stream.listen((data) {
      _audioPackets++;
      frameBuffer.addAll(data);
      // 用 50% 重叠（每次前进半个窗口），提升时间分辨率 + 响应速度
      while (frameBuffer.length - consumeOffset >= frameByteLen) {
        final frameBytes = Uint8List.fromList(
            frameBuffer.sublist(consumeOffset, consumeOffset + frameByteLen));
        _detect(frameBytes);
        consumeOffset += frameByteLen ~/ 2; // 半个窗口步进
        // 周期性清理已消费数据，避免内存无限增长
        if (consumeOffset > frameByteLen * 4) {
          frameBuffer.removeRange(0, consumeOffset);
          consumeOffset = 0;
        }
      }
    });
  }

  /// 停止采集
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  void _detect(Uint8List pcm16Bytes) async {
    _detectCalls++;
    try {
      // PCM16 → Float32 样本（供下游 FFT/和弦识别）
      final samples = _bytesToFloat(pcm16Bytes);
      // 计算 RMS 能量（用于噪声门限）
      final energy = _rmsFromSamples(samples);
      final result = await _detector!.getPitchFromIntBuffer(pcm16Bytes);
      _pitchController.add(PitchResult(
        frequency: result.pitch > 0 ? result.pitch : null,
        probability: result.probability,
        energy: energy,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        samples: samples,
      ));
    } catch (e) {
      // 缓冲不足等异常静默忽略
      debugPrint('pitch detect error: $e');
    }
  }

  /// PCM16 (little-endian bytes) → Float32 [-1.0, 1.0]
  Float32List _bytesToFloat(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    if (sampleCount == 0) return Float32List(0);
    final result = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      final v = data.getInt16(i * 2, Endian.little);
      result[i] = v / 32768.0;
    }
    return result;
  }

  double _rmsFromSamples(Float32List samples) {
    if (samples.isEmpty) return 0;
    double sumSq = 0;
    for (final v in samples) {
      sumSq += v * v;
    }
    return sumSq / samples.length;
  }

  Future<void> dispose() async {
    await stop();
    await _pitchController.close();
    await _recorder.dispose();
  }
}

/// 音高服务异常
class PitchServiceException implements Exception {
  final String message;
  const PitchServiceException(this.message);
  @override
  String toString() => 'PitchServiceException: $message';
}

/// 音高识别服务 Provider（单例）
final pitchServiceProvider = Provider<PitchDetectionService>((ref) {
  final svc = PitchDetectionService();
  ref.onDispose(svc.dispose);
  return svc;
});
