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

/// 曲谱库（含公有领域完整曲 + 流行歌示意曲）
const List<Song> kSongs = [
  // ═══ 公有领域入门曲（可整曲弹唱，完整歌词） ═══
  Song(id: 'p1', title: '小星星', artist: '英国民谣', emoji: '⭐', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 80),
  Song(id: 'p2', title: '生日快乐', artist: '经典英文歌', emoji: '🎂', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 90),
  Song(id: 'p3', title: '两只老虎', artist: '法国民谣', emoji: '🐯', colorValue: 0xFFFCA5A5, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 100),
  Song(id: 'p4', title: '欢乐颂', artist: '贝多芬', emoji: '🎵', colorValue: 0xFFBEF264, difficulty: SongDifficulty.beginner, tag: '古典', keyName: 'C', bpm: 100),
  Song(id: 'p5', title: '粉刷匠', artist: '波兰民谣', emoji: '🎨', colorValue: 0xFFFDBA74, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 110),
  Song(id: 'p6', title: '春天来了', artist: '童谣', emoji: '🌸', colorValue: 0xFFF9A8D4, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 95),
  Song(id: 'p7', title: '铃儿响叮当', artist: 'Jingle Bells', emoji: '🔔', colorValue: 0xFFE0F2FE, difficulty: SongDifficulty.beginner, tag: '圣诞', keyName: 'C', bpm: 110),
  Song(id: 'p8', title: '新年好', artist: 'Happy New Year', emoji: '🎉', colorValue: 0xFFFEF3C7, difficulty: SongDifficulty.beginner, tag: '节日', keyName: 'C', bpm: 100),
  Song(id: 'p9', title: '摇篮曲', artist: 'Brahms', emoji: '🌙', colorValue: 0xFFC7D2FE, difficulty: SongDifficulty.beginner, tag: '古典', keyName: 'C', bpm: 60),
  Song(id: 'p10', title: '送别', artist: '李叔同填词', emoji: '🌅', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 75),
  Song(id: 'p11', title: '茉莉花', artist: '中国民谣', emoji: '🤍', colorValue: 0xFFFCE7F3, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 80),
  Song(id: 'p12', title: '康康舞曲', artist: 'Offenbach', emoji: '💃', colorValue: 0xFFFECACA, difficulty: SongDifficulty.beginner, tag: '古典', keyName: 'C', bpm: 120),

  // ═══ 公有领域进阶曲 ═══
  Song(id: 'p13', title: '绿袖子', artist: 'Greensleeves', emoji: '💚', colorValue: 0xFF86EFAC, difficulty: SongDifficulty.intermediate, tag: '民谣', keyName: 'Am', bpm: 70),
  Song(id: 'p14', title: '卡农', artist: 'Pachelbel', emoji: '🎺', colorValue: 0xFFDDD6FE, difficulty: SongDifficulty.intermediate, tag: '古典', keyName: 'C', bpm: 60),
  Song(id: 'p15', title: '致爱丽丝', artist: 'Beethoven', emoji: '🎹', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.fingerstyle, tag: '古典', keyName: 'Am', bpm: 70),
  Song(id: 'p16', title: '四小天鹅', artist: 'Tchaikovsky', emoji: '🩰', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.fingerstyle, tag: '古典', keyName: 'G', bpm: 130),
  Song(id: 'p17', title: '友谊地久天长', artist: 'Auld Lang Syne', emoji: '🤝', colorValue: 0xFFBFDBFE, difficulty: SongDifficulty.intermediate, tag: '民谣', keyName: 'C', bpm: 90),
  Song(id: 'p18', title: '红河谷', artist: 'Red River Valley', emoji: '🏔️', colorValue: 0xFFFCA5A5, difficulty: SongDifficulty.intermediate, tag: '民谣', keyName: 'C', bpm: 85),
  Song(id: 'p19', title: 'Oh Susanna', artist: 'Foster', emoji: '🤠', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 110),
  Song(id: 'p20', title: 'London Bridge', artist: 'Nursery Rhyme', emoji: '🌉', colorValue: 0xFF93C5FD, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 100),
  Song(id: 'p21', title: 'Row Row Row', artist: 'Nursery Rhyme', emoji: '🚣', colorValue: 0xFF6EE7B7, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 100),

  // ═══ 流行歌曲（和弦进行+示意词，非完整歌词） ═══
  // C-G-Am-F 万能进行组
  Song(id: 's1', title: '小幸运', artist: '田馥甄', emoji: '🍀', colorValue: 0xFF86EFAC, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 72),
  Song(id: 's2', title: '晴天', artist: '周杰伦', emoji: '☀️', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'G', bpm: 120),
  Song(id: 's3', title: 'Lemon', artist: '米津玄师', emoji: '🍋', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.intermediate, tag: '日系', keyName: 'C', bpm: 88),
  Song(id: 's4', title: '平凡之路', artist: '朴树', emoji: '🛤️', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 75),
  Song(id: 's5', title: '隐形的翅膀', artist: '张韶涵', emoji: '🪽', colorValue: 0xFFC7D2FE, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 80),
  Song(id: 's7', title: '童年', artist: '罗大佑', emoji: '🧸', colorValue: 0xFFFECACA, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 100),

  // 更多流行（C-G-Am-F / C-Am-F-G 进行）
  Song(id: 's9', title: '后来', artist: '刘若英', emoji: '💧', colorValue: 0xFF93C5FD, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 75),
  Song(id: 's10', title: '稻香', artist: '周杰伦', emoji: '🌾', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 90),
  Song(id: 's11', title: '告白气球', artist: '周杰伦', emoji: '🎈', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 110),
  Song(id: 's12', title: '青花瓷', artist: '周杰伦', emoji: '🏺', colorValue: 0xFF6EE7B7, difficulty: SongDifficulty.intermediate, tag: '流行', keyName: 'C', bpm: 95),
  Song(id: 's13', title: '遇见', artist: '孙燕姿', emoji: '🍂', colorValue: 0xFFFCA5A5, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 80),
  Song(id: 's14', title: '演员', artist: '薛之谦', emoji: '🎭', colorValue: 0xFFDDD6FE, difficulty: SongDifficulty.intermediate, tag: '流行', keyName: 'G', bpm: 70),
  Song(id: 's15', title: '南山南', artist: '马頔', emoji: '🏔️', colorValue: 0xFFBFDBFE, difficulty: SongDifficulty.intermediate, tag: '民谣', keyName: 'Em', bpm: 75),
  Song(id: 's16', title: '成都', artist: '赵雷', emoji: '🌆', colorValue: 0xFFFECACA, difficulty: SongDifficulty.beginner, tag: '民谣', keyName: 'C', bpm: 80),
  Song(id: 's17', title: '理想三旬', artist: '陈鸿宇', emoji: '🛤️', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.intermediate, tag: '民谣', keyName: 'Am', bpm: 85),
  Song(id: 's18', title: '斑马斑马', artist: '宋冬野', emoji: '🦓', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.intermediate, tag: '民谣', keyName: 'G', bpm: 80),

  // 英文流行
  Song(id: 'e1', title: 'I\'m Yours', artist: 'Jason Mraz', emoji: '💙', colorValue: 0xFF67E8F9, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'C', bpm: 75),
  Song(id: 'e2', title: 'Riptide', artist: 'Vance Joy', emoji: '🌊', colorValue: 0xFF67E8F9, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'Am', bpm: 102),
  Song(id: 'e3', title: 'Let It Be', artist: 'Beatles', emoji: '🕊️', colorValue: 0xFFF3F4F6, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'C', bpm: 80),
  Song(id: 'e4', title: 'Hey Soul Sister', artist: 'Train', emoji: '💃', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'C', bpm: 100),
  Song(id: 'e5', title: 'Counting Stars', artist: 'OneRepublic', emoji: '✨', colorValue: 0xFFBFDBFE, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'Am', bpm: 122),
  Song(id: 'e6', title: 'Somewhere', artist: '指弹曲', emoji: '🏝️', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.fingerstyle, tag: '指弹', keyName: 'C', bpm: 90),
  Song(id: 'e7', title: 'Wonderwall', artist: 'Oasis', emoji: '🎸', colorValue: 0xFF86EFAC, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'G', bpm: 90),
  Song(id: 'e8', title: 'Stand By Me', artist: 'Ben E. King', emoji: '🤝', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'C', bpm: 75),
  Song(id: 'e9', title: 'Hallelujah', artist: 'Leonard Cohen', emoji: '🙏', colorValue: 0xFFDDD6FE, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'C', bpm: 70),
  Song(id: 'e10', title: 'Can\'t Help Falling', artist: 'Elvis', emoji: '💫', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'C', bpm: 65),
  Song(id: 'e11', title: 'House of Gold', artist: 'Twenty One Pilots', emoji: '🏠', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.fingerstyle, tag: '英文', keyName: 'C', bpm: 85),
  Song(id: 'e12', title: 'Riptide', artist: 'Vance Joy', emoji: '🏄', colorValue: 0xFF67E8F9, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'Am', bpm: 102),
  Song(id: 'e13', title: 'You Are My Sunshine', artist: 'Traditional', emoji: '☀️', colorValue: 0xFFFBBF24, difficulty: SongDifficulty.beginner, tag: '入门', keyName: 'C', bpm: 90),
  Song(id: 'e14', title: 'Over the Rainbow', artist: 'Israel K.', emoji: '🌈', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.intermediate, tag: '夏威夷', keyName: 'C', bpm: 70),
  Song(id: 'e15', title: 'La Bamba', artist: 'Ritchie Valens', emoji: '🎉', colorValue: 0xFFF87171, difficulty: SongDifficulty.intermediate, tag: '拉丁', keyName: 'C', bpm: 120),
  Song(id: 'e16', title: 'No Woman No Cry', artist: 'Bob Marley', emoji: '🇯🇲', colorValue: 0xFF6EE7B7, difficulty: SongDifficulty.intermediate, tag: '雷鬼', keyName: 'C', bpm: 80),
  Song(id: 'e17', title: 'Twist and Shout', artist: 'Beatles', emoji: '🎤', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'C', bpm: 130),
  Song(id: 'e18', title: 'Don\'t Stop Believin\'', artist: 'Journey', emoji: '🔥', colorValue: 0xFFFCA5A5, difficulty: SongDifficulty.intermediate, tag: '英文', keyName: 'C', bpm: 120),
  Song(id: 'e19', title: 'Hotel California', artist: 'Eagles', emoji: '🏨', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.fingerstyle, tag: '英文', keyName: 'Am', bpm: 75),
  Song(id: 'e20', title: 'Perfect', artist: 'Ed Sheeran', emoji: '💎', colorValue: 0xFFBFDBFE, difficulty: SongDifficulty.beginner, tag: '英文', keyName: 'C', bpm: 80),

  // 指弹/高级
  Song(id: 'f1', title: 'While My Guitar', artist: 'Beatles', emoji: '🎸', colorValue: 0xFF86EFAC, difficulty: SongDifficulty.fingerstyle, tag: '指弹', keyName: 'E', bpm: 100),
  Song(id: 'f2', title: 'Bootcamp', artist: 'Uke Fingerstyle', emoji: '⛺', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.fingerstyle, tag: '指弹', keyName: 'Am', bpm: 95),
  Song(id: 'f3', title: 'Blue Moon', artist: 'Traditional', emoji: '🌕', colorValue: 0xFFDDD6FE, difficulty: SongDifficulty.fingerstyle, tag: '爵士', keyName: 'C', bpm: 80),
  Song(id: 'f4', title: 'Aloha Oe', artist: 'Liliuokalani', emoji: '🌺', colorValue: 0xFFF9A8D4, difficulty: SongDifficulty.fingerstyle, tag: '夏威夷', keyName: 'C', bpm: 75),
  Song(id: 'f5', title: 'Star Spangled', artist: 'Traditional', emoji: '🎆', colorValue: 0xFF93C5FD, difficulty: SongDifficulty.fingerstyle, tag: '古典', keyName: 'C', bpm: 90),
  Song(id: 'f6', title: 'Asturias', artist: 'Albéniz', emoji: '🇪🇸', colorValue: 0xFFFCA5A5, difficulty: SongDifficulty.fingerstyle, tag: '古典', keyName: 'Am', bpm: 140),
  Song(id: 'f7', title: 'Canon Rock', artist: 'JerryC', emoji: '⚡', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.fingerstyle, tag: '古典', keyName: 'C', bpm: 100),
  Song(id: 'f8', title: 'Bohemian', artist: 'Queen', emoji: '👑', colorValue: 0xFFFBCFE8, difficulty: SongDifficulty.fingerstyle, tag: '英文', keyName: 'C', bpm: 80),
  Song(id: 'f9', title: 'Classical Gas', artist: 'Mason Williams', emoji: '🔥', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.fingerstyle, tag: '古典', keyName: 'Am', bpm: 100),
  Song(id: 'f10', title: 'Tears in Heaven', artist: 'Eric Clapton', emoji: '😢', colorValue: 0xFFBFDBFE, difficulty: SongDifficulty.fingerstyle, tag: '英文', keyName: 'A', bpm: 80),

  // 更多中文流行
  Song(id: 'c1', title: '夜空中最亮的星', artist: '逃跑计划', emoji: '🌟', colorValue: 0xFF6EE7B7, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 80),
  Song(id: 'c2', title: '老男孩', artist: '筷子兄弟', emoji: '👴', colorValue: 0xFFFDE68A, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 85),
  Song(id: 'c3', title: '那些年', artist: '胡夏', emoji: '📚', colorValue: 0xFF93C5FD, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 78),
  Song(id: 'c4', title: '七里香', artist: '周杰伦', emoji: '🌸', colorValue: 0xFFF9A8D4, difficulty: SongDifficulty.intermediate, tag: '流行', keyName: 'C', bpm: 90),
  Song(id: 'c5', title: '简单爱', artist: '周杰伦', emoji: '💛', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 95),
  Song(id: 'c6', title: '听海', artist: '张惠妹', emoji: '🌊', colorValue: 0xFF67E8F9, difficulty: SongDifficulty.intermediate, tag: '流行', keyName: 'Am', bpm: 75),
  Song(id: 'c7', title: '宁夏', artist: '梁静茹', emoji: '🌃', colorValue: 0xFFDDD6FE, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 90),
  Song(id: 'c8', title: '暖暖', artist: '梁静茹', emoji: '🌻', colorValue: 0xFFFCD34D, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 95),
  Song(id: 'c9', title: '小苹果', artist: '筷子兄弟', emoji: '🍎', colorValue: 0xFFF87171, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 120),
  Song(id: 'c10', title: '我的歌声里', artist: '曲婉婷', emoji: '🎶', colorValue: 0xFFA5F3FC, difficulty: SongDifficulty.beginner, tag: '流行', keyName: 'C', bpm: 75),
];

