/// 音高识别服务（音频引擎核心层）
///
/// 重写版（替换原 record + YIN/MPM 方案）：
/// - 采集委托给 [AudioCapturer]（Web 用 AudioWorklet 直采，移动用 record）
/// - 识别用 [NccfDetector]（归一化自相关 + 第一个显著峰 + 抛物线插值）
/// - 采样率由采集层提供唯一真值（Web = AudioContext.sampleRate），上层不再探测
///
/// 保持对外接口不变：PitchResult 字段、pitchStream、actualSampleRate，
/// 4 个下游页面（调音器/跟弹/和弦转换/节奏）零改动。
///
/// 设计目标（TDD §3.1）：
/// - 端到端延迟 < 100ms
/// - 音高精度误差 < ±5 cents（NCCF 抛物线插值保证，离线已验证）
/// - 支持 C3(130Hz)–C6(1047Hz)
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_capture.dart';
import 'nccf_detector.dart';

/// 音高识别结果事件
@immutable
class PitchResult {
  /// 识别到的频率（Hz），为 null 表示未检测到有效音高（太安静/噪声）
  final double? frequency;

  /// 置信度（0~1）。NCCF 即峰值相关性，越大越可信（纯净乐音 > 0.8，噪声 < 0.3）。
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
  static const int _bufferSize = 2048; // 检测窗口（约 43ms@48k / 46ms@44.1k）

  /// NCCF 置信度阈值：低于此值视为噪声/无声。
  /// 离线验证用 0.4（纯净乐音 > 0.8）。真机可调。
  double minConfidence = 0.4;

  /// 采集器（条件导入：Web=AudioWorklet，移动=record）
  final AudioCapturer _capturer = createAudioCapturer();

  /// NCCF 识别器（运行时按真实采样率构造）
  NccfDetector? _detector;

  StreamSubscription<AudioFrame>? _frameSub;
  final _pitchController = StreamController<PitchResult>.broadcast();

  bool _isRunning = false;

  // —— 后处理状态（状态机 + 中值平滑，抑制瞬态 null 和单帧跳变）——
  // RMS 历史（最近 5 帧），用于判定 attack/stable/release
  final List<double> _rmsHistory = [];
  // 频率历史（最近 3 帧有效频率），用于中值平滑
  final List<double> _freqHistory = [];
  // 上一稳定帧的频率（attack 段输出这个，不暴露 null）
  double? _lastStableFreq;
  // 当前状态
  _PitchState _pitchState = _PitchState.idle;

  /// 实际采样率（由采集层提供真值，识别前才确定）
  int _actualSampleRate = 44100;
  int get actualSampleRate => _actualSampleRate;

  /// 诊断计数（真机调试用）
  int _audioPackets = 0;
  int _detectCalls = 0;
  int get audioPackets => _audioPackets;
  int get detectCalls => _detectCalls;

  /// 音高事件流（广播，可多订阅）
  Stream<PitchResult> get pitchStream => _pitchController.stream;

  bool get isRunning => _isRunning;

  /// 开始采集麦克风并实时输出音高
  Future<void> start() async {
    // 如果已在运行（上一个消费者没正确停止），先停掉再重启，确保干净会话
    if (_isRunning) {
      await stop();
    }

    _isRunning = true;
    _audioPackets = 0;
    _detectCalls = 0;
    // 重置后处理状态
    _rmsHistory.clear();
    _freqHistory.clear();
    _lastStableFreq = null;
    _pitchState = _PitchState.idle;

    Stream<AudioFrame> frames;
    try {
      frames = await _capturer.start(bufferSize: _bufferSize);
    } catch (e) {
      _isRunning = false;
      throw PitchServiceException('无法访问麦克风：$e');
    }

    _frameSub = frames.listen((frame) {
      _audioPackets++;
      // 第一帧确定真实采样率，构造识别器
      if (_detector == null || _detector!.sampleRate != frame.sampleRate) {
        _actualSampleRate = frame.sampleRate;
        _detector = NccfDetector(sampleRate: _actualSampleRate);
      }
      _detect(frame);
    });
  }

