/// 互动课程数据模型
///
/// P2-3 互动课程体系：把"跟弹评分"包装成有教学逻辑的课程。
/// 每节课由若干"教学段落"(Segment)组成，形成 AI 示范教学闭环：
///   认识 → AI示范 → 该你了(用户弹) → 小结
library;

import 'package:flutter/material.dart';

/// 段落类型
enum SegmentType {
  /// 认识/讲解：展示指法图 + 文字讲解
  intro,
  /// AI 示范：播放音色（让用户听该弹成什么样）
  demo,
  /// 该你了：用户弹，AI 识别评分
  practice,
  /// 小结：本课完成，发奖励
  summary,
}

/// 教学段落
@immutable
class LessonSegment {
  final SegmentType type;
  final String title; // 段落标题
  final String? content; // 讲解文字
  final String? chordName; // 涉及的和弦名（C/Am 等，用于指法图+识别）
  final List<int>? chordFrets; // 和弦指法 [G,C,E,A]
  final String? tip; // 练习提示

  const LessonSegment({
    required this.type,
    required this.title,
    this.content,
    this.chordName,
    this.chordFrets,
    this.tip,
  });
}

/// 课程（一节课）
@immutable
class Course {
  final String id;
  final String title;
  final String subtitle;
  final String emoji;
  final int colorValue; // 主题色
  final int order; // 顺序
  final List<LessonSegment> segments;

  const Course({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.colorValue,
    required this.order,
    required this.segments,
  });

  Color get color => Color(colorValue);
  bool get isFree => order <= 2; // 前2节免费，其余会员
}