/// 「小幸运」示意段落
const List<SongLine> kXiaoXingYunLines = [
  SongLine('（示意段落·非完整歌词）', []),
  SongLine('与你相遇好幸运', [(name: 'C', pos: 0)]),
  SongLine('可我已失去为你', [(name: 'G', pos: 2)]),
  SongLine('泪流满面的权利', [(name: 'Am', pos: 0)]),
  SongLine('但愿在我看不到的天际', [(name: 'F', pos: 4)]),
  SongLine('你张开了双翼', [(name: 'G', pos: 2)]),
  SongLine('遇见你的注定', [(name: 'C', pos: 0)]),
];

/// 通用占位歌词（含和弦教学示意）
const List<SongLine> kPlaceholderLines = [
  SongLine('（曲谱内容整理中）', []),
  SongLine('本曲主要和弦进行：', [(name: 'C', pos: 0)]),
  SongLine('C → G → Am → F', [(name: 'G', pos: 0), (name: 'Am', pos: 4)]),
  SongLine('跟着和弦节奏慢慢练习', []),
  SongLine('熟练后就能完整弹唱啦', [(name: 'C', pos: 0)]),
];

/// 公有领域歌曲歌词
const List<SongLine> kJingleBellsLines = [
  SongLine('Dashing through the snow', [(name: 'C', pos: 0)]),
  SongLine('In a one-horse open sleigh', [(name: 'G', pos: 0)]),
  SongLine('O\'er the fields we go', [(name: 'C', pos: 0)]),
  SongLine('Laughing all the way', [(name: 'G', pos: 0)]),
  SongLine('Bells on bobtail ring', [(name: 'C', pos: 0)]),
  SongLine('Making spirits bright', [(name: 'G', pos: 0)]),
  SongLine('What fun it is to ride', [(name: 'C', pos: 0)]),
  SongLine('A sleighing song tonight', [(name: 'G', pos: 0), (name: 'C', pos: 6)]),
];

