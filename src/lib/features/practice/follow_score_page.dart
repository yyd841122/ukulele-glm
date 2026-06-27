/// 跟弹评分页面（M6 核心）
///
/// 给定一段应弹音符序列，实时识别用户弹奏，给出 ✓/✗ 反馈，
/// 结束后展示评分报告（音准分 + 完成度 + 逐音判定）。
///
/// MVP 用 C 大调音阶（C4-D4-E4-F4-G4-A4-B4-C5）作为练习序列，
/// 每个音符 2 秒窗口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/scoring_engine.dart';
import '../../core/monetization/feature_gate.dart';
import '../../core/monetization/monetization_model.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';

/// C 大调音阶练习序列（每个音符 2 秒）
final List<TargetNote> _cMajorScale = () {
  const scale = [
    (name: 'C', octave: 4),
    (name: 'D', octave: 4),
    (name: 'E', octave: 4),
    (name: 'F', octave: 4),
    (name: 'G', octave: 4),
    (name: 'A', octave: 4),
    (name: 'B', octave: 4),
    (name: 'C', octave: 5),
  ];
  return [
    for (var i = 0; i < scale.length; i++)
      TargetNote(
        name: scale[i].name,
        octave: scale[i].octave,
        start: Duration(seconds: i * 2),
        duration: const Duration(seconds: 2),
      ),
  ];
}();

class FollowScorePage extends ConsumerStatefulWidget {
  const FollowScorePage({super.key});

  @override
  ConsumerState<FollowScorePage> createState() => _FollowScorePageState();
}

class _FollowScorePageState extends ConsumerState<FollowScorePage> {
  bool _started = false;

  @override
  void dispose() {
    // 离开页面自动停止
    Future.microtask(() {
      if (ref.read(scoringEngineProvider).isRunning) {
        ref.read(scoringEngineProvider.notifier).stop();
      }
    });
    super.dispose();
  }

  Future<void> _tryStart() async {
    // 经 FeatureGate 判定权限（会员接口）
    final result = ref.read(featureGateProvider).check(FeatureKey.followScore);
    if (result is Locked) {
      await showPaywall(context, feature: result.feature, reason: result.reason);
      return;
    }
    setState(() => _started = true);
    try {
      await ref.read(scoringEngineProvider.notifier).start(_cMajorScale);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scoringEngineProvider);
    final finished = !state.isRunning && state.judgements.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  BackButton(color: Colors.white, onPressed: () {
                    if (state.isRunning) {
                      ref.read(scoringEngineProvider.notifier).stop();
                    }
                    Navigator.pop(context);
                  }),
                  const Spacer(),
                  const Text('🎤 跟弹评分',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // 当前音符大显示
            if (!finished)
              _CurrentNoteView(state: state),
            // 评分报告
            if (finished)
              _ScoreReport(state: state, onRetry: () {
                ref.invalidate(scoringEngineProvider);
                setState(() => _started = false);
              }),
            // 开始按钮
            if (!_started)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Text('🎯 音准跟弹练习',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      '依次弹响 C 大调音阶\n系统会实时识别并评分\n（请用调好的琴，安静环境）',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text3, height: 1.8),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _tryStart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                        child: const Text('🎤 开始跟弹',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('🟡 免费用户每日 3 次（会员接口已接入）',
                        style: TextStyle(color: AppColors.text3, fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 当前应弹音符的实时视图
class _CurrentNoteView extends ConsumerWidget {
  final ScoringState state;
  const _CurrentNoteView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.currentIndex >= _cMajorScale.length) {
      return const SizedBox.shrink();
    }
    final target = _cMajorScale[state.currentIndex];
    final cents = state.lastPitchCents;
    final inTune = cents != null && cents.abs() <= 25;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('第 ${state.currentIndex + 1} / ${_cMajorScale.length} 音',
              style: const TextStyle(color: AppColors.text3, fontSize: 13)),
          const SizedBox(height: 16),
          // 大音符显示
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              target.name,
              key: ValueKey(target.fullName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 120,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${target.octave} · ${target.frequency.toStringAsFixed(1)} Hz',
              style: const TextStyle(color: AppColors.text3, fontSize: 16)),
          const SizedBox(height: 24),
          // 实时音准指示
          if (cents != null)
            Column(
              children: [
                Text(
                  inTune ? '✓ 对了！' : '${cents > 0 ? '偏高 ↓' : '偏低 ↑'} ${cents.abs()} cents',
                  style: TextStyle(
                    color: inTune ? AppColors.ok : AppColors.err,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                // 偏差条
                SizedBox(
                  width: 260,
                  child: LinearProgressIndicator(
                    value: ((cents + 50) / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    color: inTune ? AppColors.ok : AppColors.err,
                    minHeight: 6,
                  ),
                ),
              ],
            )
          else
            const Text('弹响琴弦…',
                style: TextStyle(color: AppColors.text3, fontSize: 16)),
          const SizedBox(height: 32),
          // 进度
          _NoteProgress(state: state),
        ],
      ),
    );
  }
}

/// 音符进度条（✓/✗ 序列）
class _NoteProgress extends StatelessWidget {
  final ScoringState state;
  const _NoteProgress({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: List.generate(_cMajorScale.length, (i) {
          Color bg;
          String icon;
          if (i < state.judgements.length) {
            final ok = state.judgements[i].correct;
            bg = ok ? AppColors.ok : AppColors.err;
            icon = ok ? '✓' : '✗';
          } else if (i == state.currentIndex && state.isRunning) {
            bg = AppColors.orange;
            icon = _cMajorScale[i].name;
          } else {
            bg = Colors.white12;
            icon = _cMajorScale[i].name;
          }
          return Container(
            width: 36,
            height: 36,
            decoration:
                BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(icon,
                style: TextStyle(
                    color: (i < state.judgements.length) ||
                            (i == state.currentIndex)
                        ? Colors.white
                        : AppColors.text3,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          );
        }),
      ),
    );
  }
}

/// 评分报告
class _ScoreReport extends StatelessWidget {
  final ScoringState state;
  final VoidCallback onRetry;
  const _ScoreReport({required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final score = state.pitchScore;
    final correct = state.correctCount;
    final total = state.totalNotes;

    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Text('🎉 练习完成！',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            // 总分环
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 12,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                        score >= 80
                            ? AppColors.ok
                            : (score >= 60 ? AppColors.warn : AppColors.err),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$score',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                      const Text('音准分',
                          style: TextStyle(color: AppColors.text3, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 分项
            Row(
              children: [
                _statCard('弹对', '$correct/$total', AppColors.ok),
                const SizedBox(width: 12),
                _statCard('完成度', '${(state.progress * 100).round()}%', AppColors.teal),
              ],
            ),
            const SizedBox(height: 24),
            // 逐音判定
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('逐音判定',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            ...state.judgements.map((j) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(j.target.fullName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Icon(j.correct ? Icons.check_circle : Icons.cancel,
                          color: j.correct ? AppColors.ok : AppColors.err,
                          size: 20),
                      const Spacer(),
                      Text(
                        j.correct
                            ? '误差 ${j.centsError} cents'
                            : '未弹对',
                        style: TextStyle(
                          color: j.correct ? AppColors.ok : AppColors.err,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 28),
            // 再来一次
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('🔁 再练一次',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
