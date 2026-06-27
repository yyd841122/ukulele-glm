/// Tick 发声接口（平台无关）
///
/// 通过条件导入分流：
/// - Web 平台：用 Web Audio API 合成 beep（见 tick_player_web.dart）
/// - 移动端：用 SystemSound.click（见 tick_player_io.dart）
library;

import 'tick_player_stub.dart'
    if (dart.library.js_interop) 'tick_player_web.dart'
    if (dart.library.io) 'tick_player_io.dart';

/// 播放一个节拍 tick
///
/// [accent]=true 时频率更高（重音），区分第一拍。
void playTick({bool accent = false}) => playTickImpl(accent: accent);
