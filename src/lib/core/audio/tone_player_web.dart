/// 音色播放 - Web 实现（Web Audio API 实时合成）
library;

import 'dart:js_interop';
import 'dart:math' as math;
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;

import 'tone_player.dart';

web.AudioContext? _ctx;

/// 音名 → 频率（含升降号，A4=440）
final Map<String, double> _noteFreq = {
  'C': 261.63, 'C#': 277.18, 'D': 293.66, 'D#': 311.13, 'E': 329.63,
  'F': 349.23, 'F#': 369.99, 'G': 392.00, 'G#': 415.30, 'A': 440.00,
  'A#': 466.16, 'B': 493.88,
};

double _freqOf(String name, int octave) {
  final base = _noteFreq[name];
  if (base == null) {
    // 和弦（如 C/Am/F）：取根音
    final rootName = name.replaceAll(RegExp(r'[m7Maj]'), '');
    final rootBase = _noteFreq[rootName] ?? 261.63;
    return rootBase * math.pow(2, octave - 4);
  }
  return base * math.pow(2, octave - 4);
}

void _ensureCtx() {
  _ctx ??= web.AudioContext();
  if (_ctx!.state == 'suspended') {
    _ctx!.resume().toDart;
  }
}

void playToneImpl({
  required String name,
  required int octave,
  required ToneType type,
}) {
  try {
    _ensureCtx();
    final ctx = _ctx!;
    final f = _freqOf(name, octave);
    final now = ctx.currentTime;

    if (type == ToneType.sine) {
      // 标准音高：纯正弦，柔和衰减
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = f;
      gain.gain.setValueAtTime(0.0, now);
      gain.gain.linearRampToValueAtTime(0.3, now + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.6);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(now + 0.6);
    } else {
      // 拨弦音色：基频 + 2/3 次谐波，快速起音 + 指数衰减
      _playStrum(ctx, f, now);
      _playStrum(ctx, f * 2, now, level: 0.4);
      _playStrum(ctx, f * 3, now, level: 0.2);
    }
  } catch (e) {
    // 静默
  }
}

void _playStrum(web.AudioContext ctx, double f, double now, {double level = 1.0}) {
  final osc = ctx.createOscillator();
  final gain = ctx.createGain();
  osc.type = 'sine';
  osc.frequency.value = f;
  // 拨弦包络：快速起音 + 衰减（高频衰减更快）
  final decay = level < 0.3 ? 0.15 : 0.8;
  gain.gain.setValueAtTime(0.0, now);
  gain.gain.linearRampToValueAtTime(0.35 * level, now + 0.003);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + decay);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
  osc.stop(now + decay);
}

/// Web tick（复用音色引擎）
void playTickToneImpl({bool accent = false}) {
  try {
    _ensureCtx();
    final ctx = _ctx!;
    final now = ctx.currentTime;
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = accent ? 1320.0 : 880.0;
    gain.gain.setValueAtTime(0.0, now);
    gain.gain.linearRampToValueAtTime(0.3, now + 0.001);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.08);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(now + 0.09);
  } catch (e) {
    // 静默
  }
}
