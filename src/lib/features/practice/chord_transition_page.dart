/// 和弦转换练习页面（提速训练）
///
/// 给定和弦进行，用户依次扫响每个和弦，系统检测是否换对（评根音音高）。
/// 计算平均转换时长，给出转换速度评分。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/chord_recognizer.dart';
import '../../core/audio/pitch_service.dart';
import '../../core/theme/app_theme.dart';
import 'chord_library_page.dart' show ChordDiagram;

/// 和弦进行
@immutable
class ChordProgression {
  final String name;
  final List<({String name, int octave, List<int> frets})> chords;
  const ChordProgression({required this.name, required this.chords});
}

const List<ChordProgression> kProgressions = [
  ChordProgression(name: 'C-G-Am-F 经典进行', chords: [
    (name: 'C', octave: 4, frets: [0, 0, 0, 3]),
    (name: 'G', octave: 4, frets: [0, 2, 3, 2]),
    (name: 'Am', octave: 4, frets: [2, 0, 0, 0]),
    (name: 'F', octave: 4, frets: [2, 0, 1, 0]),
  ]),
  ChordProgression(name: 'C-Am-F-G 民谣进行', chords: [
    (name: 'C', octave: 4, frets: [0, 0, 0, 3]),
    (name: 'Am', octave: 4, frets: [2, 0, 0, 0]),
    (name: 'F', octave: 4, frets: [2, 0, 1, 0]),
    (name: 'G', octave: 4, frets: [0, 2, 3, 2]),
  ]),
  ChordProgression(name: 'G-D-Em-C 流行进行', chords: [
    (name: 'G', octave: 4, frets: [0, 2, 3, 2]),
    (name: 'D', octave: 4, frets: [2, 2, 2, 0]),
    (name: 'Em', octave: 4, frets: [0, 4, 3, 2]),
    (name: 'C', octave: 4, frets: [0, 0, 0, 3]),
  ]),
];

/// 转换练习状态
@immutable
class TransitionState {
  final bool isRunning;
  final int currentIndex; // 当前要换到的和弦
  final List<int> transitionMs; // 每次转换耗时（毫秒）
  final bool finished;

  const TransitionState({
    this.isRunning = false,
    this.currentIndex = 0,
    this.transitionMs = const [],
    this.finished = false,
  });

  double get avgMs => transitionMs.isEmpty ? 0 : transitionMs.reduce((a, b) => a + b) / transitionMs.length;
  // 速度评分：< 1秒=满分，> 3秒=0分
  int get speedScore {
    if (transitionMs.isEmpty) return 0;
    return (100 - ((avgMs - 500) / 25).clamp(0, 100)).round();
  }

  TransitionState copyWith({
    bool? isRunning,
    int? currentIndex,
    List<int>? transitionMs,
    bool? finished,
  }) {
    return TransitionState(
      isRunning: isRunning ?? this.isRunning,
      currentIndex: currentIndex ?? this.currentIndex,
      transitionMs: transitionMs ?? this.transitionMs,
      finished: finished ?? this.finished,
    );
  }
}

class TransitionNotifier extends StateNotifier<TransitionState> {
  final PitchDetectionService _pitchService;
  final ChordRecognizer _recognizer = ChordRecognizer(44100);
  TransitionNotifier(this._pitchService) : super(const TransitionState());

  DateTime _lastSwitchTime = DateTime.now();
  StreamSubscription? _sub;
  String? _lastChord; // 最近识别到的和弦（诊断显示）
  String? get lastChord => _lastChord;
  // 诊断计数（调试用）
  int _pitchEvents = 0;
  int get pitchEvents => _pitchEvents;
  double? _lastFreq;
  double? get lastFreq => _lastFreq;
  double? _lastEnergy;
  double? get lastEnergy => _lastEnergy;
  double _maxEnergy = 0; // 记录最大能量（帮助定门限）
  double get maxEnergy => _maxEnergy;
  bool _pitchVerified = false; // 上次切换是否根音验证通过
  bool get pitchVerified => _pitchVerified;

