/// 音色播放服务（试听展示用）
///
/// 支持两种音色：
/// - [ToneType.sine]：标准音高（纯正弦，柔和）
/// - [ToneType.strum]：合成拨弦音色（含谐波 + 衰减包络，更接近琴声）
///
/// 跨平台实现通过条件导入自动选择：
/// - Web：tone_player_web.dart（Web Audio API 实时合成）
/// - 移动端：tone_player_io.dart（播放预生成 WAV）
library;

import 'tone_player_stub.dart'
    if (dart.library.js_interop) 'tone_player_web.dart'
    if (dart.library.io) 'tone_player_io.dart';

/// 音色类型
enum ToneType {
  /// 标准音高（纯正弦）
  sine,
  /// 合成拨弦音色
  strum,
}

/// 播放一个音符/和弦的音色（条件导入自动按平台分发）
///
/// [name] 音名，如 "C"、"Am"、"F#"
/// [octave] 八度（单音用，和弦可忽略）
/// [type] 音色类型
void playTone({
  required String name,
  int octave = 4,
  ToneType type = ToneType.strum,
}) =>
    playToneImpl(name: name, octave: octave, type: type);

/// 播放标准 tick（节拍器用）
void playTickTone({bool accent = false}) => playTickToneImpl(accent: accent);
