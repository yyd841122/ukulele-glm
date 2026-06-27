/// 和弦库页面：尤克里里和弦查询 + 自绘指法图
///
/// - 顶部搜索框（按和弦名过滤，输入 "C" 出 C/C7/Cm/Cmaj7 等）
/// - 难度筛选标签：全部 / 基础 / 进阶
/// - 和弦卡片：和弦名、难度、自绘指法图（4 弦 × 5 品网格）
/// - 指法数组含义：[G, C, E, A]，值 0=空弦(○)，1-5=按品，-1=不弹(×)
/// - 试听按钮：调用 SystemSound.click 占位（web 无声）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

// ────────────────────────────────────────────────────────────
//  数据模型
// ────────────────────────────────────────────────────────────
enum ChordDifficulty { basic, advanced }

extension ChordDifficultyX on ChordDifficulty {
  String get label => this == ChordDifficulty.basic ? '基础' : '进阶';
}

class UkuleleChord {
  final String name; // 如 "C", "Am"
  final ChordDifficulty difficulty;
  /// 指法：[G, C, E, A]（4 弦→1 弦），值 0=空弦, 1-5=按品, -1=不弹
  final List<int> frets;

  const UkuleleChord({
    required this.name,
    required this.difficulty,
    required this.frets,
  });
}

/// 预置常用和弦（指法 G-C-E-A）
const List<UkuleleChord> kChords = [
  UkuleleChord(name: 'C', difficulty: ChordDifficulty.basic, frets: [0, 0, 0, 3]),
  UkuleleChord(name: 'Am', difficulty: ChordDifficulty.basic, frets: [2, 0, 0, 0]),
  UkuleleChord(name: 'F', difficulty: ChordDifficulty.basic, frets: [2, 0, 1, 0]),
  UkuleleChord(name: 'G', difficulty: ChordDifficulty.basic, frets: [0, 2, 3, 2]),
  UkuleleChord(name: 'Em', difficulty: ChordDifficulty.basic, frets: [0, 4, 3, 2]),
  UkuleleChord(name: 'Dm', difficulty: ChordDifficulty.basic, frets: [2, 2, 1, 0]),
  UkuleleChord(name: 'A', difficulty: ChordDifficulty.basic, frets: [2, 1, 0, 0]),
  UkuleleChord(name: 'G7', difficulty: ChordDifficulty.advanced, frets: [0, 2, 1, 2]),
  UkuleleChord(name: 'C7', difficulty: ChordDifficulty.advanced, frets: [0, 0, 0, 1]),
  UkuleleChord(name: 'Cmaj7', difficulty: ChordDifficulty.advanced, frets: [0, 0, 0, 2]),
  UkuleleChord(name: 'D', difficulty: ChordDifficulty.advanced, frets: [2, 2, 2, 0]),
  UkuleleChord(name: 'E7', difficulty: ChordDifficulty.advanced, frets: [1, 2, 0, 2]),
];

// ────────────────────────────────────────────────────────────
//  Riverpod
// ────────────────────────────────────────────────────────────
final chordSearchProvider = StateProvider<String>((ref) => '');
final chordDifficultyFilterProvider =
    StateProvider<ChordDifficulty?>((ref) => null); // null = 全部

// ────────────────────────────────────────────────────────────
//  UI
// ────────────────────────────────────────────────────────────
class ChordLibraryPage extends ConsumerWidget {
  const ChordLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyword = ref.watch(chordSearchProvider);
    final filter = ref.watch(chordDifficultyFilterProvider);

