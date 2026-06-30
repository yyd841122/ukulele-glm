/// 音频采集抽象层 —— 条件导入路由
///
/// Web 端用 AudioWorklet 直采（绕开 record 包的采样率黑盒），
/// 移动端继续用 record 包。
///
/// 采集层职责：启动/停止麦克风，输出 (Float32样本, 采样率) 给上层。
/// **采样率由采集层提供真值**（Web = AudioContext.sampleRate，移动 = 请求值），
/// 上层无需再探测，从根本上消除采样率不一致问题。
library;

import 'dart:async';
import 'dart:typed_data';

import 'audio_capture_stub.dart'
    if (dart.library.js_interop) 'audio_capture_web.dart'
    if (dart.library.io) 'audio_capture_io.dart';

/// 采集到的一帧音频
class AudioFrame {
  /// Float32 归一化 PCM 样本 [-1, 1]
  final Float32List samples;

  /// 实际采样率（Hz）—— 采集层的唯一真值
  final int sampleRate;

  const AudioFrame({required this.samples, required this.sampleRate});
}

/// 音频采集器接口
abstract class AudioCapturer {
  /// 开始采集。返回音频帧流（每帧 Float32 样本 + 真实采样率）。
  /// [bufferSize] 每帧样本数（音高检测窗口）。
  Future<Stream<AudioFrame>> start({int bufferSize = 2048});

  /// 停止采集
  Future<void> stop();

  /// 释放资源
  Future<void> dispose();
}

/// 创建平台对应的采集器实例
AudioCapturer createAudioCapturer() => createAudioCapturerImpl();
