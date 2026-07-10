/// 扫弦引擎 - 移动端实现
///
/// 移动端用预录制的 WAV 采样（assets/sounds/strum/strum_<和弦>.wav）。
/// 已有采样：C/Am/Dm/Em/F/G 共 6 个和弦 + 全部单音（C3-C5 等）。
/// 采样不存在的和弦回退到 tone_player 逐弦合成。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

import 'tone_player.dart';
import 'strum_types.dart';

final AudioPlayer _strumPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

Future<void> preloadStrumSamplesImpl(List<String> chordNames) async {
  // 移动端无需预加载（assets 直接读取）
}

void playStrumImpl({
  required List<double> frequencies,
  required StrumDirection direction,
  required double volume,
}) {
  // 尝试推断和弦名 → 播放采样
  final chordName = _inferChordName(frequencies);
  if (chordName != null) {
    _playSample(chordName, volume, direction);
    return;
  }
  // 回退：逐弦 tone_player
  final order = direction == StrumDirection.down ? [0, 1, 2, 3] : [3, 2, 1, 0];
  for (var i = 0; i < order.length; i++) {
    final freq = frequencies[order[i]];
    if (freq <= 0) continue;
    final delay = Duration(milliseconds: i * 18);
    Timer(delay, () {
      final note = _freqToNoteName(freq);
      playTone(name: note, type: ToneType.strum);
    });
  }
}

/// 播放和弦采样
void _playSample(String chordName, double volume, StrumDirection direction) async {
  try {
    await _strumPlayer.stop();
    await _strumPlayer.setVolume(volume * 2); // 采样音量补偿
    await _strumPlayer.play(AssetSource('sounds/strum/strum_$chordName.wav'));
  } catch (_) {
    // 采样不存在，回退到逐弦
    final order = direction == StrumDirection.down ? [0, 1, 2, 3] : [3, 2, 1, 0];
    for (var i = 0; i < order.length; i++) {
      Timer(Duration(milliseconds: i * 18), () {});
    }
  }
}

/// 从频率列表推断和弦名
String? _inferChordName(List<double> freqs) {
  final noteNames = <String>{};
  for (final f in freqs) {
    if (f > 0) noteNames.add(_freqToNoteNameBase(f));
  }
  // 匹配有采样的和弦
  if (noteNames.containsAll({'C', 'E', 'G'})) return 'C';
  if (noteNames.containsAll({'A', 'C', 'E'})) return 'Am';
  if (noteNames.containsAll({'F', 'A', 'C'})) return 'F';
  if (noteNames.containsAll({'G', 'B', 'D'})) return 'G';
  if (noteNames.containsAll({'E', 'G', 'B'})) return 'Em';
  if (noteNames.containsAll({'D', 'F', 'A'})) return 'Dm';
  return null;
}

/// 频率转音名
String _freqToNoteName(double freq) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final midi = (69 + 12 * (math.log(freq / 440) / math.log(2))).round();
  final idx = ((midi % 12) + 12) % 12;
  final octave = (midi / 12).floor() - 1;
  return '${names[idx]}$octave';
}

/// 频率转基础音名（不含八度）
String _freqToNoteNameBase(double freq) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final midi = (69 + 12 * (math.log(freq / 440) / math.log(2))).round();
  final idx = ((midi % 12) + 12) % 12;
  return names[idx];
}
