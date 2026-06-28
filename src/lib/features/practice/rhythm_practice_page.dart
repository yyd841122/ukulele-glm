/// 节奏练习页面（扫弦节奏型跟打）
///
/// 工作原理：
/// - 给定一个节奏型（如 民谣下下上上下上 D-D-U-U-D-U）
/// - 节拍器按 BPM 播放，视觉逐拍高亮
/// - 用户在"下扫/上扫"标记的拍点扫弦
/// - 系统检测该时刻是否有足够音量（onset 能量），判定是否跟上
/// - 累计命中率，给出节奏评分
///
/// 不依赖精确音高识别，只检测"有没有声音"（能量阈值），适合扫弦节奏练习。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/pitch_service.dart';
import '../../core/audio/tone_player.dart';
import '../../core/theme/app_theme.dart';

/// 节奏型
@immutable
class RhythmPattern {
  final String name;
  final List<StrokeType> strokes; // 每拍（含细分）的扫弦类型
  const RhythmPattern({required this.name, required this.strokes});
}

/// 扫弦类型
enum StrokeType {
  down('↓ 下扫'),
  up('↑ 上扫'),
  rest('· 不扫'),
  ;

  final String label;
  const StrokeType(this.label);
}

/// 预置节奏型（以 8 分音符为单位，一小节 8 拍）
const List<RhythmPattern> kRhythmPatterns = [
  RhythmPattern(name: '民谣（下下上上下上）', strokes: [
    StrokeType.down, StrokeType.down, StrokeType.up, StrokeType.up,
    StrokeType.down, StrokeType.up, StrokeType.down, StrokeType.up,
  ]),
  RhythmPattern(name: '基础（下下上上下上）', strokes: [
    StrokeType.down, StrokeType.rest, StrokeType.down, StrokeType.up,
    StrokeType.up, StrokeType.down, StrokeType.up, StrokeType.rest,
  ]),
  RhythmPattern(name: '华尔兹（下上下上）3/4', strokes: [
    StrokeType.down, StrokeType.rest, StrokeType.up,
    StrokeType.down, StrokeType.rest, StrokeType.up,
  ]),
];

/// 节奏练习状态
@immutable
class RhythmState {
  final bool isRunning;
  final int currentBeat; // 当前节拍 index
  final List<bool?> results; // 每拍命中结果（true=命中，false=漏，null=未判）
  final bool finished;

  const RhythmState({
    this.isRunning = false,
    this.currentBeat = -1,
    this.results = const [],
    this.finished = false,
  });

  int get hitCount => results.where((r) => r == true).length;
  int get totalBeats => results.length;
  double get accuracy =>
      totalBeats == 0 ? 0 : hitCount / totalBeats;
  int get score => (accuracy * 100).round();

  RhythmState copyWith({
    bool? isRunning,
    int? currentBeat,
    List<bool?>? results,
    bool? finished,
  }) {
    return RhythmState(
      isRunning: isRunning ?? this.isRunning,
      currentBeat: currentBeat ?? this.currentBeat,
      results: results ?? this.results,
      finished: finished ?? this.finished,
    );
  }
}

class RhythmNotifier extends StateNotifier<RhythmState> {
  final PitchDetectionService _pitchService;
  RhythmNotifier(this._pitchService) : super(const RhythmState());

  Timer? _beatTimer;
  StreamSubscription<PitchResult>? _sub;
  int _bpm = 80;
  bool _soundDetected = false; // 当前拍窗口内是否检测到声音

  void start(RhythmPattern pattern, int bpm) async {
    _bpm = bpm;
    state = RhythmState(
      isRunning: true,
      currentBeat: -1,
      results: List.filled(pattern.strokes.length, null),
    );

    // 监听音频流，检测音量（有声音就标记）
    _soundDetected = false;
    _sub = _pitchService.pitchStream.listen((r) {
      // 有有效音高 = 有声音（足够响）
      if (r.hasPitch) {
        _soundDetected = true;
      }
    });

    try {
      await _pitchService.start();
    } catch (e) {
      state = const RhythmState();
      return;
    }

    // 节拍定时器（8分音符 = BPM/2）
    final interval = Duration(milliseconds: 60000 * 2 ~/ _bpm);
    var beat = 0;
    _beatTimer = Timer.periodic(interval, (t) {
      if (beat >= pattern.strokes.length) {
        _finish();
        return;
      }
      final stroke = pattern.strokes[beat];
      bool? hit;
      if (stroke == StrokeType.rest) {
        hit = true; // 休止拍不算
      } else {
        hit = _soundDetected; // 该扫的拍：是否检测到声音
      }
      // 播放节拍 tick（下扫重音）
      if (stroke != StrokeType.rest) {
        playTickTone(accent: stroke == StrokeType.down);
      }
      final newResults = List<bool?>.from(state.results);
      newResults[beat] = hit;
      state = RhythmState(
        isRunning: true,
        currentBeat: beat,
        results: newResults,
      );
      _soundDetected = false; // 重置，下一拍重新检测
      beat++;
    });
  }

