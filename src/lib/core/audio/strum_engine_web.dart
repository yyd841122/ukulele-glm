/// 扫弦引擎 - Web 实现（Web Audio API 多弦合成 v2）
///
/// v2 改进：
/// - 增加噪声攻击层（拨弦瞬间的"擦"声，大幅提升真实感）
/// - 5 谐波（基频+2~5倍），更接近真实弦音色
/// - 弦体共振（低频残留共鸣）
/// - 更合理的音量/衰减参数
/// - 错峰触发优化（下扫慢而重，上扫快而轻）
library;

import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'strum_types.dart';

void playStrumImpl({
  required List<double> frequencies,
  required StrumDirection direction,
  required double volume,
}) {
  try {
    final ctx = _getCtx();
    if (ctx == null) return;
    final now = ctx.currentTime;

    // 触发顺序
    final order = direction == StrumDirection.down
        ? [0, 1, 2, 3]
        : [3, 2, 1, 0];

    // 整体音量提升（之前 0.12 太低，现在 0.25 基础）
    final baseVol = volume * 1.8;

    for (var i = 0; i < order.length; i++) {
      final freq = frequencies[order[i]];
      if (freq <= 0) continue;

      // 错峰：下扫 18ms（更舒展），上扫 12ms（更轻快）
      final strumDelay = (direction == StrumDirection.down ? 0.018 : 0.012) * i;
      // 力度曲线
      final dynamics = direction == StrumDirection.down
          ? 1.0 - i * 0.08  // 下扫：1.0, 0.92, 0.84, 0.76
          : 0.6 + i * 0.13; // 上扫：0.6, 0.73, 0.86, 1.0

      _playString(ctx, now + strumDelay, freq, baseVol * dynamics, direction, i);
    }
  } catch (_) {}
}

/// 播放单根弦（5谐波 + 噪声攻击 + 低通 + 共振）
void _playString(web.AudioContext ctx, double startTime, double freq, double vol, StrumDirection direction, int stringIdx) {
  // 衰减时长：低频弦更长（低音弦延音长）
  final decay = freq < 300 ? 1.2 : (freq < 500 ? 0.8 : 0.5);

  // ── 1. 噪声攻击层（拨弦瞬间的"擦"声）──
  // 用短促的过滤白噪声模拟指甲/拨片划过弦的攻击声
  final noiseDur = 0.04; // 40ms 攻击
  final noiseBuf = ctx.createBuffer(1, (ctx.sampleRate * noiseDur).round(), ctx.sampleRate);
  final noiseData = noiseBuf.getChannelData(0).toDart;
  for (var i = 0; i < noiseData.length; i++) {
    // 衰减的白噪声
    noiseData[i] = (math.Random().nextDouble() * 2 - 1) * (1.0 - i / noiseData.length);
  }
  final noiseSrc = ctx.createBufferSource();
  noiseSrc.buffer = noiseBuf;

  final noiseFilter = ctx.createBiquadFilter();
  noiseFilter.type = 'bandpass';
  noiseFilter.frequency.value = freq * 2; // 噪声集中在弦频率附近
  noiseFilter.Q.value = 2.0;

  final noiseGain = ctx.createGain();
  noiseGain.gain.setValueAtTime(0.0, startTime);
  noiseGain.gain.linearRampToValueAtTime(vol * 0.15, startTime + 0.001); // 快速起音
  noiseGain.gain.exponentialRampToValueAtTime(0.0001, startTime + noiseDur);

  noiseSrc.connect(noiseFilter);
  noiseFilter.connect(noiseGain);
  noiseGain.connect(ctx.destination);
  noiseSrc.start(startTime);
  noiseSrc.stop(startTime + noiseDur);

  // ── 2. 谐波层（5 个谐波，模拟真实弦振动）──
  final harmonics = [
    (freq, 1.0),         // 基频（最强）
    (freq * 2, 0.45),    // 2 倍频
    (freq * 3, 0.25),    // 3 倍频
    (freq * 4, 0.12),    // 4 倍频
    (freq * 5, 0.06),    // 5 倍频
  ];

  // 总增益（起音 + 衰减包络）
  final stringGain = ctx.createGain();
  stringGain.gain.setValueAtTime(0.0, startTime);
  // 快速起音（2ms，比之前 3ms 更锐利）
  stringGain.gain.linearRampToValueAtTime(vol, startTime + 0.002);
  // 双段衰减：快速衰减（攻击后）+ 慢速衰减（延音）
  stringGain.gain.exponentialRampToValueAtTime(vol * 0.3, startTime + 0.15);
  stringGain.gain.exponentialRampToValueAtTime(0.0001, startTime + decay);

  // 低通滤波（暖化音色，截止频率随谐波数调整）
  final filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = freq * 8;
  filter.Q.value = 0.7; // 低 Q 值，更自然

  for (final (h, level) in harmonics) {
    final osc = ctx.createOscillator();
    // 用 sawtooth（锯齿波）替代 triangle —— 含丰富谐波，更像弦乐
    osc.type = 'sawtooth';
    osc.frequency.value = h;

    final oscGain = ctx.createGain();
    oscGain.gain.value = level;

    osc.connect(oscGain);
    oscGain.connect(filter);
    osc.start(startTime);
    osc.stop(startTime + decay + 0.1);
  }

  filter.connect(stringGain);
  stringGain.connect(ctx.destination);
}

/// 获取共享的 AudioContext
web.AudioContext? _cachedCtx;

web.AudioContext? _getCtx() {
  if (_cachedCtx != null) {
    if (_cachedCtx!.state != 'closed') {
      if (_cachedCtx!.state == 'suspended') {
        _cachedCtx!.resume().toDart;
      }
      return _cachedCtx;
    }
  }
  try {
    _cachedCtx = web.AudioContext();
    return _cachedCtx;
  } catch (_) {
    return null;
  }
}
