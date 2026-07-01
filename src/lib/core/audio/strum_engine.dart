/// 扫弦配乐引擎（条件导入接口）
///
/// 提供真实的尤克里里扫弦音色（多弦错峰触发）+ 节奏型循环调度。
/// 替代 tone_player 的简单拨弦音，用于整曲弹唱的配乐。
library;

import 'dart:async';

import 'strum_types.dart';
export 'strum_types.dart' show StrumDirection;

import 'strum_engine_stub.dart'
    if (dart.library.js_interop) 'strum_engine_web.dart'
    if (dart.library.io) 'strum_engine_io.dart';

/// 尤克里里标准调音的 4 根弦频率（High-G）
/// [G4, C4, E4, A4] = [392.0, 261.63, 329.63, 440.0]
const kUkuleleStringFreqs = [392.0, 261.63, 329.63, 440.0];

/// 和弦名 → 4 根弦的实际频率（含按品升降）
/// frets 格式 [G弦品, C弦品, E弦品, A弦品]，0=空弦
List<double> chordToFrequencies(List<int> frets) {
  return List.generate(4, (i) {
    final fret = frets[i];
    if (fret < 0) return 0.0; // 闷音不弹
    return kUkuleleStringFreqs[i] * _semitoneRatio(fret);
  });
}

/// 半音比率：2^(n/12)
double _semitoneRatio(int semitones) {
  double r = 1.0;
  for (var i = 0; i < semitones.abs(); i++) {
    r *= 1.0594630943592953; // 2^(1/12)
  }
  return r;
}

/// 播放一次扫弦
///
/// [frequencies] 4 根弦的频率（Hz），0 表示不弹
/// [direction] 下扫（低音先响）或上扫（高音先响）
/// [volume] 音量 0~1
void playStrum({
  required List<double> frequencies,
  StrumDirection direction = StrumDirection.down,
  double volume = 0.15,
}) =>
    playStrumImpl(
      frequencies: frequencies,
      direction: direction,
      volume: volume,
    );

/// 按和弦指法播放一次扫弦（便捷方法）
void playStrumByFrets({
  required List<int> frets,
  StrumDirection direction = StrumDirection.down,
  double volume = 0.15,
}) {
  playStrum(
    frequencies: chordToFrequencies(frets),
    direction: direction,
    volume: volume,
  );
}

// ════════════════════════════════════════════════════════════════
// 节奏型调度器
// ════════════════════════════════════════════════════════════════

/// 一个扫弦动作（在节奏型中的位置）
class StrumAction {
  final int beatOffset; // 从小节开始的 8 分音符偏移（0-7）
  final StrumDirection direction;
  const StrumAction(this.beatOffset, this.direction);
}

/// 常用扫弦节奏型
/// D=下扫，U=上扫，- = 不弹（休止）
/// 以 8 分音符为单位，一小节 8 个位置
class StrumPattern {
  final String name;
  final List<StrumAction> actions;
  const StrumPattern({required this.name, required this.actions});
}

/// 经典民谣扫弦：D - D U - U D U
/// 适用：大多数流行弹唱（4/4 拍）
const kPatternFolk = StrumPattern(
  name: '民谣扫弦',
  actions: [
    StrumAction(0, StrumDirection.down),  // 第1拍 D
    StrumAction(2, StrumDirection.down),  // 第2拍 D
    StrumAction(3, StrumDirection.up),    // 第2拍后半 U
    StrumAction(4, StrumDirection.down),  // 第3拍 D
    StrumAction(5, StrumDirection.up),    // 第3拍后半 U
    StrumAction(6, StrumDirection.down),  // 第4拍 D
    StrumAction(7, StrumDirection.up),    // 第4拍后半 U
  ],
);

/// 简单扫弦：D - - - D - - -（每小节2次下扫，最简单）
const kPatternSimple = StrumPattern(
  name: '简单扫弦',
  actions: [
    StrumAction(0, StrumDirection.down),  // 第1拍 D
    StrumAction(4, StrumDirection.down),  // 第3拍 D
  ],
);

/// 节奏型调度器
///
/// 按 BPM 循环播放扫弦节奏型，和弦可随时切换。
/// 用法：
/// ```dart
/// final sched = StrumPatternScheduler(bpm: 80, pattern: kPatternFolk, volume: 0.15);
/// sched.start();           // 开始循环
/// sched.setChord(frets);   // 切换和弦（立即生效）
/// sched.stop();            // 停止
/// ```
class StrumPatternScheduler {
  final int bpm;
  final StrumPattern pattern;
  final double volume;
  final void Function(StrumDirection)? onStrum; // 回调（UI 同步用，可选）

  Timer? _timer;
  int _eighthNoteIdx = 0; // 当前 8 分音符 index（全局累计）
  List<int> _currentFrets = [0, 0, 0, 3]; // 当前和弦指法（默认 C）

  StrumPatternScheduler({
    required this.bpm,
    required this.pattern,
    this.volume = 0.15,
    this.onStrum,
  });

  /// 8 分音符间隔（毫秒）
  int get _eighthMs => 60000 ~/ bpm ~/ 2;

  /// 设置当前和弦指法
  void setChord(List<int> frets) {
    _currentFrets = frets;
  }

  /// 开始循环
  void start() {
    _eighthNoteIdx = 0;
    // 立即播第一拍
    _processEighth(0);
    _eighthNoteIdx = 1;
    _timer = Timer.periodic(Duration(milliseconds: _eighthMs), (_) {
      _processEighth(_eighthNoteIdx % 8);
      _eighthNoteIdx++;
    });
  }

  /// 处理一个 8 分音符位置
  void _processEighth(int posInMeasure) {
    // 找当前位置是否有扫弦动作
    for (final action in pattern.actions) {
      if (action.beatOffset == posInMeasure) {
        playStrumByFrets(
          frets: _currentFrets,
          direction: action.direction,
          volume: volume,
        );
        onStrum?.call(action.direction);
        break;
      }
    }
  }

  /// 停止
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 是否在运行
  bool get isRunning => _timer != null;
}
