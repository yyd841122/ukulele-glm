/// 课程详情页（互动教学闭环）
///
/// 按段落顺序展示：认识 → AI示范 → 该你了(练习) → 小结
/// - intro：指法图 + 文字讲解
/// - demo：播放音色（让用户听）
/// - practice：引导用户去对应练习页（调音器/和弦转换/曲谱）
/// - summary：完成，发奖励
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/tone_player.dart';
import '../../core/game/game_service.dart';
import '../../core/theme/app_theme.dart';
import '../practice/chord_library_page.dart' show ChordDiagram;
import '../practice/tuner_page.dart';
import '../practice/chord_transition_page.dart';
import '../songs/song_detail_page.dart';
import '../songs/song_model.dart';
import 'course_model.dart';
import 'learn_page.dart' show courseProgressProvider;

class CourseDetailPage extends ConsumerStatefulWidget {
  final Course course;
  const CourseDetailPage({super.key, required this.course});

  @override
  ConsumerState<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends ConsumerState<CourseDetailPage> {
  int _currentSegment = 0;

  LessonSegment get _segment => widget.course.segments[_currentSegment];
  bool get _isLast => _currentSegment >= widget.course.segments.length - 1;

  /// 依次播放 4 根弦的空弦音 G4→C4→E4→A4（让用户听清音高差异）
  void _playAllStrings() async {
    final strings = [
      ('G', 4), ('C', 4), ('E', 4), ('A', 4),
    ];
    for (final (name, octave) in strings) {
      if (!mounted) return;
      playTone(name: name, octave: octave, type: ToneType.sine);
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  void _next() {
    // 记录进度（持久化到 SharedPreferences）
    ref.read(courseProgressProvider.notifier).complete(widget.course.id, _currentSegment + 1);

    if (_isLast) {
      // 课程完成，发经验
      ref.read(gameProvider.notifier).reportPractice(
        const PracticeResult(score: 100, songCompleted: true),
      );
      _showCompleteDialog();
    } else {
      setState(() => _currentSegment++);
    }
  }

  void _showCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🎉 课程完成！', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎓', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(_segment.content ?? '恭喜完成本课！',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.text2)),
            const SizedBox(height: 8),
            const Text('✨ 获得 100 经验值',
                style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.bold)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 关对话框
              Navigator.pop(context); // 回课程列表
            },
            child: const Text('继续学习', style: TextStyle(color: AppColors.orange)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏：返回 + 进度
            _buildHeader(),
            // 段落内容
            Expanded(child: _buildSegment()),
            // 底部操作
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: Column(
        children: [
          Row(
            children: [
              const BackButton(color: Colors.white),
              const SizedBox(width: 4),
              Expanded(
                child: Text(widget.course.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              Text(
                '${_currentSegment + 1}/${widget.course.segments.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 段落进度点
          Row(
            children: List.generate(widget.course.segments.length, (i) {
              final done = i < _currentSegment;
              final now = i == _currentSegment;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 4,
                  decoration: BoxDecoration(
                    color: done || now ? Colors.white : Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment() {
    final seg = _segment;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 段落类型标签
          _segmentTypeTag(seg.type),
          const SizedBox(height: 12),
          // 标题
          Text(seg.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // 指法图（intro/demo/practice 且有和弦时显示）
          if (seg.chordFrets != null) ...[
            Center(
              child: Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Text(seg.chordName ?? '',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(child: ChordDiagram(frets: seg.chordFrets!, fretCount: 5)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          // 内容文字
          if (seg.content != null)
            Text(seg.content!,
                style: const TextStyle(fontSize: 15, height: 1.8, color: AppColors.text1)),
          // 提示
          if (seg.tip != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(seg.tip!,
                        style: const TextStyle(fontSize: 13, color: AppColors.teal)),
                  ),
                ],
              ),
            ),
          ],
          // demo：试听按钮
          if (seg.type == SegmentType.demo) ...[
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (seg.tip == 'play_all_strings') {
                    // 依次播放 4 根弦 G→C→E→A
                    _playAllStrings();
                  } else if (seg.chordName != null) {
                    playTone(name: seg.chordName!, type: ToneType.strum);
                  }
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('🎧 点击试听'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ],
          // practice：跳转练习入口
          if (seg.type == SegmentType.practice && seg.tip != null) ...[
            const SizedBox(height: 24),
            _buildPracticeEntry(seg),
          ],
          // summary
          if (seg.type == SegmentType.summary) ...[
            const SizedBox(height: 24),
            const Center(child: Text('🎓', style: TextStyle(fontSize: 72))),
          ],
        ],
      ),
    );
  }

  /// 根据段落的 tip 推断跳转目标
  Widget _buildPracticeEntry(LessonSegment seg) {
    VoidCallback onTap;
    String label;
    if (seg.tip!.contains('调音器')) {
      label = '🎼 打开调音器';
      onTap = () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const TunerPage()));
    } else if (seg.tip!.contains('和弦转换')) {
      label = '🔁 打开和弦转换';
      onTap = () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ChordTransitionPage()));
    } else if (seg.tip!.contains('曲谱库') || seg.tip!.contains('童年')) {
      final song = kSongs.where((s) => s.title.contains('童年')).firstOrNull;
      label = '🎼 打开《童年》曲谱';
      onTap = () {
        if (song != null) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => SongDetailPage(song: song)));
        }
      };
    } else {
      label = '▶ 开始练习';
      onTap = () {};
    }
    return Center(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
    );
  }

  Widget _segmentTypeTag(SegmentType type) {
    final config = switch (type) {
      SegmentType.intro => ('📖 认识', AppColors.teal),
      SegmentType.demo => ('🎧 AI 示范', AppColors.orange),
      SegmentType.practice => ('🎤 该你了', AppColors.purple),
      SegmentType.summary => ('✅ 小结', AppColors.ok),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: config.$2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(config.$1,
          style: TextStyle(
              color: config.$2, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line.withValues(alpha: 0.5))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _next,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(
            _isLast ? '完成课程 🎉' : '下一步 →',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