  void start(ChordProgression progression) async {
    state = TransitionState(isRunning: true, currentIndex: 0, transitionMs: []);
    _lastSwitchTime = DateTime.now();

    final chords = progression.chords;

    _sub = _pitchService.pitchStream.listen((r) {
      if (!state.isRunning || state.currentIndex >= chords.length) return;
      final target = chords[state.currentIndex];
      // 记录诊断数据
      if (r.energy > _maxEnergy) _maxEnergy = r.energy;
      _lastEnergy = r.energy;

      // 用 Chroma 识别和弦（需要原始样本）
      if (r.samples != null && r.samples!.isNotEmpty) {
        _pitchEvents++;
        final result = _recognizer.recognizeDetailed(
          r.samples!.toList(),
          sampleRate: _pitchService.actualSampleRate,
        );
        _lastChord = result.bestMatch != null
            ? '${result.bestMatch}(${result.score.toStringAsFixed(2)})'
            : '-';

        // 判定：识别到的和弦 == 目标和弦 → 切换
        final now = DateTime.now();
        final sinceLast = now.difference(_lastSwitchTime).inMilliseconds;
        if (result.chord != null &&
            result.chord == target.name &&
            sinceLast > 500) {
          _pitchVerified = true;
          final elapsed = now.difference(_lastSwitchTime).inMilliseconds;
          final newMs = [...state.transitionMs];
          if (state.currentIndex > 0) newMs.add(elapsed);
          _lastSwitchTime = now;
          final nextIdx = state.currentIndex + 1;
          if (nextIdx >= progression.chords.length) {
            _finish(newMs);
          } else {
            state = TransitionState(
              isRunning: true,
              currentIndex: nextIdx,
              transitionMs: newMs,
            );
          }
          return;
        }
      }

      state = TransitionState(
        isRunning: true,
        currentIndex: state.currentIndex,
        transitionMs: state.transitionMs,
      );
    });

    try {
      await _pitchService.start();
    } catch (e) {
      state = const TransitionState();
    }
  }

  void _finish(List<int> ms) {
    _sub?.cancel();
    _pitchService.stop();
    state = TransitionState(isRunning: false, transitionMs: ms, finished: true);
  }

