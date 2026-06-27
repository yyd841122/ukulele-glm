/// 跟弹评分页面（优化版）
///
/// 三大改进：
/// 1. 内嵌可调节拍器（BPM 显示 + 加减 + tick 播放）
/// 2. 试听展示（标准音高/拨弦两种音色可切换，顺序播放）
/// 3. 单音/和弦两种练习模式（和弦模式显示指法图）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/music_utils.dart';
import '../../core/audio/scoring_engine.dart';
import '../../core/audio/tone_player.dart';
import '../../core/monetization/feature_gate.dart';
import '../../core/monetization/monetization_model.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';
import 'chord_library_page.dart' show ChordDiagram;

/// 练习模式
enum PracticeMode { single, chord }

/// 应弹项（单音 或 和弦）
@immutable
class PracticeItem {
  final String label; // 显示名：单音 "C4"、和弦 "C"
  final String name; // 音名（用于识别比对）
  final int octave; // 八度（和弦忽略）
  final List<int>? chordFrets; // 和弦指法 [G,C,E,A]（和弦模式用）

  const PracticeItem({
    required this.label,
    required this.name,
    this.octave = 4,
    this.chordFrets,
  });
}

/// 单音练习序列：C 大调音阶（含指板位置 frets）
///
/// frets 语义：[G弦, C弦, E弦, A弦]，值：
///   0 = 空弦(○)，1+ = 按该品，-1 = 不弹(×)
/// 单音只在一根弦上弹，其余弦标 -1 闷音。
final List<PracticeItem> _scaleItems = [
  // C4 = C弦(3弦)空弦
  PracticeItem(label: 'C', name: 'C', octave: 4, chordFrets: [-1, 0, -1, -1]),
  // D4 = C弦(3弦)第2品
  PracticeItem(label: 'D', name: 'D', octave: 4, chordFrets: [-1, 2, -1, -1]),
  // E4 = E弦(2弦)空弦
  PracticeItem(label: 'E', name: 'E', octave: 4, chordFrets: [-1, -1, 0, -1]),
  // F4 = E弦(2弦)第1品
  PracticeItem(label: 'F', name: 'F', octave: 4, chordFrets: [-1, -1, 1, -1]),
  // G4 = G弦(4弦)空弦
  PracticeItem(label: 'G', name: 'G', octave: 4, chordFrets: [0, -1, -1, -1]),
  // A4 = A弦(1弦)空弦
  PracticeItem(label: 'A', name: 'A', octave: 4, chordFrets: [-1, -1, -1, 0]),
  // B4 = A弦(1弦)第2品
  PracticeItem(label: 'B', name: 'B', octave: 4, chordFrets: [-1, -1, -1, 2]),
  // C5 = A弦(1弦)第3品
  PracticeItem(label: 'C', name: 'C', octave: 5, chordFrets: [-1, -1, -1, 3]),
];

/// 和弦练习序列：C-G-Am-F 经典进行
final List<PracticeItem> _chordItems = [
  PracticeItem(label: 'C', name: 'C', chordFrets: [0, 0, 0, 3]),
  PracticeItem(label: 'G', name: 'G', chordFrets: [0, 2, 3, 2]),
  PracticeItem(label: 'Am', name: 'Am', chordFrets: [2, 0, 0, 0]),
  PracticeItem(label: 'F', name: 'F', chordFrets: [2, 0, 1, 0]),
];

class FollowScorePage extends ConsumerStatefulWidget {
  const FollowScorePage({super.key});

  @override
  ConsumerState<FollowScorePage> createState() => _FollowScorePageState();
}

class _FollowScorePageState extends ConsumerState<FollowScorePage> {
  PracticeMode _mode = PracticeMode.single;
  ToneType _toneType = ToneType.strum;
  int _bpm = 80;
  bool _metronomeOn = false;
  bool _practiceTickSound = false; // 练习中节拍器是否发声（默认静音避免干扰识别）
  Timer? _metroTimer;
  int _metroBeat = 0;
  bool _started = false;
  bool _previewing = false;