    final filtered = kChords.where((c) {
      final matchKeyword =
          keyword.isEmpty || c.name.contains(keyword.toUpperCase());
      final matchDiff = filter == null || c.difficulty == filter;
      return matchKeyword && matchDiff;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // 渐变头部
          Container(
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BackButton(color: Colors.white),
                    const SizedBox(width: 4),
                    const Text('🎵 和弦库',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                // 搜索框
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.rBtn),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (v) =>
                        ref.read(chordSearchProvider.notifier).state = v,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.search, color: AppColors.orange),
                      hintText: '搜索和弦，如 C / Am / G7',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 难度筛选
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _FilterChip(
                  label: '全部',
                  selected: filter == null,
                  onTap: () => ref
                      .read(chordDifficultyFilterProvider.notifier)
                      .state = null,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '基础',
                  selected: filter == ChordDifficulty.basic,
                  onTap: () => ref
                      .read(chordDifficultyFilterProvider.notifier)
                      .state = ChordDifficulty.basic,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '进阶',
                  selected: filter == ChordDifficulty.advanced,
                  onTap: () => ref
                      .read(chordDifficultyFilterProvider.notifier)
                      .state = ChordDifficulty.advanced,
                ),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('没有匹配的和弦',
                        style: TextStyle(color: AppColors.text3)))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ChordCard(chord: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.orange : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.text2,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ChordCard extends StatelessWidget {
  final UkuleleChord chord;
  const _ChordCard({required this.chord});

  @override
  Widget build(BuildContext context) {
    final isBasic = chord.difficulty == ChordDifficulty.basic;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 和弦名 + 难度
          Row(
            children: [
              Text(chord.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isBasic ? AppColors.teal : AppColors.purple)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chord.difficulty.label,
                  style: TextStyle(
                    color: isBasic ? AppColors.teal : AppColors.purple,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 指法图
          Expanded(
            child: Center(
              child: ChordDiagram(
                frets: chord.frets,
                fretCount: 5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 试听按钮
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => SystemSound.play(SystemSoundType.click),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🔊', style: TextStyle(fontSize: 13)),
                    SizedBox(width: 4),
                    Text('试听',
                        style: TextStyle(
                            color: AppColors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  和弦指法图（CustomPaint）
//
//  布局：4 列（弦 G-C-E-A，从左到右）× N 行（品格，从上到下，最上为第 1 品）
//  - 顶部行：闷音(×)/空弦(○) 标记
//  - 网格线：横线=品丝，竖线=琴弦
//  - 按弦位置：在该弦对应列、对应品丝之间画黑点
// ────────────────────────────────────────────────────────────
class ChordDiagram extends StatelessWidget {
  final List<int> frets; // [G, C, E, A]
  final int fretCount; // 显示的品格数（默认 5）
  const ChordDiagram({required this.frets, this.fretCount = 5, super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.82,
      child: CustomPaint(
        painter: _ChordDiagramPainter(frets: frets, fretCount: fretCount),
      ),
    );
  }
}

class _ChordDiagramPainter extends CustomPainter {
  final List<int> frets;
  final int fretCount;
  _ChordDiagramPainter({required this.frets, required this.fretCount});

  @override
  void paint(Canvas canvas, Size size) {
    const stringCount = 4;
    final w = size.width;
    final h = size.height;

    final topPad = h * 0.14; // 顶部标记区
    final bottomPad = h * 0.04; // 底部弦名区
    final sidePad = w * 0.12; // 左右留白

    final gridLeft = sidePad;
    final gridRight = w - sidePad;
    final gridTop = topPad;
    final gridBottom = h - bottomPad;
    final gridWidth = gridRight - gridLeft;
    final gridHeight = gridBottom - gridTop;

    final colSpacing = gridWidth / (stringCount - 1);
    final rowSpacing = gridHeight / fretCount;

    final stringPaint = Paint()
      ..color = AppColors.text2
      ..strokeWidth = 1.2;
    final fretPaint = Paint()
      ..color = AppColors.text2
      ..strokeWidth = 1.2;
    final nutPaint = Paint()
      ..color = AppColors.text1
      ..strokeWidth = 3.5; // 上弦枕（加粗）

    final markPaint = Paint()
      ..color = AppColors.text1
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 顶部标记（× / ○）+ 画琴弦
    for (int s = 0; s < stringCount; s++) {
      final x = gridLeft + colSpacing * s;
      final fret = frets[s];
      final cx = x;
      final cy = topPad * 0.5;
      if (fret == -1) {
        // 不弹：×
        const r = 5.0;
        canvas.drawLine(
            Offset(cx - r, cy - r), Offset(cx + r, cy + r), markPaint);
        canvas.drawLine(
            Offset(cx - r, cy + r), Offset(cx + r, cy - r), markPaint);
      } else if (fret == 0) {
        // 空弦：○
        canvas.drawCircle(Offset(cx, cy), 6, markPaint);
      }
      // 画琴弦（竖线）
      canvas.drawLine(Offset(x, gridTop), Offset(x, gridBottom), stringPaint);
    }

    // 上弦枕（最顶横线加粗）
    canvas.drawLine(
        Offset(gridLeft, gridTop), Offset(gridRight, gridTop), nutPaint);

    // 画品丝（横线，从第 1 品到第 fretCount 品）
    for (int f = 1; f <= fretCount; f++) {
      final y = gridTop + rowSpacing * f;
      canvas.drawLine(Offset(gridLeft, y), Offset(gridRight, y), fretPaint);
    }

    // 画按弦黑点
    final dotPaint = Paint()
      ..color = AppColors.text1
      ..style = PaintingStyle.fill;
    final dotRadius = (colSpacing * 0.32).clamp(7.0, 13.0);

    for (int s = 0; s < stringCount; s++) {
      final fret = frets[s];
      if (fret <= 0) continue; // 0 或 -1 不画点
      final x = gridLeft + colSpacing * s;
      final y = gridTop + rowSpacing * (fret - 0.5);
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
    }

    // 弦名标签（底部 G C E A）
    const stringNames = ['G', 'C', 'E', 'A'];
    final nameTp = TextPainter(textDirection: TextDirection.ltr);
    for (int s = 0; s < stringCount; s++) {
      final x = gridLeft + colSpacing * s;
      nameTp.text = TextSpan(
        text: stringNames[s],
        style: const TextStyle(color: AppColors.text3, fontSize: 9),
      );
      nameTp.layout();
      nameTp.paint(canvas, Offset(x - nameTp.width / 2, gridBottom + 4));
    }

    // 品位数字（左侧第一品标 "1"）
    final firstFretTp = TextPainter(textDirection: TextDirection.ltr)
      ..text = const TextSpan(
        text: '1',
        style: TextStyle(color: AppColors.text3, fontSize: 9),
      );
    firstFretTp.layout();
    firstFretTp.paint(
        canvas,
        Offset(gridLeft - 14,
            gridTop + rowSpacing * 0.5 - firstFretTp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ChordDiagramPainter old) =>
      old.frets != frets || old.fretCount != fretCount;
}