  /// 停止采集
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _frameSub?.cancel();
    _frameSub = null;
    await _capturer.stop();
  }

  void _detect(AudioFrame frame) {
    _detectCalls++;
    try {
      final samples = frame.samples;
      final rms = _rmsFromSamples(samples);

      // —— 门限 1：RMS 能量（过滤电扇等环境噪声）——
      // 修了之前的 bug（漏 sqrt）：现在 rms 是真正的 RMS。
      // 电扇 RMS < 0.01，拨弦 > 0.03。低于 0.01 视为静音/噪声。
      if (rms < 0.01) {
        _rmsHistory.add(rms);
        if (_rmsHistory.length > 5) _rmsHistory.removeAt(0);
        _pitchState = _PitchState.release;
        _lastStableFreq = null;
        _freqHistory.clear();
        _pitchController.add(PitchResult(
          frequency: null,
          probability: null,
          energy: rms,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          samples: samples,
        ));
        return;
      }

      final nccf = _detector!.getPitch(samples);

      // —— 门限 2：NCCF 置信度（过滤瞬态段/低质量检测）——
      // 拨弦稳态段 confidence > 0.7，噪声/瞬态 < 0.5。
      double? frequency = nccf.frequency;
      if (nccf.confidence < 0.5) {
        frequency = null;
      }

      // —— 状态机：attack/stable/release ——
      _rmsHistory.add(rms);
      if (_rmsHistory.length > 5) _rmsHistory.removeAt(0);

      final prevRms = _rmsHistory.length > 1
          ? _rmsHistory[_rmsHistory.length - 2]
          : rms;

      if (rms > prevRms * 1.5 && _pitchState != _PitchState.stable) {
        // 能量急升 → attack 段（拨弦瞬态），输出上一稳定值，不暴露 null
        _pitchState = _PitchState.attack;
      } else if (_pitchState == _PitchState.attack && rms < prevRms * 1.1) {
        // 能量趋于平稳 → stable 段
        _pitchState = _PitchState.stable;
      }

      // —— 中值平滑：最近 3 帧有效频率取中位数，抑制单帧跳变 ——
      double? smoothedFreq = frequency;
      if (frequency != null) {
        _freqHistory.add(frequency);
        if (_freqHistory.length > 3) _freqHistory.removeAt(0);
        if (_freqHistory.length >= 2) {
          _freqHistory.sort();
          smoothedFreq = _freqHistory[_freqHistory.length ~/ 2];
        }
        if (_pitchState == _PitchState.stable) {
          _lastStableFreq = smoothedFreq;
        }
      } else if (_pitchState == _PitchState.attack && _lastStableFreq != null) {
        // attack 段 NCCF 常返回 null，用上一稳定值兜底
        smoothedFreq = _lastStableFreq;
      }

      final probability = smoothedFreq != null ? nccf.confidence : null;
      _pitchController.add(PitchResult(
        frequency: smoothedFreq,
        probability: probability,
        energy: rms,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        samples: samples,
      ));
    } catch (e) {
      debugPrint('pitch detect error: $e');
    }
  }

  /// RMS 能量（正确的均方根，已修复之前漏 sqrt 的 bug）
  double _rmsFromSamples(Float32List samples) {
    if (samples.isEmpty) return 0;
    double sumSq = 0;
    for (final v in samples) {
      sumSq += v * v;
    }
    return math.sqrt(sumSq / samples.length);
  }

  Future<void> dispose() async {
    await stop();
    await _pitchController.close();
    await _capturer.dispose();
  }
}

/// 音高检测状态机阶段
/// - idle：未开始/静音
/// - attack：拨弦瞬态（能量急升），NCCF 不稳，用上一稳定值兜底
/// - stable：稳态段（能量平稳），正常输出
/// - release：音符结束（能量下降），输出 null
enum _PitchState { idle, attack, stable, release }

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
