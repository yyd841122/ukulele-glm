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

/// 音高识别结果事件
@immutable
class PitchResult {
  /// 识别到的频率（Hz），为 null 表示未检测到有效音高（太安静/噪声）
  final double? frequency;

  /// YIN 置信度（0~1），越接近 0 越可信
  final double? probability;

  /// 时间戳（启动后的毫秒）
  final int timestampMs;

  const PitchResult({
    required this.frequency,
    required this.probability,
    required this.timestampMs,
  });

  bool get hasPitch => frequency != null && frequency! > 0;

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

  final AudioRecorder _recorder = AudioRecorder();
  final PitchDetector _detector =
      PitchDetector(audioSampleRate: _sampleRate.toDouble(), bufferSize: _bufferSize);

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

    // 累积 PCM16 字节到一帧窗口再识别，避免碎包且保证 YIN 精度
    final frameBuffer = <int>[];
    _audioPackets = 0;
    _detectCalls = 0;
    _audioSub = stream.listen((data) {
      _audioPackets++;
      frameBuffer.addAll(data);
      while (frameBuffer.length >= _bufferSize * 2) {
        // 取一帧（每样本 2 字节）
        final frameBytes =
            Uint8List.fromList(frameBuffer.sublist(0, _bufferSize * 2));
        frameBuffer.removeRange(0, _bufferSize * 2);
        _detect(frameBytes);
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
      final result = await _detector.getPitchFromIntBuffer(pcm16Bytes);
      _pitchController.add(PitchResult(
        frequency: result.pitch > 0 ? result.pitch : null,
        probability: result.probability,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      // 缓冲不足等异常静默忽略
      debugPrint('pitch detect error: $e');
    }
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