  // ── 循环练习 ──
  int _rounds = 3; // 练习轮数（0=无限循环）
  int _restSeconds = 5; // 每轮间隔休息秒数
  int _currentRound = 0; // 当前第几轮（0 起）
  bool _resting = false; // 是否在休息中
  int _restCountdown = 0; // 休息倒计时
  Timer? _restTimer;
  final List<int> _roundScores = []; // 每轮得分
  bool _loopDone = false; // 全部轮次完成

  List<PracticeItem> get _items =>
      _mode == PracticeMode.single ? _scaleItems : _chordItems;

  @override
  void dispose() {
    _metroTimer?.cancel();
    _restTimer?.cancel();
    Future.microtask(() {
      if (ref.read(scoringEngineProvider).isRunning) {
        ref.read(scoringEngineProvider.notifier).stop();
      }
    });
    super.dispose();
  }

  // ─── 节拍器 ───
  void _toggleMetronome() {
    if (_metronomeOn) {
      _metroTimer?.cancel();
      setState(() {
        _metronomeOn = false;
        _metroBeat = 0;
      });
    } else {
      setState(() => _metronomeOn = true);
      _metroBeat = 0;
      playTickTone(accent: true);
      _metroTimer =
          Timer.periodic(Duration(milliseconds: 60000 ~/ _bpm), (t) {
        _metroBeat = (_metroBeat + 1) % 4;
        playTickTone(accent: _metroBeat == 0);
      });
    }
  }

  void _setBpm(int v) {
    setState(() => _bpm = v.clamp(40, 240));
    if (_metronomeOn) {
      _metroTimer?.cancel();
      _metroBeat = 0;
      playTickTone(accent: true);
      _metroTimer =
          Timer.periodic(Duration(milliseconds: 60000 ~/ _bpm), (t) {
        _metroBeat = (_metroBeat + 1) % 4;
        playTickTone(accent: _metroBeat == 0);
      });
    }
  }

  // ─── 试听展示 ───
  void _preview() async {
    // 已在试听 → 停止（修复：之前直接 return 导致无法暂停）
    if (_previewing) {
      setState(() => _previewing = false);
      return;
    }
    setState(() => _previewing = true);
    final noteDuration = Duration(milliseconds: 60000 * 2 ~/ _bpm);
    for (final item in _items) {
      if (!_previewing) break; // 被停止则中断
      playTone(name: item.name, octave: item.octave, type: _toneType);
      await Future.delayed(noteDuration);
    }
    if (_previewing) setState(() => _previewing = false);
  }

  // ─── 开始跟弹（循环模式）───
  Future<void> _tryStart() async {
    final result = ref.read(featureGateProvider).check(FeatureKey.followScore);
    if (result is Locked) {
      await showPaywall(context, feature: result.feature, reason: result.reason);
      return;
    }
    // 停掉节拍器（避免和评分冲突）
    if (_metronomeOn) _toggleMetronome();

    setState(() {
      _started = true;
      _loopDone = false;
      _currentRound = 0;
      _roundScores.clear();
    });
    await _startRound();
  }