  void stop() {
    _sub?.cancel();
    _pitchService.stop();
    state = TransitionState(isRunning: false, transitionMs: state.transitionMs, finished: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final transitionProvider =
    StateNotifierProvider<TransitionNotifier, TransitionState>((ref) {
  return TransitionNotifier(ref.read(pitchServiceProvider));
});

// ─────────────────────────────────────────────
//  UI
// ─────────────────────────────────────────────

class ChordTransitionPage extends ConsumerStatefulWidget {
  const ChordTransitionPage({super.key});

  @override
  ConsumerState<ChordTransitionPage> createState() => _ChordTransitionPageState();
}

class _ChordTransitionPageState extends ConsumerState<ChordTransitionPage> {
  int _progIdx = 0;
  bool _started = false;
  // 循环练习
  int _rounds = 3; // 轮数（0=无限）
  int _restSeconds = 5;
  int _currentRound = 0;
  bool _resting = false;
  int _restCountdown = 0;
  Timer? _restTimer;
  final List<int> _roundScores = []; // 每轮速度分
  bool _loopDone = false;

  ChordProgression get _progression => kProgressions[_progIdx];

  @override
  void dispose() {
    _restTimer?.cancel();
    if (ref.read(transitionProvider).isRunning) {
      ref.read(transitionProvider.notifier).stop();
    }
    super.dispose();
  }

  // ── 循环控制 ──
  void _startRound() {
    ref.invalidate(transitionProvider);
    ref.read(transitionProvider.notifier).start(_progression);
  }

  void _onRoundFinished(TransitionState st) {
    _roundScores.add(st.speedScore);
    final hasMore = _rounds == 0 || (_currentRound + 1 < _rounds);
    if (!hasMore) {
      setState(() => _loopDone = true);
      return;
    }
    // 休息
    setState(() { _resting = true; _restCountdown = _restSeconds; });
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _restCountdown--);
      if (_restCountdown <= 0) {
        t.cancel();
        setState(() { _resting = false; _currentRound++; });
        _startRound();
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() { _resting = false; _currentRound++; });
    _startRound();
  }

  void _resetLoop() {
    _restTimer?.cancel();
    setState(() {
      _loopDone = false; _started = false; _resting = false;
      _currentRound = 0; _roundScores.clear();
    });
    ref.invalidate(transitionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transitionProvider);

    // 监听一轮结束 → 触发循环逻辑
    ref.listen(transitionProvider, (prev, next) {
      if (prev != null && !prev.finished && next.finished && _started && !_loopDone) {
        _onRoundFinished(next);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  BackButton(
                      color: Colors.white,
                      onPressed: () {
                        _restTimer?.cancel();
                        if (state.isRunning) ref.read(transitionProvider.notifier).stop();
                        Navigator.pop(context);
                      }),
                  const Spacer(),
                  const Text('🔁 和弦转换',
                      style: TextStyle(
                          color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // 练习中
            if (_started && !_resting && !_loopDone && state.isRunning)
              _TransitionView(
                state: state,
                progression: _progression,
                diagText: '识别:${ref.read(transitionProvider.notifier).lastChord ?? "-"} 能量:${(ref.read(transitionProvider.notifier).lastEnergy ?? 0).toStringAsFixed(3)} 采样率:${ref.read(pitchServiceProvider).actualSampleRate}',
              )
            // 休息中
            else if (_resting)
              _TransitionRestView(
                countdown: _restCountdown,
                round: _currentRound + 1,
                lastScore: _roundScores.isNotEmpty ? _roundScores.last : null,
                onSkip: _skipRest,
                onQuit: _resetLoop,
              )
            // 全部完成：汇总
            else if (_loopDone)
              _TransitionLoopReport(scores: _roundScores, onRetry: _resetLoop)
            // 单轮完成但未循环（_rounds=1 时）
            else if (state.finished && !_loopDone)
              _TransitionReport(state: state, onRetry: _resetLoop)
            // 起始设置
            else
              _buildSetup(),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup() {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔁 选择和弦进行',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...kProgressions.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              final selected = i == _progIdx;
              return GestureDetector(
                onTap: () => setState(() => _progIdx = i),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.orange.withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AppColors.orange : Colors.transparent, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: TextStyle(
                              color: selected ? Colors.white : AppColors.text2,
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: p.chords
                            .map((c) => Container(
                                  width: 50, height: 50,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                      color: Colors.white, borderRadius: BorderRadius.circular(10)),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      SizedBox(
                                          width: 44, height: 30,
                                          child: ChordDiagram(frets: c.frets, fretCount: 5)),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
            // 循环设置
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white10, borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔁 循环练习', style: TextStyle(color: AppColors.teal, fontSize: 13)),
                  const SizedBox(height: 8),
                  const Text('练习轮数', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final r in [1, 3, 5, 10, 0])
                      ChoiceChip(
                        label: Text(r == 0 ? '无限' : '$r 轮', style: const TextStyle(fontSize: 12)),
                        selected: _rounds == r,
                        selectedColor: AppColors.orange,
                        labelStyle: TextStyle(color: _rounds == r ? Colors.white : AppColors.text3),
                        onSelected: (_) => setState(() => _rounds = r),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  const Text('每轮间隔休息', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final s in [3, 5, 8, 10])
                      ChoiceChip(
                        label: Text('$s 秒', style: const TextStyle(fontSize: 12)),
                        selected: _restSeconds == s,
                        selectedColor: AppColors.orange,
                        labelStyle: TextStyle(color: _restSeconds == s ? Colors.white : AppColors.text3),
                        onSelected: (_) => setState(() => _restSeconds = s),
                      ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _started = true;
                    _loopDone = false;
                    _currentRound = 0;
                    _roundScores.clear();
                  });
                  _startRound();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('🔁 开始转换',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('依次扫响每个和弦，系统计时你的转换速度',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _TransitionView extends StatelessWidget {
  final TransitionState state;
  final ChordProgression progression;
  final String? diagText; // 诊断信息（调试用）
  const _TransitionView({required this.state, required this.progression, this.diagText});

  @override
  Widget build(BuildContext context) {
    final current = progression.chords[state.currentIndex];
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('第 ${state.currentIndex + 1} / ${progression.chords.length}',
              style: const TextStyle(color: AppColors.text3, fontSize: 14)),
          const SizedBox(height: 6),
          if (state.transitionMs.isNotEmpty)
            Text('上次转换 ${(state.transitionMs.last / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(color: AppColors.teal, fontSize: 13)),
          // 诊断信息（调试用）
          if (diagText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(diagText!,
                  style: TextStyle(color: AppColors.text3.withValues(alpha: 0.5), fontSize: 10)),
            ),
          const SizedBox(height: 16),
          // 当前和弦大图
          Text(current.name,
              style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 12),
          Container(
            width: 180, height: 180,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 3)],
            ),
            child: ChordDiagram(frets: current.frets, fretCount: 5),
          ),
          const SizedBox(height: 12),
          const Text('👆 按这个和弦并扫响（扫弦即可切换）',
              style: TextStyle(color: AppColors.teal, fontSize: 14)),
          const SizedBox(height: 20),
          // 进度
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(progression.chords.length, (i) {
              final done = i < state.currentIndex;
              final now = i == state.currentIndex;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: now ? 24 : 12, height: 8,
                decoration: BoxDecoration(
                  color: done ? AppColors.ok : (now ? AppColors.orange : Colors.white12),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TransitionReport extends StatelessWidget {
  final TransitionState state;
  final VoidCallback onRetry;
  const _TransitionReport({required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final score = state.speedScore;
    final avg = state.avgMs / 1000;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉 转换完成！',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              SizedBox(
                width: 160, height: 160,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(width: 160, height: 160,
                    child: CircularProgressIndicator(
                        value: score / 100, strokeWidth: 12,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(
                            score >= 80 ? AppColors.ok : (score >= 60 ? AppColors.warn : AppColors.err)))),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$score', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, height: 1)),
                    const Text('速度分', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              Text('平均转换 ${avg.toStringAsFixed(2)} 秒/次',
                  style: const TextStyle(color: AppColors.teal, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                avg < 1 ? '👍 转换很流畅！' : (avg < 2 ? '💪 还需练习，继续加油' : '🎯 多练和弦指法记忆'),
                style: const TextStyle(color: AppColors.text3, fontSize: 13),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                  child: const Text('🔁 再练一次',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// 和弦转换 - 休息视图
class _TransitionRestView extends StatelessWidget {
  final int countdown;
  final int round;
  final int? lastScore;
  final VoidCallback onSkip;
  final VoidCallback onQuit;
  const _TransitionRestView({
    required this.countdown, required this.round, required this.lastScore,
    required this.onSkip, required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lastScore != null) ...[
              Text('第 $round 轮完成', style: const TextStyle(color: AppColors.text3, fontSize: 14)),
              const SizedBox(height: 6),
              Text('$lastScore 分', style: TextStyle(
                  color: lastScore! >= 80 ? AppColors.ok : AppColors.warn,
                  fontSize: 36, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
            ],
            Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.teal, width: 3),
              ),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$countdown', style: const TextStyle(
                    color: AppColors.teal, fontSize: 48, fontWeight: FontWeight.w800, height: 1)),
                const Text('秒后继续', style: TextStyle(color: AppColors.text3, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 12),
            const Text('☕ 调整呼吸，准备下一轮', style: TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 28),
            SizedBox(
              width: 200, height: 44,
              child: ElevatedButton(
                onPressed: onSkip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('立即继续 ▶', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onQuit, child: const Text('结束练习', style: TextStyle(color: AppColors.text3, fontSize: 13))),
          ],
        ),
      ),
    );
  }
}


/// 和弦转换 - 多轮汇总报告
class _TransitionLoopReport extends StatelessWidget {
  final List<int> scores;
  final VoidCallback onRetry;
  const _TransitionLoopReport({required this.scores, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final avg = scores.isEmpty ? 0 : (scores.reduce((a, b) => a + b) / scores.length).round();
    final best = scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text('🎉 全部练习完成！',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('共 ${scores.length} 轮', style: const TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 24),
            SizedBox(
              width: 160, height: 160,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 160, height: 160,
                  child: CircularProgressIndicator(
                      value: avg / 100, strokeWidth: 12,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(avg >= 80 ? AppColors.ok : (avg >= 60 ? AppColors.warn : AppColors.err)))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$avg', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, height: 1)),
                  const Text('平均速度分', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              _stat('最高分', '$best', AppColors.ok),
              const SizedBox(width: 12),
              _stat('轮数', '${scores.length}', AppColors.teal),
            ]),
            const SizedBox(height: 24),
            const Align(alignment: Alignment.centerLeft,
              child: Text('每轮速度分', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
            const SizedBox(height: 12),
            ...scores.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 50, child: Text('第 ${e.key + 1} 轮', style: const TextStyle(color: AppColors.text3, fontSize: 13))),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(children: [
                    Container(height: 20, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10))),
                    FractionallySizedBox(
                      widthFactor: e.value / 100,
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: e.value >= 80 ? AppColors.ok : (e.value >= 60 ? AppColors.warn : AppColors.err),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(padding: const EdgeInsets.only(left: 10),
                        child: Align(alignment: Alignment.centerLeft,
                          child: Text('${e.value} 分', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))),
                  ]),
                ),
              ]),
            )),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                child: const Text('🔁 再来一组', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
        ]),
      ),
    );
  }
}
