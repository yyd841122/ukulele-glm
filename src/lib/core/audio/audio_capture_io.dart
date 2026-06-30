/// 音频采集 - 移动端实现（Android/iOS，继续用 record 包）
///
/// 移动端 record 包尊重请求的采样率（不像 Web 端是黑盒），
/// 所以直接用请求值 44100 作为真实采样率即可。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_capture.dart';

AudioCapturer createAudioCapturerImpl() => _RecordCapturer();

class _RecordCapturer implements AudioCapturer {
  static const int _sampleRate = 44100;
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<AudioFrame>? _controller;
  StreamSubscription<List<int>>? _audioSub;

  @override
  Future<Stream<AudioFrame>> start({int bufferSize = 2048}) async {
    final controller = StreamController<AudioFrame>();
    _controller = controller;
    final frameByteLen = bufferSize * 2; // PCM16，每样本 2 字节
    final frameBuffer = <int>[];
    var consumeOffset = 0;

    // 权限检查：Android/iOS 必须先调 hasPermission() 触发系统授权弹窗，
    // 否则 startStream 在无权限下静默失败、无数据（真机调音器无反应的根因）。
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw Exception('麦克风权限被拒绝，请到系统设置 → 应用 → 尤克里里 → 权限，允许麦克风后重试');
    }

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
    _audioSub = stream.listen((data) {
      if (controller.isClosed) return;
      frameBuffer.addAll(data);
      // 50% 重叠
      while (frameBuffer.length - consumeOffset >= frameByteLen) {
        final frameBytes = Uint8List.fromList(
            frameBuffer.sublist(consumeOffset, consumeOffset + frameByteLen));
        controller.add(AudioFrame(
          samples: _bytesToFloat(frameBytes),
          sampleRate: _sampleRate,
        ));
        consumeOffset += frameByteLen ~/ 2;
        if (consumeOffset > frameByteLen * 4) {
          frameBuffer.removeRange(0, consumeOffset);
          consumeOffset = 0;
        }
      }
    });
    return controller.stream;
  }

  /// PCM16 (LE) → Float32
  Float32List _bytesToFloat(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    if (n == 0) return Float32List(0);
    final out = Float32List(n);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  @override
  Future<void> stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
