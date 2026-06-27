/// 音乐工具函数（与原型 prototype/index.html 同源逻辑）
///
/// 提供频率↔音名换算、cents 偏差计算等，被调音器、评分、和弦库共用。
library;

import 'dart:math' as math;

/// 音名（不含八度）
const List<String> kNoteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

/// 尤克里里标准调音（High-G）：4弦→1弦 = G4 C4 E4 A4
/// Low-G 配置下 4 弦为 G3
class UkuleleString {
  final String name; // 音名，如 "G"
  final int octave; // 八度，如 4
  final int order; // 弦序（4=最粗，1=最细）
  final String label; // 显示标签

  const UkuleleString({
    required this.name,
    required this.octave,
    required this.order,
    required this.label,
  });

  /// 标准频率（Hz）
  double get frequency => noteToFrequency(name, octave);

  /// 完整音名（含八度）
  String get fullName => '$name$octave';

  @override
  String toString() => fullName;
}

/// High-G 标准调音（4弦→1弦，由粗到细）
const List<UkuleleString> kHighGTuning = [
  UkuleleString(name: 'G', octave: 4, order: 4, label: '4弦'),
  UkuleleString(name: 'C', octave: 4, order: 3, label: '3弦'),
  UkuleleString(name: 'E', octave: 4, order: 2, label: '2弦'),
  UkuleleString(name: 'A', octave: 4, order: 1, label: '1弦'),
];

/// Low-G 调音（4 弦低八度）
const List<UkuleleString> kLowGTuning = [
  UkuleleString(name: 'G', octave: 3, order: 4, label: '4弦(低)'),
  UkuleleString(name: 'C', octave: 4, order: 3, label: '3弦'),
  UkuleleString(name: 'E', octave: 4, order: 2, label: '2弦'),
  UkuleleString(name: 'A', octave: 4, order: 1, label: '1弦'),
];

/// 音名+八度 → 频率（A4=440Hz 基准）
double noteToFrequency(String name, int octave) {
  final semitone = kNoteNames.indexOf(name);
  // MIDI 号：A4=69
  final midi = (octave + 1) * 12 + semitone;
  return 440.0 * math.pow(2, (midi - 69) / 12);
}

/// 频率 → {音名, 八度, cents 偏差}
/// cents: 相对最近的标准音的偏差，范围 [-50, 50)
NoteInfo frequencyToNote(double frequency) {
  // MIDI 浮点数：A4(440Hz)=69
  final midiFloat = 69 + 12 * (math.log(frequency / 440) / math.log(2));
  final midiRound = midiFloat.round();
  final cents = ((midiFloat - midiRound) * 100).round();
  final noteIndex = ((midiRound % 12) + 12) % 12;
  final octave = (midiRound / 12).floor() - 1;
  return NoteInfo(
    name: kNoteNames[noteIndex],
    octave: octave,
    cents: cents,
    midi: midiRound,
  );
}

class NoteInfo {
  final String name;
  final int octave;
  final int cents; // 相对标准音偏差 [-50,50)
  final int midi;

  const NoteInfo({
    required this.name,
    required this.octave,
    required this.cents,
    required this.midi,
  });

  String get fullName => '$name$octave';

  /// |cents| <= 阈值 视为调准
  bool isInTune({int threshold = 5}) => cents.abs() <= threshold;

  @override
  String toString() => '$fullName ($cents cents)';
}