  void _finish() {
    _beatTimer?.cancel();
    _beatTimer = null;
    _sub?.cancel();
    _sub = null;
    _pitchService.stop();
    state = RhythmState(
      isRunning: false,
      results: state.results,
      finished: true,
    );
  }

  void stop() {
    _finish();
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final rhythmProvider =
    StateNotifierProvider<RhythmNotifier, RhythmState>((ref) {
  return RhythmNotifier(ref.read(pitchServiceProvider));
});

// ─────────────────────────────────────────────
//  UI
// ─────────────────────────────────────────────

class RhythmPracticePage extends ConsumerStatefulWidget {
  const RhythmPracticePage({super.key});

  @override
  ConsumerState<RhythmPracticePage> createState() => _RhythmPracticePageState();
}

class _RhythmPracticePageState extends ConsumerState<RhythmPracticePage> {
  int _patternIdx = 0;
  int _bpm = 80;
  bool _started = false;
  // 循环
  int _rounds = 3;
  int _restSeconds = 5;
  int _currentRound = 0;
  bool _resting = false;
  int _restCountdown = 0;
  Timer? _restTimer;
  final List<int> _roundScores = [];
  bool _loopDone = false;

  RhythmPattern get _pattern => kRhythmPatterns[_patternIdx];

  @override
  void dispose() {
    _restTimer?.cancel();
    if (ref.read(rhythmProvider).isRunning) {
      ref.read(rhythmProvider.notifier).stop();
    }
    super.dispose();
  }

  // ── 循环控制 ──
  void _startRound() {
    ref.invalidate(rhythmProvider);
    ref.read(rhythmProvider.notifier).start(_pattern, _bpm);
  }

  void _onRoundFinished(RhythmState st) {
    _roundScores.add(st.score);
    final hasMore = _rounds == 0 || (_currentRound + 1 < _rounds);
    if (!hasMore) {
      setState(() => _loopDone = true);
      return;
    }
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
    ref.invalidate(rhythmProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rhythmProvider);

    // 监听一轮结束
    ref.listen(rhythmProvider, (prev, next) {
      if (prev != null && !prev.finished && next.finished && _started && !_loopDone) {
        _onRoundFinished(next);
      }
    });

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
                  BackButton(
                      color: Colors.white,
                      onPressed: () {
                        _restTimer?.cancel();
                        if (state.isRunning) {
                          ref.read(rhythmProvider.notifier).stop();
                        }
                        Navigator.pop(context);
                      }),
                  const Spacer(),
                  const Text('🥁 节奏练习',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // 练习中
            if (_started && !_resting && !_loopDone && state.isRunning)
              _RhythmView(state: state, pattern: _pattern, bpm: _bpm)
            // 休息中
            else if (_resting)
              _RhythmRestView(
                countdown: _restCountdown,
                round: _currentRound + 1,
                lastScore: _roundScores.isNotEmpty ? _roundScores.last : null,
                onSkip: _skipRest,
                onQuit: _resetLoop,
              )
            // 全部完成
            else if (_loopDone)
              _RhythmLoopReport(scores: _roundScores, onRetry: _resetLoop)
            // 单轮完成未循环
            else if (state.finished && !_loopDone)
              _RhythmReport(
                state: state, pattern: _pattern, onRetry: _resetLoop,
              )
            // 设置
            else
              _buildSetup(state),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup(RhythmState state) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('🥁 选择节奏型',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // 节奏型选择
            ...kRhythmPatterns.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              final selected = i == _patternIdx;
              return GestureDetector(
                onTap: () => setState(() => _patternIdx = i),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.orange.withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected ? AppColors.orange : Colors.transparent, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: TextStyle(
                              color: selected ? Colors.white : AppColors.text2,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      // 扫弦序列预览
                      Wrap(
                        spacing: 8,
                        children: p.strokes
                            .map((s) => Text(s.label,
                                style: TextStyle(
                                    color: s == StrokeType.rest ? AppColors.text3 : AppColors.teal,
                                    fontSize: 13)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
            // BPM
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _bpm = (_bpm - 5).clamp(40, 240)),
                  child: Container(
                    width: 36, height: 36,
                    decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                    child: const Icon(Icons.remove, color: Colors.white, size: 20),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Text('$_bpm', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      const Text('BPM', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _bpm = (_bpm + 5).clamp(40, 240)),
                  child: Container(
                    width: 36, height: 36,
                    decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
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
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('🥁 开始练习',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '跟着节拍，在 ↓↑ 标记的拍点扫弦\n系统检测你是否在正确时刻扫响',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text3, fontSize: 12, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// 练习中视图
class _RhythmView extends StatelessWidget {
  final RhythmState state;
  final RhythmPattern pattern;
  final int bpm;
  const _RhythmView({required this.state, required this.pattern, required this.bpm});

  @override
  Widget build(BuildContext context) {
    final currentStroke = state.currentBeat >= 0 && state.currentBeat < pattern.strokes.length
        ? pattern.strokes[state.currentBeat]
        : StrokeType.rest;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('BPM $bpm', style: const TextStyle(color: AppColors.text3, fontSize: 14)),
          const SizedBox(height: 20),
          // 当前拍大显示
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 100),
            child: Text(
              currentStroke == StrokeType.rest ? '·' : (currentStroke == StrokeType.down ? '↓' : '↑'),
              key: ValueKey('${state.currentBeat}_${currentStroke.name}'),
              style: TextStyle(
                color: currentStroke == StrokeType.rest ? AppColors.text3 : AppColors.orange,
                fontSize: 120,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentStroke == StrokeType.rest ? '休止（不扫）' : currentStroke.label,
            style: const TextStyle(color: AppColors.teal, fontSize: 16),
          ),
          const SizedBox(height: 40),
          // 全部拍点序列
          Wrap(
            spacing: 8, runSpacing: 12, alignment: WrapAlignment.center,
            children: List.generate(pattern.strokes.length, (i) {
              final s = pattern.strokes[i];
              final result = i < state.results.length ? state.results[i] : null;
              Color bg;
              Color fg;
              if (i < state.currentBeat) {
                // 已判
                if (s == StrokeType.rest) {
                  bg = Colors.white10; fg = AppColors.text3;
                } else if (result == true) {
                  bg = AppColors.ok; fg = Colors.white;
                } else {
                  bg = AppColors.err; fg = Colors.white;
                }
              } else if (i == state.currentBeat) {
                bg = AppColors.orange; fg = Colors.white;
              } else {
                bg = Colors.white10; fg = AppColors.text3;
              }
              return Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text(
                  s == StrokeType.rest ? '·' : (s == StrokeType.down ? '↓' : '↑'),
                  style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// 节奏报告
class _RhythmReport extends StatelessWidget {
  final RhythmState state;
  final RhythmPattern pattern;
  final VoidCallback onRetry;
  const _RhythmReport({required this.state, required this.pattern, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final score = state.score;
    final hit = state.hitCount;
    final need = state.totalBeats;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉 节奏练习完成！',
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
                    const Text('节奏分', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              Text('命中 $hit / $need 拍',
                  style: const TextStyle(color: AppColors.teal, fontSize: 16, fontWeight: FontWeight.bold)),
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

/// 节奏练习 - 休息视图
class _RhythmRestView extends StatelessWidget {
  final int countdown;
  final int round;
  final int? lastScore;
  final VoidCallback onSkip;
  final VoidCallback onQuit;
  const _RhythmRestView({
    required this.countdown,
    required this.round,
    required this.lastScore,
    required this.onSkip,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lastScore != null) ...[
              Text('第 $round 轮完成',
                  style: const TextStyle(color: AppColors.text3, fontSize: 14)),
              const SizedBox(height: 6),
              Text('$lastScore 分',
                  style: TextStyle(
                      color: lastScore! >= 80 ? AppColors.ok : AppColors.warn,
                      fontSize: 36,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
            ],
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.teal, width: 3),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$countdown',
                      style: const TextStyle(
                          color: AppColors.teal,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 1)),
                  const Text('秒后继续',
                      style: TextStyle(color: AppColors.text3, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('☕ 调整呼吸，准备下一轮',
                style: TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              height: 44,
              child: ElevatedButton(
                onPressed: onSkip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('立即继续 ▶',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onQuit,
              child: const Text('结束练习',
                  style: TextStyle(color: AppColors.text3, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 节奏练习 - 多轮汇总报告
class _RhythmLoopReport extends StatelessWidget {
  final List<int> scores;
  final VoidCallback onRetry;
  const _RhythmLoopReport({required this.scores, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final avg = scores.isEmpty
        ? 0
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final best = scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text('🎉 全部练习完成！',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('共 ${scores.length} 轮',
                style: const TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                        value: avg / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(avg >= 80
                            ? AppColors.ok
                            : (avg >= 60 ? AppColors.warn : AppColors.err)))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$avg',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 1)),
                  const Text('平均节奏分',
                      style: TextStyle(color: AppColors.text3, fontSize: 13)),
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
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('每轮节奏分',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold))),
            const SizedBox(height: 12),
            ...scores.asMap().entries.map((e) => _scoreBar(e.key, e.value)),
            const SizedBox(height: 28),
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
                        borderRadius: BorderRadius.circular(999))),
                child: const Text('🔁 再来一组',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreBar(int idx, int val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 50,
            child: Text('第 ${idx + 1} 轮',
                style: const TextStyle(color: AppColors.text3, fontSize: 13))),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(children: [
            Container(
                height: 20,
                decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10))),
            FractionallySizedBox(
              widthFactor: val / 100,
              child: Container(
                height: 20,
                decoration: BoxDecoration(
                  color: val >= 80 ? AppColors.ok : (val >= 60 ? AppColors.warn : AppColors.err),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('$val 分',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: Colors.white10, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.text3, fontSize: 12)),
        ]),
      ),
    );
  }
}