/// 必修课课程体系（尤克里里入门，从0到弹唱）
const List<Course> kCourses = [
  Course(
    id: 'c1',
    title: '认识你的尤克里里',
    subtitle: '持琴姿势·认识琴弦·基本发声',
    emoji: '🎸',
    colorValue: 0xFFFFE4D6,
    order: 1,
    segments: [
      LessonSegment(
        type: SegmentType.intro,
        title: '认识 4 根琴弦',
        content: '尤克里里有 4 根弦，从下往上（最细到最粗）分别叫 1弦(A)、2弦(E)、3弦(C)、4弦(G)。\n标准调音是 G-C-E-A（从4弦到1弦）。',
        tip: '记住：最细的 1 弦是 A，最粗的 4 弦是 G',
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听一下各弦的音',
        content: '依次播放 4 根弦的空弦音（G→C→E→A），记住它们由低到高的音高。',
        chordName: 'G', // 标记用，详情页会依次播放 G/C/E/A
        tip: 'play_all_strings', // 特殊标记：依次播放 4 根弦
      ),
      LessonSegment(
        type: SegmentType.summary,
        title: '本课完成！',
        content: '你已经认识了尤克里里的 4 根弦。下一课我们学习调音！',
      ),
    ],
  ),
  Course(
    id: 'c2',
    title: '学会给琴调音',
    subtitle: '使用调音器把 4 根弦调准',
    emoji: '🎼',
    colorValue: 0xFFFFE4D6,
    order: 2,
    segments: [
      LessonSegment(
        type: SegmentType.intro,
        title: '为什么要调音',
        content: '琴弦会随温度、湿度变化跑音。不调准的琴，弹什么都会难听。每次弹琴前都要先调音！',
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '标准调音 G-C-E-A',
        content: '标准调音从 4 弦到 1 弦是 G4-C4-E4-A4。来听一下标准音。',
        chordName: 'A',
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：用调音器调弦',
        content: '打开调音器，依次弹响每根弦，把指针调到居中（绿色）。',
        tip: '练琴页 → 调音器',
      ),
      LessonSegment(
        type: SegmentType.summary,
        title: '本课完成！',
        content: '调音是弹琴的第一步，养成每次弹前先调音的好习惯！',
      ),
    ],
  ),
  Course(
    id: 'c3',
    title: '第一个和弦：C 和 Am',
    subtitle: '两指按弦，10分钟弹响第一个和弦',
    emoji: '🎵',
    colorValue: 0xFFFFE4D6,
    order: 3,
    segments: [
      LessonSegment(
        type: SegmentType.intro,
        title: '认识 C 和弦',
        content: 'C 和弦只需要一根手指！把左手无名指按在 1 弦(A)第 3 品，其余弦弹空弦。',
        chordName: 'C',
        chordFrets: [0, 0, 0, 3],
        tip: '指尖按紧品丝附近，别碰到其他弦',
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听 C 和弦的声音',
        content: '这就是 C 和弦的声音，明亮、稳定。',
        chordName: 'C',
        chordFrets: [0, 0, 0, 3],
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：弹响 C 和弦',
        content: '按好 C 和弦指法，扫一下，让系统识别！',
        chordName: 'C',
        chordFrets: [0, 0, 0, 3],
        tip: '按紧 + 扫干净',
      ),
      LessonSegment(
        type: SegmentType.intro,
        title: '认识 Am 和弦',
        content: 'Am 和弦也只需一根手指！中指按 4 弦(G)第 2 品。',
        chordName: 'Am',
        chordFrets: [2, 0, 0, 0],
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听 Am 和弦的声音',
        content: 'Am 比 C 略带忧郁感。',
        chordName: 'Am',
        chordFrets: [2, 0, 0, 0],
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：弹响 Am 和弦',
        content: '按好 Am 指法，扫一下！',
        chordName: 'Am',
        chordFrets: [2, 0, 0, 0],
      ),
      LessonSegment(
        type: SegmentType.summary,
        title: '🎉 你学会第一个和弦了！',
        content: 'C 和 Am 是最常用的两个和弦，很多歌只用它们就能弹！',
      ),
    ],
  ),
  Course(
    id: 'c4',
    title: 'F 和 G 和弦',
    subtitle: '两指和弦，扩展和弦库',
    emoji: '🎹',
    colorValue: 0xFFFFE4D6,
    order: 4,
    segments: [
      LessonSegment(
        type: SegmentType.intro,
        title: '认识 F 和弦',
        content: 'F 和弦需要两根手指：食指按 2 弦第 1 品，中指按 4 弦第 2 品。',
        chordName: 'F',
        chordFrets: [2, 0, 1, 0],
        tip: 'F 对新手稍难，多练几次',
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听 F 和弦',
        chordName: 'F',
        chordFrets: [2, 0, 1, 0],
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：弹响 F 和弦',
        chordName: 'F',
        chordFrets: [2, 0, 1, 0],
      ),
      LessonSegment(
        type: SegmentType.intro,
        title: '认识 G 和弦',
        content: 'G 和弦三根手指：食指3弦第2品，中指1弦第2品，无名指4弦第3品。',
        chordName: 'G',
        chordFrets: [0, 2, 3, 2],
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听 G 和弦',
        chordName: 'G',
        chordFrets: [0, 2, 3, 2],
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：弹响 G 和弦',
        chordName: 'G',
        chordFrets: [0, 2, 3, 2],
      ),
      LessonSegment(
        type: SegmentType.summary,
        title: '🎉 你掌握了 4 个和弦！',
        content: 'C、Am、F、G 是"万能和弦进行"，能弹唱无数首歌！',
      ),
    ],
  ),
  Course(
    id: 'c5',
    title: '和弦转换 C-G-Am-F',
    subtitle: '练习最经典的和弦进行',
    emoji: '🔁',
    colorValue: 0xFFFFE4D6,
    order: 5,
    segments: [
      LessonSegment(
        type: SegmentType.intro,
        title: '为什么要练转换',
        content: '弹唱的关键是能快速换和弦。C-G-Am-F 是最经典的进行，练熟它就能弹唱大量歌曲。',
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听 C-G-Am-F 进行',
        content: '感受这个进行的节奏感。',
        chordName: 'C',
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：依次弹 4 个和弦',
        content: '去和弦转换练习，依次扫响 C→G→Am→F！',
        tip: '练琴页 → 和弦转换',
      ),
      LessonSegment(
        type: SegmentType.summary,
        title: '🎉 经典进行掌握！',
        content: '能流畅转换 C-G-Am-F，你就具备了弹唱基础！',
      ),
    ],
  ),
  Course(
    id: 'c6',
    title: '第一首弹唱：童年',
    subtitle: '用 4 个和弦弹唱一整首歌',
    emoji: '🎤',
    colorValue: 0xFFFFE4D6,
    order: 6,
    segments: [
      LessonSegment(
        type: SegmentType.intro,
        title: '童年的和弦进行',
        content: '《童年》整首只用 C-G-Am-F 循环！你已经全会了。',
      ),
      LessonSegment(
        type: SegmentType.demo,
        title: '听歌曲节奏',
        content: '每小节 4 拍，C→G→Am→F 循环。',
        chordName: 'C',
      ),
      LessonSegment(
        type: SegmentType.practice,
        title: '该你了：去弹唱《童年》',
        content: '打开曲谱库，找到《童年》，跟着歌词和和弦弹唱！',
        tip: '曲谱库 → 童年',
      ),
      LessonSegment(
        type: SegmentType.summary,
        title: '🎉 你完成第一首歌！',
        content: '恭喜！你已经能弹唱一整首歌了！继续探索更多曲目吧。',
      ),
    ],
  ),
];
