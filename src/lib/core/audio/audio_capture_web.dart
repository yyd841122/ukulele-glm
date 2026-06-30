/// 音频采集 - Web 实现（直接用 Web Audio API，绕开 record 包）
///
/// 【为什么不用 record 包】record 包在 Web 上自管 AudioContext，内部重采样，
/// 外部探测的采样率和实际数据采样率对不上，导致音高算法频率系统性偏移。
/// 实测（selftest）证明：直接用 AudioWorklet 采集，采样率 100% 由
/// AudioContext.sampleRate 决定，喂给算法完全正确。
///
/// 采集流程：
///   1. getUserMedia 拿麦克风流
///   2. new AudioContext() → 读 ctx.sampleRate 作为唯一真值
///   3. audioWorklet.addModule 加载 pitch-capture processor
///   4. AudioWorkletNode + createMediaStreamSource 连线
///   5. node.port.onMessage 接收 Float32 帧 → AudioFrame(采样率=ctx.sampleRate)
///
/// worklet 代码用 Blob URL 内联（不依赖资源打包路径，最可靠）。
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'audio_capture.dart';

AudioCapturer createAudioCapturerImpl() => _WebCapturer();

/// AudioWorklet processor 的 JS 源码（用 Blob URL 加载，避免资源路径问题）
const _workletSource = r'''
class PitchCaptureProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this._bufSize = (options && options.processorOptions && options.processorOptions.bufSize) || 2048;
    this._buffer = [];
  }
  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const channel = input[0];
    if (!channel) return true;
    for (let i = 0; i < channel.length; i++) this._buffer.push(channel[i]);
    while (this._buffer.length >= this._bufSize) {
      const frame = this._buffer.splice(0, this._bufSize);
      this.port.postMessage(new Float32Array(frame));
    }
    return true;
  }
}
registerProcessor('pitch-capture', PitchCaptureProcessor);
''';

class _WebCapturer implements AudioCapturer {
  web.AudioContext? _ctx;
  web.MediaStream? _mediaStream;
  web.AudioWorkletNode? _node;
  web.MediaStreamAudioSourceNode? _source;
  StreamController<AudioFrame>? _controller;
  int _sampleRate = 0;

  @override
  Future<Stream<AudioFrame>> start({int bufferSize = 2048}) async {
    final controller = StreamController<AudioFrame>();
    _controller = controller;

    // 1. getUserMedia 拿麦克风
    final constraints = web.MediaStreamConstraints(
      audio: {
        'channelCount': 1,
        'echoCancellation': false,
        'noiseSuppression': false,
        'autoGainControl': false,
      }.jsify()!,
    );
    _mediaStream =
        await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

    // 2. 创建 AudioContext —— sampleRate 即为数据真实采样率（唯一真值）
    _ctx = web.AudioContext();
    _sampleRate = _ctx!.sampleRate.toInt();
    // Web 上 AudioContext 创建后默认 suspended，必须 resume 才会处理音频数据
    if (_ctx!.state == 'suspended') {
      await _ctx!.resume().toDart;
    }

    // 3. 用 Blob URL 加载 worklet（不依赖资源打包路径）
    final blob = web.Blob(
      [_workletSource.toJS].toJS,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    final workletUrl = web.URL.createObjectURL(blob);
    await _ctx!.audioWorklet.addModule(workletUrl).toDart;
    web.URL.revokeObjectURL(workletUrl);

    // 4. 连线：麦克风 → source → workletNode
    _source = _ctx!.createMediaStreamSource(_mediaStream!);
    final options = web.AudioWorkletNodeOptions(
      processorOptions: {'bufSize': bufferSize}.jsify()! as JSObject,
    );
    _node = web.AudioWorkletNode(_ctx!, 'pitch-capture', options);
    // 注意：不连 destination，避免播放反馈到扬声器

    // 5. 接收帧
    void onMessage(web.MessageEvent event) {
      if (controller.isClosed) return;
      final jsData = event.data;
      if (jsData == null) return;
      // worklet postMessage 的是 Float32Array，转回 Dart Float32List
      final f32 = (jsData as JSFloat32Array).toDart;
      if (f32.isEmpty) return;
      controller.add(AudioFrame(samples: f32, sampleRate: _sampleRate));
    }

    _node!.port.onmessage = onMessage.toJS;
    _source!.connect(_node!);

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    _node?.port.onmessage = null;
    try {
      _source?.disconnect();
    } catch (_) {}
    try {
      _node?.disconnect();
    } catch (_) {}
    _source = null;
    _node = null;

    if (_mediaStream != null) {
      try {
        final tracks = _mediaStream!.getAudioTracks().toDart;
        for (final t in tracks) {
          t.stop();
        }
      } catch (_) {}
      _mediaStream = null;
    }

    if (_ctx != null) {
      try {
        await _ctx!.close().toDart;
      } catch (_) {}
      _ctx = null;
    }

    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