const List<SongLine> kHappyNewYearLines = [
  SongLine('Happy new year happy new year', [(name: 'C', pos: 0), (name: 'G', pos: 12)]),
  SongLine('Happy new year to you all', [(name: 'Am', pos: 0), (name: 'F', pos: 10)]),
  SongLine('We wish you a happy new year', [(name: 'C', pos: 0), (name: 'G', pos: 12), (name: 'C', pos: 25)]),
];

const List<SongLine> kSendOffLines = [
  SongLine('长亭外 古道边', [(name: 'C', pos: 0), (name: 'G', pos: 4)]),
  SongLine('芳草碧连天', [(name: 'Am', pos: 0), (name: 'F', pos: 3)]),
  SongLine('晚风拂柳笛声残', [(name: 'C', pos: 0), (name: 'G', pos: 5)]),
  SongLine('夕阳山外山', [(name: 'Am', pos: 0), (name: 'C', pos: 3)]),
];

const List<SongLine> kOhSusannaLines = [
  SongLine('Oh I come from Alabama', [(name: 'C', pos: 0)]),
  SongLine('With my banjo on my knee', [(name: 'G7', pos: 0)]),
  SongLine('I\'m going to Louisiana', [(name: 'C', pos: 0)]),
  SongLine('My true love for to see', [(name: 'G7', pos: 0)]),
  SongLine('Oh Susanna don\'t you cry', [(name: 'C', pos: 0)]),
  SongLine('For I come from Alabama', [(name: 'G7', pos: 0), (name: 'C', pos: 6)]),
];