  /// 启动一轮练习
  Future<void> _startRound() async {
    ref.invalidate(scoringEngineProvider);
    final beatMs = 60000 * 2 ~/ _bpm; // 每音符 2 拍
    final targets = <TargetNote>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      targets.add(TargetNote(
        name: it.name,
        octave: it.octave,
        start: Duration(milliseconds: i * beatMs), // 按顺序错开
        duration: Duration(milliseconds: beatMs),
      ));
    }
    try {
      await ref.read(scoringEngineProvider.notifier).start(targets);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// 一轮结束后：记录分数，决定休息/下一轮/结束
  void _onRoundFinished(ScoringState state) {
    if (_resting || _loopDone) return; // 防重复触发
    final score = state.pitchScore;
    _roundScores.add(score);

    // 是否还有下一轮？_rounds=0 表示无限循环
    final hasMore = _rounds == 0 || (_currentRound + 1 < _rounds);
    if (!hasMore) {
      setState(() => _loopDone = true);
      return;
    }
    // 进入休息
    _startRest();
  }

  /// 开始休息倒计时
  void _startRest() {
    setState(() {
      _resting = true;
      _restCountdown = _restSeconds;
    });
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _restCountdown--);
      if (_restCountdown <= 0) {
        t.cancel();
        setState(() {
          _resting = false;
          _currentRound++;
        });
        _startRound(); // 自动开始下一轮
      }
    });
  }

  /// 提前结束休息，立即开始下一轮
  void _skipRest() {
    _restTimer?.cancel();
    setState(() {
      _resting = false;
      _currentRound++;
    });
    _startRound();
  }

  /// 退出循环练习（手动停止）
  void _quitLoop() {
    _restTimer?.cancel();
    ref.read(scoringEngineProvider.notifier).stop();
    setState(() {
      _started = false;
      _resting = false;
      _loopDone = false;
      _currentRound = 0;
      _roundScores.clear();
    });
    ref.invalidate(scoringEngineProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scoringEngineProvider);
    final finished = !state.isRunning && state.judgements.isNotEmpty;

    // 监听一轮结束 → 触发休息/下一轮/汇总
    ref.listen(scoringEngineProvider, (prev, next) {
      if (prev?.isRunning == true && !next.isRunning && next.judgements.isNotEmpty) {
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
                        _metroTimer?.cancel();
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
                  // 练习中：节拍器发声开关（默认静音避免干扰麦克风，可手动开声）
                  if (_started && !_resting && !_loopDone)
                    GestureDetector(
                      onTap: () => setState(() => _practiceTickSound = !_practiceTickSound),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _practiceTickSound
                              ? AppColors.teal.withValues(alpha: 0.3)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _practiceTickSound ? AppColors.teal : Colors.transparent),
                        ),
                        child: Text(
                          _practiceTickSound ? '🔊 节拍声' : '🔇 静音',
                          style: TextStyle(
                              color: _practiceTickSound ? AppColors.teal : AppColors.text3,
                              fontSize: 11),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
            // 顶部工具栏（模式/音色/节拍器/试听）—— 仅未开始时显示
            if (!_started && !_loopDone) _buildToolbar(),
            // 练习中：当前轮次进度
            if (_started && !finished && !_resting)
              _CurrentNoteView(
                state: state, items: _items, currentIdx: state.currentIndex,
                bpm: _bpm, tickSound: _practiceTickSound),
            // 休息中
            if (_resting) _RestView(
              countdown: _restCountdown,
              round: _currentRound + 1,
              totalRounds: _rounds,
              lastScore: _roundScores.isNotEmpty ? _roundScores.last : null,
              onSkip: _skipRest,
              onQuit: _quitLoop,
            ),
            // 全部轮次完成：汇总报告
            if (_loopDone)
              _LoopReport(
                scores: _roundScores,
                onRetry: () {
                  setState(() {
                    _loopDone = false;
                    _started = false;
                    _roundScores.clear();
                    _currentRound = 0;
                  });
                  ref.invalidate(scoringEngineProvider);
                },
              ),
            // 起始页（含循环设置）
            if (!_started && !_loopDone) _buildStartArea(state),
          ],
        ),
      ),
    );
  }

  // ─── 工具栏 ───
  Widget _buildToolbar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 模式切换
          Row(
            children: [
              const Text('练习模式', style: TextStyle(color: AppColors.text3, fontSize: 12)),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('单音音阶', style: TextStyle(fontSize: 12)),
                selected: _mode == PracticeMode.single,
                selectedColor: AppColors.orange,
                labelStyle: TextStyle(
                    color: _mode == PracticeMode.single ? Colors.white : AppColors.text3),
                onSelected: (_) => setState(() => _mode = PracticeMode.single),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('和弦转换', style: TextStyle(fontSize: 12)),
                selected: _mode == PracticeMode.chord,
                selectedColor: AppColors.orange,
                labelStyle: TextStyle(
                    color: _mode == PracticeMode.chord ? Colors.white : AppColors.text3),
                onSelected: (_) => setState(() => _mode = PracticeMode.chord),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 音色切换
          Row(
            children: [
              const Text('试听音色', style: TextStyle(color: AppColors.text3, fontSize: 12)),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('🎵 拨弦', style: TextStyle(fontSize: 12)),
                selected: _toneType == ToneType.strum,
                selectedColor: AppColors.teal,
                labelStyle: TextStyle(
                    color: _toneType == ToneType.strum ? Colors.white : AppColors.text3),
                onSelected: (_) => setState(() => _toneType = ToneType.strum),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('♩ 标准音', style: TextStyle(fontSize: 12)),
                selected: _toneType == ToneType.sine,
                selectedColor: AppColors.teal,
                labelStyle: TextStyle(
                    color: _toneType == ToneType.sine ? Colors.white : AppColors.text3),
                onSelected: (_) => setState(() => _toneType = ToneType.sine),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 节拍器 + 试听
          Row(
            children: [
              // BPM 加减
              GestureDetector(
                onTap: () => _setBpm(_bpm - 5),
                child: Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                  child: const Icon(Icons.remove, color: Colors.white, size: 18),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Text('$_bpm', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Text('BPM', style: TextStyle(color: AppColors.text3, fontSize: 9)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _setBpm(_bpm + 5),
                child: Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              // 节拍器开关
              GestureDetector(
                onTap: _toggleMetronome,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _metronomeOn ? AppColors.teal.withValues(alpha: 0.3) : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _metronomeOn ? AppColors.teal : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_metronomeOn ? Icons.stop : Icons.play_arrow,
                          color: _metronomeOn ? AppColors.teal : Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('节拍', style: TextStyle(
                          color: _metronomeOn ? AppColors.teal : Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // 试听
              GestureDetector(
                onTap: _preview,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.orange),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_previewing ? Icons.pause : Icons.headphones,
                          color: AppColors.orange, size: 16),
                      const SizedBox(width: 4),
                      Text(_previewing ? '试听中' : '试听',
                          style: const TextStyle(color: AppColors.orange, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 起始说明区 ───
  Widget _buildStartArea(ScoringState state) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              _mode == PracticeMode.single ? '🎯 C 大调音阶' : '🎯 和弦转换 C-G-Am-F',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // 序列预览
            Wrap(
              spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
              children: _items
                  .map((it) => Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
                        ),
                        alignment: Alignment.center,
                        child: Text(it.label,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            // 和弦模式：按次序逐个展示和弦指法图
            if (_mode == PracticeMode.chord) ...[
              _ChordSequenceView(
                items: _chordItems,
                bpm: _bpm,
                metronomeOn: _metronomeOn,
              ),
              const SizedBox(height: 16),
            ],
            // 循环练习设置
            _buildLoopSettings(),
            const SizedBox(height: 16),
            // 开始按钮
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _tryStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('🎤 开始跟弹',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == PracticeMode.single
                  ? '依次弹响每个音，系统实时评分'
                  : '依次扫响每个和弦（评根音），系统实时评分',
              style: const TextStyle(color: AppColors.text3, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 循环练习设置 ───
  Widget _buildLoopSettings() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔁 循环练习', style: TextStyle(color: AppColors.teal, fontSize: 13)),
          const SizedBox(height: 10),
          // 练习轮数
          const Text('练习轮数', style: TextStyle(color: AppColors.text3, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final r in [1, 3, 5, 10, 0])
                ChoiceChip(
                  label: Text(r == 0 ? '无限' : '$r 轮', style: const TextStyle(fontSize: 12)),
                  selected: _rounds == r,
                  selectedColor: AppColors.orange,
                  labelStyle: TextStyle(color: _rounds == r ? Colors.white : AppColors.text3),
                  onSelected: (_) => setState(() => _rounds = r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 休息时长
          const Text('每轮间隔休息', style: TextStyle(color: AppColors.text3, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final s in [3, 5, 8, 10])
                ChoiceChip(
                  label: Text('$s 秒', style: const TextStyle(fontSize: 12)),
                  selected: _restSeconds == s,
                  selectedColor: AppColors.orange,
                  labelStyle: TextStyle(color: _restSeconds == s ? Colors.white : AppColors.text3),
                  onSelected: (_) => setState(() => _restSeconds = s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 当前应弹音符的实时视图（含和弦指法图）
class _CurrentNoteView extends StatefulWidget {
  final ScoringState state;
  final List<PracticeItem> items;
  final int currentIdx;
  final int bpm;
  final bool tickSound; // 练习中节拍器是否发声
  const _CurrentNoteView({
    required this.state,
    required this.items,
    required this.currentIdx,
    required this.bpm,
    this.tickSound = false,
  });

  @override
  State<_CurrentNoteView> createState() => _CurrentNoteViewState();
}

class _CurrentNoteViewState extends State<_CurrentNoteView> {
  int _beat = 0;
  Timer? _beatTimer;

  @override
  void initState() {
    super.initState();
    _startBeat();
  }

  void _startBeat() {
    _beatTimer?.cancel();
    _beat = 0;
    final interval = Duration(milliseconds: 60000 ~/ widget.bpm);
    _beatTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() => _beat = (_beat + 1) % 4);
      // 可选发声（默认静音，避免干扰麦克风识别）
      if (widget.tickSound) {
        playTickTone(accent: _beat == 0);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CurrentNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bpm != widget.bpm || oldWidget.tickSound != widget.tickSound) {
      _startBeat();
    }
  }

  /// 判断是否单音（frets 中只有 1 根弦需要弹，其余闷音）
  bool _isSingleNote(PracticeItem item) {
    final frets = item.chordFrets;
    if (frets == null) return false;
    final playable = frets.where((f) => f != -1).length;
    return playable == 1;
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentIdx >= widget.items.length) return const SizedBox.shrink();
    final item = widget.items[widget.currentIdx];
    final cents = widget.state.lastPitchCents;
    final inTune = cents != null && cents.abs() <= 25;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 节拍器视觉（纯视觉不发声，避免干扰麦克风识别）
          _BeatIndicator(beat: _beat),
          const SizedBox(height: 8),
          Text('第 ${widget.currentIdx + 1} / ${widget.items.length} · ${widget.bpm} BPM',
              style: const TextStyle(color: AppColors.text3, fontSize: 13)),
          const SizedBox(height: 10),
          if (item.chordFrets != null) ...[
            // 指法图占主导（大、醒目），名称作小标签（单音/和弦通用）
            // 名称标签
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey('${item.label}${item.octave}'),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(item.label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            // 指法图（大幅放大，新手照着按的位置看清楚）
            Container(
              width: 240, height: 240,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 3)],
              ),
              child: ChordDiagram(frets: item.chordFrets!, fretCount: 5),
            ),
            const SizedBox(height: 8),
            Text(
              _isSingleNote(item) ? '👆 只弹 ○/● 那根弦，× 的弦不弹' : '👆 照着图按这个和弦',
              style: const TextStyle(color: AppColors.teal, fontSize: 14),
            ),
          ] else ...[
            // 无指法数据：音名大字兜底
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(item.label, key: ValueKey(item.label),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 100, fontWeight: FontWeight.w800, height: 1)),
            ),
            const SizedBox(height: 4),
            Text('${item.octave} · ${noteToFrequency(item.name, item.octave).toStringAsFixed(1)} Hz',
                style: const TextStyle(color: AppColors.text3, fontSize: 15)),
          ],
          const SizedBox(height: 20),
          // 实时音准指示
          if (cents != null)
            Column(children: [
              Text(inTune ? '✓ 对了！' : '${cents > 0 ? "偏高 ↓" : "偏低 ↑"} ${cents.abs()} cents',
                  style: TextStyle(
                      color: inTune ? AppColors.ok : AppColors.err,
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SizedBox(width: 260,
                child: LinearProgressIndicator(
                    value: ((cents + 50) / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    color: inTune ? AppColors.ok : AppColors.err, minHeight: 6)),
            ])
          else
            const Text('弹响琴弦…', style: TextStyle(color: AppColors.text3, fontSize: 16)),
          const SizedBox(height: 24),
          // 和弦序列预览：从当前开始，按次序展示后续和弦按法（新手照着练）
          if (widget.items.any((i) => i.chordFrets != null))
            _ChordSequencePreview(items: widget.items, currentIdx: widget.currentIdx),
          const SizedBox(height: 20),
          _NoteProgress(state: widget.state, items: widget.items),
        ],
      ),
    );
  }
}

/// 音符进度条
class _NoteProgress extends StatelessWidget {
  final ScoringState state;
  final List<PracticeItem> items;
  const _NoteProgress({required this.state, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
        children: List.generate(items.length, (i) {
          Color bg; String icon;
          if (i < state.judgements.length) {
            bg = state.judgements[i].correct ? AppColors.ok : AppColors.err;
            icon = state.judgements[i].correct ? '✓' : '✗';
          } else if (i == state.currentIndex && state.isRunning) {
            bg = AppColors.orange; icon = items[i].label;
          } else {
            bg = Colors.white12; icon = items[i].label;
          }
          return Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(icon,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          );
        }),
      ),
    );
  }
}

/// 和弦按次序展示视图
///
/// 起始页用：按节拍逐个显示一个和弦指法图，新手一个一个认。
/// - 节拍器开 → 自动按节奏轮播（并试听当前和弦音色）
/// - 节拍器关 → 手动 ◀ ▶ 切换
class _ChordSequenceView extends StatefulWidget {
  final List<PracticeItem> items;
  final int bpm;
  final bool metronomeOn;
  const _ChordSequenceView({
    required this.items,
    required this.bpm,
    required this.metronomeOn,
  });

  @override
  State<_ChordSequenceView> createState() => _ChordSequenceViewState();
}

class _ChordSequenceViewState extends State<_ChordSequenceView> {
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _setupAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _ChordSequenceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 节拍器开关或 BPM 变化时重新设定时器
    if (oldWidget.metronomeOn != widget.metronomeOn ||
        oldWidget.bpm != widget.bpm) {
      _setupAutoPlay();
    }
  }

  void _setupAutoPlay() {
    _timer?.cancel();
    _timer = null;
    if (!widget.metronomeOn) return;
    // 每个小节（4拍）切换一次和弦，并试听
    final interval = Duration(milliseconds: 60000 * 4 ~/ widget.bpm);
    playTone(
        name: widget.items[_current].name,
        octave: widget.items[_current].octave,
        type: ToneType.strum);
    _timer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() {
        _current = (_current + 1) % widget.items.length;
      });
      playTone(
          name: widget.items[_current].name,
          octave: widget.items[_current].octave,
          type: ToneType.strum);
    });
  }

  void _goto(int idx) {
    setState(() => _current = (idx + widget.items.length) % widget.items.length);
    playTone(
        name: widget.items[_current].name,
        octave: widget.items[_current].octave,
        type: ToneType.strum);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_current];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('🎵 按次序认和弦',
                style: TextStyle(color: AppColors.teal, fontSize: 13)),
            Text(
              widget.metronomeOn ? '自动播放中（跟着节奏认）' : '手动切换',
              style: TextStyle(
                  color: widget.metronomeOn ? AppColors.teal : AppColors.text3,
                  fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 进度点
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.items.length, (i) {
            final active = i == _current;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? AppColors.orange : Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // 当前和弦大图
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 上一个
            GestureDetector(
              onTap: () => _goto(_current - 1),
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                    color: Colors.white10, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_left,
                    color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 16),
            // 和弦图
            Container(
              width: 150, height: 170,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.orange.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2),
                ],
              ),
              child: Column(
                children: [
                  Text(item.label,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Expanded(
                      child: ChordDiagram(frets: item.chordFrets!, fretCount: 5)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // 下一个
            GestureDetector(
              onTap: () => _goto(_current + 1),
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                    color: Colors.white10, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right,
                    color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 全部序列缩略（点选跳转）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.items.length, (i) {
            final it = widget.items[i];
            final active = i == _current;
            return GestureDetector(
              onTap: () => _goto(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppColors.orange : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${i + 1}.${it.label}',
                    style: TextStyle(
                        color: active ? Colors.white : AppColors.text3,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal)),
              ),
            );
          }),
        ),
      ],
    );
  }
}


/// 节拍器视觉指示（练习中用，纯视觉不发声，避免干扰麦克风）
class _BeatIndicator extends StatelessWidget {
  final int beat; // 当前拍 0-3
  const _BeatIndicator({required this.beat});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final active = i == beat;
        final isDownbeat = i == 0; // 第一拍（重音）
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: active ? 18 : 12,
          height: active ? 18 : 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? (isDownbeat ? AppColors.teal : AppColors.orange)
                : Colors.white12,
            boxShadow: active
                ? [BoxShadow(
                    color: (isDownbeat ? AppColors.teal : AppColors.orange)
                        .withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1)]
                : [],
          ),
        );
      }),
    );
  }
}


/// 和弦序列预览（练习中用）
///
/// 从当前和弦开始，按次序横向展示当前+后续和弦的迷你指法图。
/// 当前和弦高亮放大，后续的缩小、半透明，让新手预知下一个该按什么。
/// 弹过的不再显示。
class _ChordSequencePreview extends StatelessWidget {
  final List<PracticeItem> items;
  final int currentIdx;
  const _ChordSequencePreview({required this.items, required this.currentIdx});

  @override
  Widget build(BuildContext context) {
    // 取从当前往后的和弦（含当前，最多显示 4 个）
    final upcoming = <int>[];
    for (var i = currentIdx; i < items.length && upcoming.length < 4; i++) {
      if (items[i].chordFrets != null) upcoming.add(i);
    }
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const Text('🎵 接下来按次序弹（照着按）',
            style: TextStyle(color: AppColors.teal, fontSize: 12)),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              const SizedBox(width: 12),
              for (var seq = 0; seq < upcoming.length; seq++) ...[
                _miniChord(items[upcoming[seq]], seq == 0),
                if (seq < upcoming.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 40),
                    child: const Icon(Icons.arrow_forward_ios,
                        color: AppColors.text3, size: 14),
                  ),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniChord(PracticeItem item, bool isCurrent) {
    return Opacity(
      opacity: isCurrent ? 1.0 : 0.55,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isCurrent ? 100 : 76,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isCurrent ? AppColors.orange : Colors.transparent,
              width: isCurrent ? 2 : 0),
          boxShadow: isCurrent
              ? [BoxShadow(
                  color: AppColors.orange.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1)]
              : [],
        ),
        child: Column(
          children: [
            Text(item.label,
                style: TextStyle(
                    fontSize: isCurrent ? 18 : 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Expanded(child: ChordDiagram(frets: item.chordFrets!, fretCount: 5)),
          ],
        ),
      ),
    );
  }
}


/// 休息倒计时视图（每轮之间）
class _RestView extends StatelessWidget {
  final int countdown; // 倒计时秒
  final int round; // 刚完成的轮次
  final int totalRounds; // 总轮数（0=无限）
  final int? lastScore; // 上一轮得分
  final VoidCallback onSkip; // 跳过休息
  final VoidCallback onQuit; // 退出练习
  const _RestView({
    required this.countdown,
    required this.round,
    required this.totalRounds,
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
            // 倒计时大圆
            Container(
              width: 140, height: 140,
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
                          color: AppColors.teal, fontSize: 48, fontWeight: FontWeight.w800, height: 1)),
                  const Text('秒后继续', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('☕ 调整呼吸，准备下一轮',
                style: TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 28),
            // 跳过休息
            SizedBox(
              width: 200, height: 44,
              child: ElevatedButton(
                onPressed: onSkip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('立即继续 ▶',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onQuit,
              child: const Text('结束练习', style: TextStyle(color: AppColors.text3, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}


/// 全部轮次完成：汇总报告
class _LoopReport extends StatelessWidget {
  final List<int> scores; // 每轮得分
  final VoidCallback onRetry;
  const _LoopReport({required this.scores, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final avg = scores.isEmpty
        ? 0
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final best = scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
    final progress = scores.isEmpty ? 0.0 : avg / 100;

    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text('🎉 全部练习完成！',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('共 ${scores.length} 轮',
                style: const TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 24),
            // 平均分环
            SizedBox(
              width: 160, height: 160,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 160, height: 160,
                  child: CircularProgressIndicator(
                      value: progress, strokeWidth: 12,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(avg >= 80
                          ? AppColors.ok
                          : (avg >= 60 ? AppColors.warn : AppColors.err)))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$avg', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, height: 1)),
                  const Text('平均分', style: TextStyle(color: AppColors.text3, fontSize: 13)),
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
            // 每轮得分柱状
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('每轮得分', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            ...scores.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 50, child: Text('第 ${i + 1} 轮',
                      style: const TextStyle(color: AppColors.text3, fontSize: 13))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Stack(children: [
                      // 背景
                      Container(height: 20, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10))),
                      // 得分条
                      FractionallySizedBox(
                        widthFactor: s / 100,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: s >= 80 ? AppColors.ok : (s >= 60 ? AppColors.warn : AppColors.err),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      // 数字
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('$s 分',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                child: const Text('🔁 再来一组',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        ],
      ),
    ),
  );
  }
}
