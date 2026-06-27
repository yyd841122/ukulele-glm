/// Tick 发声 - Web 实现（Web Audio API 合成 beep）
library;

import 'dart:js_interop';
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;

void playTickImpl({bool accent = false}) {
  _playWebBeep(frequency: accent ? 1320.0 : 880.0);
}

web.AudioContext? _ctx;

/// Web 端：用 OscillatorNode 合成一个短促正弦 beep
void _playWebBeep({required double frequency}) {
  try {
    _ctx ??= web.AudioContext();
    final ctx = _ctx!;
    if (ctx.state == 'suspended') {
      ctx.resume().toDart;
    }

    final oscillator = ctx.createOscillator();
    final gain = ctx.createGain();

    oscillator.type = 'sine';
    oscillator.frequency.value = frequency;

    // 包络：快速起音，短促衰减
    final now = ctx.currentTime;
    gain.gain.setValueAtTime(0.0, now);
    gain.gain.linearRampToValueAtTime(0.3, now + 0.001);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.08);

    oscillator.connect(gain);
    gain.connect(ctx.destination);
    oscillator.start();
    oscillator.stop(now + 0.09);
  } catch (e) {
    // 静默失败
  }
}
