/// 音色播放 - 移动端实现（播放预生成 WAV）
library;

import 'package:audioplayers/audioplayers.dart';

import 'tone_player.dart';

final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

void playToneImpl({
  required String name,
  required int octave,
  required ToneType type,
}) async {
  try {
    // 音频文件路径：sounds/tones/sine_C4.wav 或 sounds/strum/strum_C.wav
    final dir = type == ToneType.sine ? 'tones' : 'strum';
    final prefix = type == ToneType.sine ? 'sine_' : 'strum_';
    // 和弦文件名不含八度（如 strum_C.wav），单音含八度（如 sine_C4.wav）
    final isChord = RegExp(r'[m7Maj]').hasMatch(name);
    final fileName = isChord ? '$prefix$name.wav' : '$prefix$name$octave.wav';
    await _player.stop();
    await _player.play(AssetSource('sounds/$dir/$fileName'));
  } catch (e) {
    // 静默
  }
}

/// 移动端 tick（复用之前的 beep）
void playTickToneImpl({bool accent = false}) async {
  try {
    await _player.stop();
    await _player.play(AssetSource(
        accent ? 'sounds/tick_accent.wav' : 'sounds/tick_normal.wav'));
  } catch (e) {
    // 静默
  }
}
