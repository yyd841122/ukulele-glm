/// 曲谱数据模型 + 示例数据
///
/// 定义 Song / SongLine 结构，预置 8 首示例曲谱。
/// 「小幸运」含带和弦位置的完整段落，其余为元数据 + 占位歌词。
library;

import 'package:flutter/material.dart';

/// 难度枚举
enum SongDifficulty {
  beginner('入门'),
  intermediate('进阶'),
  fingerstyle('指弹');

  final String label;
  const SongDifficulty(this.label);

  int get stars => switch (this) {
        SongDifficulty.beginner => 2,
        SongDifficulty.intermediate => 3,
        SongDifficulty.fingerstyle => 5,
      };
}

/// 一行歌词（含和弦位置）
///
/// [chords] 中 pos 为和弦标签起点在 lyrics 字符串中的字符偏移。
class SongLine {
  final String lyrics;
  final List<({String name, int pos})> chords;
  const SongLine(this.lyrics, [this.chords = const []]);
}

class Song {
  final String id;
  final String title;
  final String artist;
  final String emoji;
  final int colorValue; // 0xFFRRGGBB
  final SongDifficulty difficulty;
  final String tag;
  final String keyName;
  final int bpm;

  /// 进阶/指弹为会员曲目
  bool get isMemberOnly =>
      difficulty == SongDifficulty.intermediate ||
      difficulty == SongDifficulty.fingerstyle;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.emoji,
    required this.colorValue,
    required this.difficulty,
    required this.tag,
    required this.keyName,
    required this.bpm,
  });

  /// 封面渐变浅色
  Color get colorLight => Color(colorValue).withValues(alpha: 0.55);
  Color get color => Color(colorValue);
}

/// 示例曲谱（含 3 首可整曲弹唱的练习曲）
const List<Song> kSongs = [
  // 可整曲弹唱的入门曲
  Song(id: 'p1', title: '小星星', artist: '英国民谣', emoji: '⭐', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 80),
  Song(id: 'p2', title: '生日快乐', artist: '经典英文歌', emoji: '🎂', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 90),
  Song(id: 'p3', title: '两只老虎', artist: '法国民谣', emoji: '🐯', colorValue: 0xFFFCA5A5, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 100),
  Song(id: 'p4', title: '欢乐颂', artist: '贝多芬', emoji: '🎵', colorValue: 0xFFBEF264, difficulty: SongDifficulty.beginner, tag: '古典', keyName: 'C', bpm: 100),
  Song(id: 'p5', title: '粉刷匠', artist: '波兰民谣', emoji: '🎨', colorValue: 0xFFFDBA74, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 110),
  Song(id: 'p6', title: '春天来了', artist: '童谣', emoji: '🌸', colorValue: 0xFFF9A8D4, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 95),
  // 其他曲谱
  Song(id: 's1', title: '小幸运', artist: '田馥甄', emoji: '🍀', colorValue: 0xFF86EFAC, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 72),
  Song(id: 's2', title: '晴天', artist: '周杰伦', emoji: '☀️', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'G', bpm: 120),
  Song(id: 's3', title: 'Lemon', artist: '米津玄师', emoji: '🍋', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.intermediate, tag: '日系', keyName: 'C', bpm: 88),
  Song(id: 's4', title: '平凡之路', artist: '朴树', emoji: '🛤️', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 75),
  Song(id: 's5', title: 'Somewhere', artist: '指弹曲', emoji: '🏝️', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.fingerstyle, tag: '指弹', keyName: 'C', bpm: 90),
  Song(id: 's6', title: '隐形的翅膀', artist: '张韶涵', emoji: '🪽', colorValue: 0xFFC7D2FE, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 80),
  Song(id: 's7', title: '童年', artist: '罗大佑', emoji: '🧸', colorValue: 0xFFFECACA, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 100),
  Song(id: 's8', title: 'Riptide', artist: 'Vance Joy', emoji: '🌊', colorValue: 0xFF67E8F9, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'Am', bpm: 102),
];

/// 「小幸运」完整带和弦段落
const List<SongLine> kXiaoXingYunLines = [
  SongLine('我听见雨滴落在青青草地', []),
  SongLine('我听见远方下起钟声响起', []),
  SongLine('可是我没有听见你的声音', []),
  SongLine('认真 呼唤我姓名', [(name: 'G', pos: 2)]),
  SongLine('爱上你的时候还不懂感情', []),
  SongLine('离别了才觉得刻骨铭心', []),
  SongLine('为什么没有发现遇见了你', []),
  SongLine('是生命最好的 事情', [(name: 'G', pos: 7)]),
];

/// 通用占位歌词
const List<SongLine> kPlaceholderLines = [
  SongLine('（曲谱内容整理中）', []),
  SongLine('这是示例歌词第一行', []),
  SongLine('和弦标注会显示在这里', [(name: 'C', pos: 0), (name: 'G', pos: 4)]),
  SongLine('跟着节拍慢慢练习', []),
  SongLine('熟练后就能完整弹唱啦', []),
];

/// 按 id 取歌词
List<SongLine> lyricsFor(Song song) =>
    song.id == 's1' ? kXiaoXingYunLines : kPlaceholderLines;
