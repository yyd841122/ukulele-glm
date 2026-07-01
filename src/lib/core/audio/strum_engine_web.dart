/// 扫弦引擎 - Web 实现（Web Audio API 多弦合成）
///
/// 每次扫弦 = 4 根弦以 15-25ms 时差依次触发：
/// - 每根弦用 3 个谐波 OscillatorNode（基频 + 2倍 + 3倍）+ 低通滤波 + 指数衰减包络
/// - 下扫：G→C→E→A（低音弦先响），力度递增
/// - 上扫：A→E→C→G（高音弦先响），力度递减
/// - 整体音量可控（配乐默认 0.15，避免干扰麦克风识别）
library;

import 'dart:js_interop';

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

    // 触发顺序：下扫 G→A（低先），上扫 A→G（高先）
    final order = direction == StrumDirection.down
        ? [0, 1, 2, 3]
        : [3, 2, 1, 0];

    for (var i = 0; i < order.length; i++) {
      final freq = frequencies[order[i]];
      if (freq <= 0) continue;

      // 错峰时间：下扫每弦间隔 15ms，上扫 10ms（上扫更快）
      final strumDelay = (direction == StrumDirection.down ? 0.015 : 0.010) * i;
      // 力度：下扫从强到弱，上扫从弱到强
      final dynamics = direction == StrumDirection.down
          ? 1.0 - i * 0.12 // 下扫：1.0, 0.88, 0.76, 0.64
          : 0.7 + i * 0.10; // 上扫：0.7, 0.8, 0.9, 1.0

      _playString(ctx, now + strumDelay, freq, volume * dynamics, direction);
    }
  } catch (_) {
    // 静默忽略
  }
}

/// 播放单根弦的音色（3 谐波 + 低通 + 衰减包络）
void _playString(web.AudioContext ctx, double startTime, double freq, double vol, StrumDirection direction) {
  // 衰减时长：低频弦更长（更像低音弦的延音）
  final decay = freq < 300 ? 0.8 : (freq < 500 ? 0.5 : 0.3);

  // 3 个谐波：基频（最强）、2倍（中）、3倍（弱）
  final harmonics = [
    (freq, 1.0),        // 基频
    (freq * 2, 0.4),    // 2 倍频
    (freq * 3, 0.15),   // 3 倍频
  ];

  // 总增益节点（控制这根弦的总音量）
  final stringGain = ctx.createGain();
  // 起音 + 指数衰减包络
  stringGain.gain.setValueAtTime(0.0, startTime);
  stringGain.gain.linearRampToValueAtTime(vol, startTime + 0.003); // 3ms 起音
  stringGain.gain.exponentialRampToValueAtTime(0.0001, startTime + decay); // 指数衰减

  // 低通滤波（去掉高频毛刺，让音色更暖）
  final filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = freq * 6; // 截止频率 = 基频 × 6
  filter.Q.value = 1.0;

  // 连接：弦谐波 → 低通 → 增益 → 输出
  for (final (h, level) in harmonics) {
    final osc = ctx.createOscillator();
    osc.type = 'triangle'; // 三角波比正弦更像弦乐（含奇次谐波）
    osc.frequency.value = h;

    final oscGain = ctx.createGain();
    oscGain.gain.value = level;

    osc.connect(oscGain);
    oscGain.connect(filter);
    osc.start(startTime);
    osc.stop(startTime + decay + 0.05); // 多留 50ms 确保衰减完成
  }

  filter.connect(stringGain);
  stringGain.connect(ctx.destination);
}

/// 获取共享的 AudioContext（复用，不每次新建）
web.AudioContext? _cachedCtx;

web.AudioContext? _getCtx() {
  if (_cachedCtx != null) {
    // 如果 context 被关闭了，重新创建
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
