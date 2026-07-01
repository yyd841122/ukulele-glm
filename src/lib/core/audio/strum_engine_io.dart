/// 扫弦引擎 - 移动端实现
///
/// 移动端没有 Web Audio API 的实时合成能力，回退到 tone_player 的拨弦音色。
/// 每个"扫弦"实际是依次播放 4 根弦的音色（用 Timer 错峰）。
/// 后期可替换为预录制的真实采样 WAV。
library;

import 'dart:async';
import 'dart:math' as math;

import 'tone_player.dart';
import 'strum_types.dart';

void playStrumImpl({
  required List<double> frequencies,
  required StrumDirection direction,
  required double volume,
}) {
  // 移动端：用 tone_player 的 strum 音色，按方向依次播放
  final order = direction == StrumDirection.down
      ? [0, 1, 2, 3] // 下扫：G→C→E→A（低音先）
      : [3, 2, 1, 0]; // 上扫：A→E→C→G（高音先）

  for (var i = 0; i < order.length; i++) {
    final freq = frequencies[order[i]];
    if (freq <= 0) continue;
    final delay = Duration(milliseconds: i * 20); // 20ms 错峰
    Timer(delay, () {
      final note = _freqToNoteName(freq);
      playTone(name: note, type: ToneType.strum);
    });
  }
}

/// 频率转音名
String _freqToNoteName(double freq) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final midi = (69 + 12 * (math.log(freq / 440) / math.log(2))).round();
  final idx = ((midi % 12) + 12) % 12;
  return names[idx];
}