const List<SongLine> kLondonBridgeLines = [
  SongLine('London Bridge is falling down', [(name: 'C', pos: 0), (name: 'G', pos: 12)]),
  SongLine('Falling down falling down', [(name: 'Am', pos: 0), (name: 'F', pos: 10)]),
  SongLine('London Bridge is falling down', [(name: 'C', pos: 0), (name: 'G', pos: 12)]),
  SongLine('My fair lady', [(name: 'C', pos: 0)]),
];

const List<SongLine> kGreensleevesLines = [
  SongLine('Alas my love you do me wrong', [(name: 'Am', pos: 0)]),
  SongLine('To cast me off discourteously', [(name: 'G', pos: 0)]),
  SongLine('And I have loved you so long', [(name: 'Em', pos: 0)]),
  SongLine('Delighting in your company', [(name: 'Am', pos: 0)]),
  SongLine('Greensleeves was all my joy', [(name: 'Am', pos: 0)]),
  SongLine('Greensleeves was my delight', [(name: 'G', pos: 0)]),
];

const List<SongLine> kStandByMeLines = [
  SongLine('When the night has come', [(name: 'C', pos: 0)]),
  SongLine('And the land is dark', [(name: 'Am', pos: 0)]),
  SongLine('And the moon is the only', [(name: 'F', pos: 0)]),
  SongLine('Light we\'ll see', [(name: 'G', pos: 0)]),
  SongLine('So darlin\' darlin\' stand', [(name: 'C', pos: 0), (name: 'Am', pos: 4)]),
  SongLine('By me', [(name: 'F', pos: 0), (name: 'G', pos: 2), (name: 'C', pos: 5)]),
];

