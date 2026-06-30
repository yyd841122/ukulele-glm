// AudioWorklet processor: 捕获麦克风输入，输出原始 Float32 PCM（不重采样）。
//
// 由 audio_capture_web.dart 通过 ctx.audioWorklet.addModule() 加载。
// 输出采样率 = AudioContext.sampleRate（浏览器实际，通常 48000），
// Dart 侧直接读 ctx.sampleRate，不再有"探测值 vs 数据值"不一致问题。
//
// process() 由音频线程按 128 样本块调用，累积到 bufSize 后通过 port 发送。

class PitchCaptureProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this._bufSize = (options && options.processorOptions && options.processorOptions.bufSize) || 2048;
    this._buffer = [];
  }

  process(inputs) {
    const input = inputs[0];
    // 无输入（如权限未授予/静音）时跳过，返回 true 保持 worklet 存活
    if (!input || input.length === 0) return true;
    const channel = input[0];
    if (!channel) return true;

    // 复制样本（底层可能复用缓冲区，必须拷贝）
    for (let i = 0; i < channel.length; i++) {
      this._buffer.push(channel[i]);
    }

    // 累积到一帧窗口，发送给 Dart
    while (this._buffer.length >= this._bufSize) {
      const frame = this._buffer.splice(0, this._bufSize);
      // postMessage 会结构化克隆 Float32Array，Dart 侧用 JSFloat32Array.toDart 接收
      this.port.postMessage(new Float32Array(frame));
    }
    return true;
  }
}

registerProcessor('pitch-capture', PitchCaptureProcessor);
