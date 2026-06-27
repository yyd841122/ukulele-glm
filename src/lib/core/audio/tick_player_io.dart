/// Tick 发声 - 移动端实现（audioplayers 播放 beep）
///
/// SystemSound.click 在多数 Android 设备无声，故用 audioplayers 播放
/// 预生成的短促 wav beep（重音/非重音各一个）。
library;

import 'package:audioplayers/audioplayers.dart';

final AudioPlayer _player = AudioPlayer()
  ..setReleaseMode(ReleaseMode.stop); // 播完即停，可重复触发

void playTickImpl({bool accent = false}) async {
  try {
    final source = AssetSource(
        accent ? 'sounds/tick_accent.wav' : 'sounds/tick_normal.wav');
    await _player.stop();
    await _player.play(source);
  } catch (e) {
    // 静默失败，不中断节拍
  }
}