const List<SongLine> kYouAreMySunshineLines = [
  SongLine('You are my sunshine', [(name: 'C', pos: 0)]),
  SongLine('My only sunshine', [(name: 'F', pos: 0)]),
  SongLine('You make me happy', [(name: 'C', pos: 0)]),
  SongLine('When skies are gray', [(name: 'G7', pos: 0)]),
  SongLine('You\'ll never know dear', [(name: 'C', pos: 0)]),
  SongLine('How much I love you', [(name: 'F', pos: 0), (name: 'C', pos: 6)]),
];

const List<SongLine> kAuldLangSyneLines = [
  SongLine('Should auld acquaintance be forgot', [(name: 'C', pos: 0)]),
  SongLine('And never brought to mind', [(name: 'G', pos: 0)]),
  SongLine('Should auld acquaintance be forgot', [(name: 'C', pos: 0)]),
  SongLine('And days of auld lang syne', [(name: 'F', pos: 0), (name: 'C', pos: 8)]),
];

const List<SongLine> kJasmineLines = [
  SongLine('好一朵美丽的茉莉花', [(name: 'C', pos: 0), (name: 'G', pos: 4)]),
  SongLine('好一朵美丽的茉莉花', [(name: 'Am', pos: 0), (name: 'F', pos: 4)]),
  SongLine('芬芳美丽满枝桠', [(name: 'C', pos: 0), (name: 'G', pos: 5)]),
  SongLine('又香又白人人夸', [(name: 'Am', pos: 0), (name: 'C', pos: 4)]),
];

/// 按 id 取歌词
List<SongLine> lyricsFor(Song song) {
  switch (song.id) {
    case 's1': return kXiaoXingYunLines;
    case 'p7': return kJingleBellsLines;
    case 'p8': return kHappyNewYearLines;
    case 'p10': return kSendOffLines;
    case 'p11': return kJasmineLines;
    case 'p13': return kGreensleevesLines;
    case 'p17': return kAuldLangSyneLines;
    case 'p19': return kOhSusannaLines;
    case 'p20': return kLondonBridgeLines;
    case 'e8': return kStandByMeLines;
    case 'e13': return kYouAreMySunshineLines;
    default: return kPlaceholderLines;
  }
}
