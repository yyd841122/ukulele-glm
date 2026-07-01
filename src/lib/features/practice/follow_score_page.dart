/// 跟弹评分页面（优化版）
///
/// 三大改进：
/// 1. 内嵌可调节拍器（BPM 显示 + 加减 + tick 播放）
/// 2. 试听展示（标准音高/拨弦两种音色可切换，顺序播放）
/// 3. 单音/和弦两种练习模式（和弦模式显示指法图）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/chord_recognizer.dart';
import '../../core/audio/music_utils.dart';
import '../../core/audio/pitch_service.dart';
import '../../core/audio/scoring_engine.dart';
import '../../core/audio/tone_player.dart';
import '../../core/game/game_service.dart';
import '../../core/monetization/feature_gate.dart';
import '../../core/monetization/monetization_model.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';
import 'chord_library_page.dart' show ChordDiagram;

/// 练习模式
enum PracticeMode { single, chord, song }

/// ── 整曲练习数据结构 ──

/// 歌词行里的一个和弦标注
@immutable
class PracticeChord {
  final String name; // 和弦名，如 "C"
  final int position; // 在歌词文本中的字符位置
  final int beats; // 持续几拍（节奏驱动模式用，默认2拍）
  const PracticeChord({required this.name, required this.position, this.beats = 2});
}

/// 一行歌词（含和弦标注）
@immutable
class PracticeLyric {
  final String text; // 歌词文本
  final List<PracticeChord> chords; // 这行的和弦（按位置）
  final List<PracticeNote>? notes; // 单音旋律（与歌词对应，可选）
  const PracticeLyric({required this.text, this.chords = const [], this.notes});
}

/// 单音旋律的一个音
@immutable
class PracticeNote {
  final String name; // 音名，如 "C"
  final int octave; // 八度
  final int beats; // 持续几拍
  const PracticeNote({required this.name, this.octave = 4, this.beats = 1});
}

/// 一首歌
@immutable
class PracticeSong {
  final String title; // 歌名
  final String artist; // 原唱/说明
  final int bpm; // 建议速度
  final List<PracticeLyric> lyrics; // 歌词行
  final Map<String, List<int>> chordFrets; // 和弦名→指法[G,C,E,A]

  const PracticeSong({
    required this.title,
    required this.artist,
    required this.lyrics,
    required this.chordFrets,
    this.bpm = 80,
  });

  /// 歌曲中所有和弦的有序列表（用于进度跟踪）
  List<PracticeChord> get chordSequence => lyrics
      .expand((line) => line.chords)
      .toList();

  /// 歌曲中所有单音旋律的有序列表（单音模式用）
  List<PracticeNote> get noteSequence => lyrics
      .where((l) => l.notes != null)
      .expand((l) => l.notes!)
      .toList();
}

/// 歌曲库
final List<PracticeSong> kSongs = [
  PracticeSong(
    title: '小星星',
    artist: '英国民谣 · 入门',
    bpm: 80,
    chordFrets: {
      'C': [0, 0, 0, 3],
      'G': [0, 2, 3, 2],
      'Am': [2, 0, 0, 0],
      'F': [2, 0, 1, 0],
    },
    lyrics: [
      // 单音旋律：C C G G A A G（一闪一闪亮晶晶）
      const PracticeLyric(text: '一闪一闪亮晶晶', chords: [
        PracticeChord(name: 'C', position: 0),
        PracticeChord(name: 'G', position: 4),
      ], notes: [
        PracticeNote(name: 'C', beats: 1), PracticeNote(name: 'C', beats: 1),
        PracticeNote(name: 'G', beats: 1), PracticeNote(name: 'G', beats: 1),
        PracticeNote(name: 'A', beats: 1), PracticeNote(name: 'A', beats: 1),
        PracticeNote(name: 'G', beats: 2),
      ]),
      const PracticeLyric(text: '满天都是小星星', chords: [
        PracticeChord(name: 'Am', position: 0),
        PracticeChord(name: 'F', position: 4),
      ], notes: [
        PracticeNote(name: 'F', beats: 1), PracticeNote(name: 'F', beats: 1),
        PracticeNote(name: 'E', beats: 1), PracticeNote(name: 'E', beats: 1),
        PracticeNote(name: 'D', beats: 1), PracticeNote(name: 'D', beats: 1),
        PracticeNote(name: 'C', beats: 2),
      ]),
      const PracticeLyric(text: '挂在天上放光明', chords: [
        PracticeChord(name: 'C', position: 0),
        PracticeChord(name: 'G', position: 4),
      ], notes: [
        PracticeNote(name: 'G', beats: 1), PracticeNote(name: 'G', beats: 1),
        PracticeNote(name: 'F', beats: 1), PracticeNote(name: 'F', beats: 1),
        PracticeNote(name: 'E', beats: 1), PracticeNote(name: 'E', beats: 1),
        PracticeNote(name: 'D', beats: 2),
      ]),
      const PracticeLyric(text: '好像许多小眼睛', chords: [
        PracticeChord(name: 'Am', position: 0),
        PracticeChord(name: 'F', position: 4),
        PracticeChord(name: 'C', position: 7),
      ], notes: [
        PracticeNote(name: 'G', beats: 1), PracticeNote(name: 'G', beats: 1),
        PracticeNote(name: 'F', beats: 1), PracticeNote(name: 'F', beats: 1),
        PracticeNote(name: 'E', beats: 1), PracticeNote(name: 'E', beats: 1),
        PracticeNote(name: 'D', beats: 2),
      ]),
      const PracticeLyric(text: '一闪一闪亮晶晶', chords: [
        PracticeChord(name: 'G', position: 0),
        PracticeChord(name: 'Am', position: 4),
      ], notes: [
        PracticeNote(name: 'C', beats: 1), PracticeNote(name: 'C', beats: 1),
        PracticeNote(name: 'G', beats: 1), PracticeNote(name: 'G', beats: 1),
        PracticeNote(name: 'A', beats: 1), PracticeNote(name: 'A', beats: 1),
        PracticeNote(name: 'G', beats: 2),
      ]),
      const PracticeLyric(text: '满天都是小星星', chords: [
        PracticeChord(name: 'F', position: 0),
        PracticeChord(name: 'C', position: 4),
      ], notes: [
        PracticeNote(name: 'F', beats: 1), PracticeNote(name: 'F', beats: 1),
        PracticeNote(name: 'E', beats: 1), PracticeNote(name: 'E', beats: 1),
        PracticeNote(name: 'D', beats: 1), PracticeNote(name: 'D', beats: 1),
        PracticeNote(name: 'C', beats: 2),
      ]),
    ],
  ),
];

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

  // ── 整曲练习 ──
  int _songIdx = 0; // 选中的歌曲 index
  bool _songStarted = false; // 整曲练习是否进行中
  bool _songSingleNote = false; // 整曲：true=单音旋律版，false=和弦伴奏版
  bool _songAccompaniment = true; // 配乐开关
  int _songBpm = 80; // 整曲 BPM
  int _songRounds = 1; // 整曲循环次数

  // ── 循环练习 ──
  int _rounds = 3; // 练习轮数（0=无限循环）
  int _restSeconds = 5; // 每轮间隔休息秒数
  int _currentRound = 0; // 当前第几轮（0 起）
  bool _resting = false; // 是否在休息中
  int _restCountdown = 0; // 休息倒计时
  Timer? _restTimer;
  final List<int> _roundScores = []; // 每轮得分
  int _totalExpGained = 0; // 本次练习累计获得 EXP
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
    // 已在试听 → 停止
    if (_previewing) {
      setState(() => _previewing = false);
      return;
    }
    setState(() => _previewing = true);
    final noteDuration = Duration(milliseconds: 60000 * 2 ~/ _bpm);
    for (final item in _items) {
      if (!_previewing) break;
      if (item.chordFrets != null) {
        // 和弦：依次快速播放 4 根弦（模拟扫弦）
        _playChordStrum(item);
      } else {
        // 单音
        playTone(name: item.name, octave: item.octave, type: _toneType);
      }
      await Future.delayed(noteDuration);
    }
    if (_previewing) setState(() => _previewing = false);
  }

  /// 播放和弦扫弦（依次拨响 4 根弦，模拟扫弦效果）
  void _playChordStrum(PracticeItem item) {
    // frets [G,C,E,A] → 对应弦的音名+八度
    final stringNotes = [
      ('G', 4), ('C', 4), ('E', 4), ('A', 4),
    ];
    for (var i = 0; i < 4; i++) {
      final fret = item.chordFrets![i];
      if (fret < 0) continue; // 闷音不弹
      // 品位 0=空弦，品位>0 升对应半音
      final base = stringNotes[i];
      final (name, octave) = _fretToNote(base.$1, base.$2, fret);
      // 依次播放（间隔 30ms 模拟扫弦）
      Future.delayed(Duration(milliseconds: i * 30), () {
        if (_previewing) {
          playTone(name: name, octave: octave, type: _toneType);
        }
      });
    }
  }

  /// 品位 → 实际音名+八度
  (String, int) _fretToNote(String baseName, int baseOctave, int fret) {
    if (fret == 0) return (baseName, baseOctave);
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    var idx = names.indexOf(baseName);
    idx += fret;
    var octave = baseOctave;
    while (idx >= 12) { idx -= 12; octave++; }
    while (idx < 0) { idx += 12; octave--; }
    return (names[idx], octave);
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
      _totalExpGained = 0;
    });
    await _startRound();
  }

  /// 启动一轮练习
  Future<void> _startRound() async {
    ref.invalidate(scoringEngineProvider);
    final beatMs = 60000 * 2 ~/ _bpm; // 每音符 2 拍
    final isChordMode = _mode == PracticeMode.chord;
    final targets = <TargetNote>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      targets.add(TargetNote(
        name: it.name,
        octave: it.octave,
        start: Duration(milliseconds: i * beatMs),
        duration: Duration(milliseconds: beatMs),
        isChord: isChordMode, // 和弦模式走 Chroma 识别
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

    // 上报游戏化系统：获得 EXP（每轮都算一次练习）
    final exp = ref.read(gameProvider.notifier).reportPractice(PracticeResult(
      score: score,
      durationSeconds: _items.length * (60000 * 2 ~/ _bpm) ~/ 1000,
      songCompleted: true,
    ));
    _totalExpGained += exp;

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
            if (!_started && !_loopDone && _mode != PracticeMode.song) _buildToolbar(),
            // ── 整曲练习模式（独立流程）──
            if (_mode == PracticeMode.song)
              _buildSongArea()
            else ...[
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
                expGained: _totalExpGained,
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
            ], // end else (非整曲模式)
          ],
        ),
      ),
    );
  }

  // ─── 整曲练习 ───
  Widget _buildSongArea() {
    final songState = ref.watch(practiceSongTrackerProvider);
    final song = kSongs[_songIdx];

    // 完成报告
    if (songState.finished && _songStarted) {
      return _PracticeSongReport(state: songState, song: song, onRetry: () {
        ref.read(practiceSongTrackerProvider.notifier).reset();
        setState(() => _songStarted = false);
      });
    }
    // 练习中
    if (_songStarted && songState.isRunning) {
      return _PracticeSongView(state: songState, song: song, onQuit: () {
        ref.read(practiceSongTrackerProvider.notifier).stop();
        setState(() => _songStarted = false);
      });
    }
    // 起始选歌页
    return _buildSongStart(songState);
  }

  Widget _buildSongStart(PracticeSongState songState) {
    final song = kSongs[_songIdx];
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🎵 选择歌曲',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // 歌曲列表
            ...kSongs.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value;
              final selected = i == _songIdx;
              return GestureDetector(
                onTap: () => setState(() => _songIdx = i),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.orange.withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AppColors.orange : Colors.transparent, width: 2),
                  ),
                  child: Row(children: [
                    const Icon(Icons.music_note, color: AppColors.teal, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, style: TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(s.artist, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('和弦：${s.chordSequence.map((c) => c.name).toSet().join(' · ')}',
                            style: const TextStyle(color: AppColors.text3, fontSize: 11)),
                      ],
                    )),
                    Text('${s.chordSequence.length}和弦',
                        style: const TextStyle(color: AppColors.teal, fontSize: 12)),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 16),
            // 当前歌曲预览（歌词+和弦）
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white10, borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📜 ${song.title} 歌词预览',
                      style: const TextStyle(color: AppColors.teal, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...song.lyrics.map((line) => _LyricPreviewX(line: line, frets: song.chordFrets)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 子模式切换：单音旋律 / 和弦伴奏
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('和弦伴奏', style: TextStyle(fontSize: 12)),
                  selected: !_songSingleNote,
                  selectedColor: AppColors.orange,
                  labelStyle: TextStyle(color: !_songSingleNote ? Colors.white : AppColors.text3),
                  onSelected: (_) => setState(() => _songSingleNote = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('单音旋律', style: TextStyle(fontSize: 12)),
                  selected: _songSingleNote,
                  selectedColor: AppColors.teal,
                  labelStyle: TextStyle(color: _songSingleNote ? Colors.white : AppColors.text3),
                  onSelected: (_) => setState(() => _songSingleNote = true),
                ),
                const SizedBox(width: 8),
                // 配乐开关
                GestureDetector(
                  onTap: () => setState(() => _songAccompaniment = !_songAccompaniment),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _songAccompaniment ? AppColors.teal.withValues(alpha: 0.3) : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _songAccompaniment ? AppColors.teal : Colors.transparent),
                    ),
                    child: Text(_songAccompaniment ? '🔊 配乐' : '🔇 静音',
                        style: TextStyle(color: _songAccompaniment ? AppColors.teal : AppColors.text3, fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // BPM 可调
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('速度', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() { if (_songBpm > 40) _songBpm -= 5; }),
                  child: Container(width: 28, height: 28,
                    decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                    child: const Icon(Icons.remove, color: Colors.white, size: 16)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$_songBpm', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                GestureDetector(
                  onTap: () => setState(() { if (_songBpm < 140) _songBpm += 5; }),
                  child: Container(width: 28, height: 28,
                    decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white, size: 16)),
                ),
                const SizedBox(width: 4),
                const Text('BPM', style: TextStyle(color: AppColors.text3, fontSize: 10)),
                const SizedBox(width: 20),
                // 循环次数
                const Text('循环', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                const SizedBox(width: 6),
                for (final r in [1, 3, 5])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text('$r', style: const TextStyle(fontSize: 11)),
                      selected: _songRounds == r,
                      selectedColor: AppColors.orange,
                      labelStyle: TextStyle(color: _songRounds == r ? Colors.white : AppColors.text3),
                      onSelected: (_) => setState(() => _songRounds = r),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 开始按钮 → 进入横屏整曲页面
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SongLandscapePage(
                      song: song,
                      isSingleNote: _songSingleNote,
                      accompaniment: _songAccompaniment,
                      bpm: _songBpm,
                      rounds: _songRounds,
                    ),
                  ));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('🎵 开始弹唱（横屏）',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _songSingleNote
                  ? '跟着节奏弹响旋律单音，配乐会带你找到节奏'
                  : '跟着节奏扫响每个和弦，配乐会带你找到节奏',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text3, fontSize: 11)),
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
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('整曲练习', style: TextStyle(fontSize: 12)),
                selected: _mode == PracticeMode.song,
                selectedColor: AppColors.orange,
                labelStyle: TextStyle(
                    color: _mode == PracticeMode.song ? Colors.white : AppColors.text3),
                onSelected: (_) => setState(() => _mode = PracticeMode.song),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          children: [
            Text(
              _mode == PracticeMode.single ? '🎯 C 大调音阶' : '🎯 和弦转换 C-G-Am-F',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            // 序列预览（紧凑）
            Wrap(
              spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
              children: _items
                  .map((it) => Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
                        ),
                        alignment: Alignment.center,
                        child: Text(it.label,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // 和弦模式：横向缩略和弦图（紧凑，避免超屏）
            if (_mode == PracticeMode.chord) ...[
              _ChordThumbStrip(items: _chordItems),
              const SizedBox(height: 12),
            ],
            // 循环练习设置（紧凑）
            _buildLoopSettings(),
            const SizedBox(height: 12),
            // 开始按钮
            SizedBox(
              width: double.infinity, height: 48,
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
            const SizedBox(height: 6),
            Text(
              _mode == PracticeMode.single
                  ? '依次弹响每个音，系统实时评分'
                  : '依次扫响每个和弦（评根音），系统实时评分',
              style: const TextStyle(color: AppColors.text3, fontSize: 11),
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
  final int expGained; // 本次获得的总 EXP
  final VoidCallback onRetry;
  const _LoopReport({required this.scores, required this.expGained, required this.onRetry});

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
            const SizedBox(height: 8),
            // EXP 收益提示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.teal.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text('获得 $expGained 经验值',
                      style: const TextStyle(
                          color: AppColors.teal, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
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
        ]),
      ),
    );
  }
}

/// 和弦横向缩略图条（紧凑版，替代 _ChordSequenceView 的大图轮播）
/// 起始页用：横向排列所有和弦的迷你指法图，一屏放下不超屏。
class _ChordThumbStrip extends StatelessWidget {
  final List<PracticeItem> items;
  const _ChordThumbStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const SizedBox(width: 4),
          for (final it in items) ...[
            Container(
              width: 72,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Text(it.label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Expanded(
                    child: it.chordFrets != null
                        ? ChordDiagram(frets: it.chordFrets!, fretCount: 5)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            if (items.indexOf(it) < items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 35),
                child: Icon(Icons.arrow_forward_ios, color: AppColors.text3, size: 12),
              ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 整曲练习：进度跟踪器
// ─────────────────────────────────────────────

/// 整曲练习状态
@immutable
class PracticeSongState {
  final bool isRunning;
  final int currentIndex; // 当前应弹项（和弦或单音）的 index
  final int totalItems;
  final int currentBeat; // 当前和弦的第几拍（0起，节奏指示用）
  final List<_ItemResult> results; // 每项的对错记录（pending/correct/wrong/skip）
  final bool finished;
  final bool isSingleNote; // 单音模式 vs 和弦模式

  const PracticeSongState({
    this.isRunning = false,
    this.currentIndex = 0,
    this.totalItems = 0,
    this.currentBeat = 0,
    this.results = const [],
    this.finished = false,
    this.isSingleNote = false,
  });

  int get correctCount => results.where((r) => r == _ItemResult.correct).length;
  double get progress => totalItems == 0 ? 0 : currentIndex / totalItems;
  int get scorePercent {
    if (results.isEmpty) return 0;
    return (correctCount * 100 ~/ results.length);
  }
}

/// 单项判定结果
enum _ItemResult { pending, correct, wrong, skip }

/// 整曲练习进度跟踪器（节奏驱动模式）
///
/// 与之前的"弹对才走"不同：配乐按 BPM 自动播放，和弦按节奏自动推进。
/// 用户在每个时间窗口内弹对→标记绿，弹错→红，没弹到→灰。
class PracticeSongTracker extends StateNotifier<PracticeSongState> {
  final PitchDetectionService _pitchService;
  StreamSubscription<PitchResult>? _sub;
  ChordRecognizer? _recognizer;
  Timer? _beatTimer;

  // 和弦模式数据
  List<PracticeChord> _chords = [];
  // 单音模式数据
  List<PracticeNote> _notes = [];
  // 当前是否单音模式
  bool _isSingleNote = false;
  // 节奏参数
  int _bpm = 80;
  // 当前项在第几拍（用于多拍和弦的节奏指示）
  int _beatInItem = 0;
  // 当前项的剩余拍数
  int _remainingBeats = 0;
  // 当前窗口内用户是否已弹对（避免重复计分）
  bool _matchedInWindow = false;
  // 配乐开关
  bool _accompanimentOn = true;

  PracticeSongTracker(this._pitchService) : super(const PracticeSongState());

  /// 开始整曲练习
  /// [isSingleNote] true=单音旋律版，false=和弦伴奏版
  void start(PracticeSong song, {bool isSingleNote = false, bool accompaniment = true}) async {
    _isSingleNote = isSingleNote;
    _accompanimentOn = accompaniment;
    _bpm = song.bpm;
    _recognizer = ChordRecognizer(_pitchService.actualSampleRate);

    if (isSingleNote) {
      _notes = song.noteSequence;
      _chords = [];
    } else {
      _chords = song.chordSequence;
      _notes = [];
    }

    final total = isSingleNote ? _notes.length : _chords.length;
    if (total == 0) return;

    state = PracticeSongState(
      isRunning: true,
      currentIndex: 0,
      totalItems: total,
      currentBeat: 0,
      results: List.filled(total, _ItemResult.pending),
      isSingleNote: isSingleNote,
    );

    _beatInItem = 0;
    _remainingBeats = _currentItemBeats();
    _matchedInWindow = false;

    // 播放第一个和弦/单音的配乐
    _playAccompaniment();

    // 启动麦克风识别
    _sub = _pitchService.pitchStream.listen(_onPitch);
    try {
      await _pitchService.start();
    } catch (e) {
      state = PracticeSongState(isRunning: false, finished: true, isSingleNote: isSingleNote);
      return;
    }

    // 启动节拍定时器（每拍一次，驱动节奏推进）
    final beatMs = 60000 ~/ _bpm;
    _beatTimer = Timer.periodic(Duration(milliseconds: beatMs), (_) => _onBeat());
  }

  /// 当前项的持续拍数
  int _currentItemBeats() {
    final idx = state.currentIndex;
    if (idx >= state.totalItems) return 1;
    if (_isSingleNote) {
      return _notes[idx].beats;
    }
    return _chords[idx].beats;
  }

  /// 当前项的名称（和弦名或音名）
  String _currentItemName() {
    final idx = state.currentIndex;
    if (idx >= state.totalItems) return '';
    if (_isSingleNote) return _notes[idx].name;
    return _chords[idx].name;
  }

  /// 每拍回调：驱动节奏推进
  void _onBeat() {
    if (!state.isRunning) return;
    _beatInItem++;
    _remainingBeats--;

    // 更新节拍指示（UI 闪烁用）
    state = PracticeSongState(
      isRunning: true,
      currentIndex: state.currentIndex,
      totalItems: state.totalItems,
      currentBeat: _beatInItem,
      results: state.results,
      isSingleNote: _isSingleNote,
    );

    if (_remainingBeats <= 0) {
      // 当前项时间窗口结束 → 判定结果 + 推进到下一项
      _onItemEnd();
    }
  }

  /// 当前项时间窗口结束
  void _onItemEnd() {
    // 判定：窗口内没弹对 → 标记 skip（没弹到）
    final idx = state.currentIndex;
    final newResults = List<_ItemResult>.from(state.results);
    if (newResults[idx] == _ItemResult.pending) {
      newResults[idx] = _ItemResult.skip;
    }

    final nextIdx = idx + 1;
    if (nextIdx >= state.totalItems) {
      // 全曲结束
      _finish(newResults);
      return;
    }

    // 推进到下一项
    _beatInItem = 0;
    _remainingBeats = _isSingleNote ? _notes[nextIdx].beats : _chords[nextIdx].beats;
    _matchedInWindow = false;

    state = PracticeSongState(
      isRunning: true,
      currentIndex: nextIdx,
      totalItems: state.totalItems,
      currentBeat: 0,
      results: newResults,
      isSingleNote: _isSingleNote,
    );

    // 播放下一项的配乐
    _playAccompaniment();
  }

  /// 播放配乐（当前和弦/单音）
  void _playAccompaniment() {
    if (!_accompanimentOn) return;
    final name = _currentItemName();
    if (name.isEmpty) return;
    if (_isSingleNote) {
      // 单音模式：播单音
      final note = _notes[state.currentIndex];
      playTone(name: note.name, octave: note.octave, type: ToneType.strum);
    } else {
      // 和弦模式：播和弦扫弦（用拨弦音色，根音+泛音）
      playTone(name: name, type: ToneType.strum);
    }
  }

  /// 麦克风识别回调：判定用户弹的对错
  void _onPitch(PitchResult r) {
    if (!state.isRunning || _matchedInWindow) return;
    if (r.samples == null || r.samples!.isEmpty) return;
    if (r.energy < 0.02) return;

    final target = _currentItemName();
    if (target.isEmpty) return;

    bool matched = false;
    if (_isSingleNote) {
      // 单音模式：NCCF 频率 → 音名匹配
      if (r.frequency != null) {
        final info = frequencyToNote(r.frequency!);
        matched = info.name == target;
      }
    } else {
      // 和弦模式：Chroma 整和弦识别
      final result = _recognizer!.recognizeDetailed(
        r.samples!.toList(),
        sampleRate: _pitchService.actualSampleRate,
      );
      matched = result.chord == target ||
          (result.bestMatch == target && result.score > 0.6);
    }

    if (matched) {
      _matchedInWindow = true;
      final newResults = List<_ItemResult>.from(state.results);
      newResults[state.currentIndex] = _ItemResult.correct;
      state = PracticeSongState(
        isRunning: true,
        currentIndex: state.currentIndex,
        totalItems: state.totalItems,
        currentBeat: _beatInItem,
        results: newResults,
        isSingleNote: _isSingleNote,
      );
    }
  }

  void _finish(List<_ItemResult> results) {
    _beatTimer?.cancel();
    _beatTimer = null;
    _sub?.cancel();
    _pitchService.stop();
    state = PracticeSongState(
      isRunning: false,
      finished: true,
      totalItems: state.totalItems,
      results: results,
      currentIndex: state.totalItems,
      isSingleNote: _isSingleNote,
    );
  }

  void stop() {
    _beatTimer?.cancel();
    _beatTimer = null;
    _sub?.cancel();
    _pitchService.stop();
    state = PracticeSongState(
      isRunning: false,
      finished: true,
      totalItems: state.totalItems,
      results: state.results,
      isSingleNote: _isSingleNote,
    );
  }

  void reset() {
    _beatTimer?.cancel();
    _beatTimer = null;
    _sub?.cancel();
    state = const PracticeSongState();
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final practiceSongTrackerProvider =
    StateNotifierProvider<PracticeSongTracker, PracticeSongState>((ref) {
  return PracticeSongTracker(ref.read(pitchServiceProvider));
});

// ─────────────────────────────────────────────
// 整曲练习：UI 组件
// ─────────────────────────────────────────────

/// 歌词预览（起始页用，静态展示歌词+和弦/单音）
class _LyricPreviewX extends StatelessWidget {
  final PracticeLyric line;
  final Map<String, List<int>> frets;
  const _LyricPreviewX({required this.line, required this.frets});

  @override
  Widget build(BuildContext context) {
    final sorted = List<PracticeChord>.from(line.chords)
      ..sort((a, b) => a.position.compareTo(b.position));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sorted.isNotEmpty) Row(children: _buildChordRow(sorted)),
          Text(
            line.text + (line.notes != null
                ? '  (${line.notes!.map((n) => n.name).join(' ')})'
                : ''),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildChordRow(List<PracticeChord> sorted) {
    final widgets = <Widget>[];
    var lastPos = 0;
    for (final c in sorted) {
      final gap = (c.position - lastPos) * 14.0;
      if (gap > 0) widgets.add(SizedBox(width: gap));
      widgets.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(c.name,
            style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
      ));
      lastPos = c.position + c.name.length;
    }
    return widgets;
  }
}

/// 整曲练习视图（节奏驱动，配乐滚动）
class _PracticeSongView extends StatelessWidget {
  final PracticeSongState state;
  final PracticeSong song;
  final VoidCallback onQuit;
  const _PracticeSongView({required this.state, required this.song, required this.onQuit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          // 顶栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onQuit,
                  child: const Icon(Icons.close, color: Colors.white70, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(song.title,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text(state.isSingleNote ? '单音旋律' : '和弦伴奏',
                            style: const TextStyle(color: AppColors.teal, fontSize: 11)),
                      ]),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: state.progress,
                        backgroundColor: Colors.white12,
                        color: AppColors.orange, minHeight: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('${state.currentIndex + 1}/${state.totalItems}',
                    style: const TextStyle(color: AppColors.teal, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          _CurrentChordHintX(state: state, song: song),
          _BeatFlash(state: state),
          Expanded(child: _SongLyricScroll(state: state, song: song)),
        ],
      ),
    );
  }
}

/// 节拍闪烁指示
class _BeatFlash extends StatelessWidget {
  final PracticeSongState state;
  const _BeatFlash({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final active = i <= (state.currentBeat % 4);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 16 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? AppColors.orange : Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

/// 当前和弦/单音提示
class _CurrentChordHintX extends StatelessWidget {
  final PracticeSongState state;
  final PracticeSong song;
  const _CurrentChordHintX({required this.state, required this.song});

  @override
  Widget build(BuildContext context) {
    if (state.currentIndex >= state.totalItems) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('🎉 完成！', style: TextStyle(color: AppColors.ok, fontSize: 22, fontWeight: FontWeight.bold)),
      );
    }
    final isChord = !state.isSingleNote;
    final name = isChord
        ? song.chordSequence[state.currentIndex].name
        : song.noteSequence[state.currentIndex].name;
    final frets = song.chordFrets[name];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(isChord ? '当前和弦' : '当前音符', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.orange, borderRadius: BorderRadius.circular(999),
                ),
                child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              ),
              if (isChord && frets != null) ...[
                const SizedBox(width: 16),
                Container(
                  width: 64, height: 64,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)],
                  ),
                  child: ChordDiagram(frets: frets, fretCount: 5),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(isChord ? '👆 跟着节奏扫响这个和弦' : '👆 跟着节奏弹响这个音',
              style: const TextStyle(color: AppColors.teal, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 歌词滚动区（按节奏高亮当前项）
class _SongLyricScroll extends StatelessWidget {
  final PracticeSongState state;
  final PracticeSong song;
  const _SongLyricScroll({required this.state, required this.song});

  @override
  Widget build(BuildContext context) {
    var globalIdx = 0;
    final isChord = !state.isSingleNote;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: song.lyrics.map((line) {
          final items = isChord ? line.chords : (line.notes ?? []);
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(line.text, style: const TextStyle(color: Colors.white54, fontSize: 14)),
            );
          }
          final itemWidgets = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            final thisIdx = globalIdx++;
            final name = isChord
                ? (items[i] as PracticeChord).name
                : (items[i] as PracticeNote).name;
            final isCurrent = thisIdx == state.currentIndex && state.isRunning;
            final result = thisIdx < state.results.length ? state.results[thisIdx] : _ItemResult.pending;
            Color bg; Color fg;
            if (isCurrent) {
              bg = AppColors.orange; fg = Colors.white;
            } else if (result == _ItemResult.correct) {
              bg = AppColors.ok.withValues(alpha: 0.3); fg = AppColors.ok;
            } else if (result == _ItemResult.skip) {
              bg = Colors.white10; fg = AppColors.text3;
            } else {
              bg = Colors.white12; fg = Colors.white54;
            }
            itemWidgets.add(Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: isCurrent ? Border.all(color: AppColors.orange, width: 2) : null,
              ),
              child: Text(name, style: TextStyle(
                color: fg,
                fontSize: isCurrent ? 16 : 13,
                fontWeight: FontWeight.bold,
              )),
            ));
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(children: itemWidgets),
                const SizedBox(height: 2),
                Text(line.text, style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), fontSize: 15, height: 1.4)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 整曲完成报告
class _PracticeSongReport extends StatelessWidget {
  final PracticeSongState state;
  final PracticeSong song;
  final VoidCallback onRetry;
  const _PracticeSongReport({required this.state, required this.song, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final correct = state.correctCount;
    final total = state.totalItems;
    final percent = state.scorePercent;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉 弹唱完成！',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('《${song.title}》${state.isSingleNote ? '(单音)' : '(和弦)'}',
                  style: const TextStyle(color: AppColors.text3, fontSize: 16)),
              const SizedBox(height: 24),
              SizedBox(
                width: 150, height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(width: 150, height: 150,
                    child: CircularProgressIndicator(
                      value: percent / 100, strokeWidth: 12,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                          percent >= 80 ? AppColors.ok : (percent >= 60 ? AppColors.warn : AppColors.err)))),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$percent%', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1)),
                    const Text('准确率', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              Text('$correct / $total ${state.isSingleNote ? "音" : "和弦"}弹对',
                  style: const TextStyle(color: AppColors.teal, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                  child: const Text('🎵 再弹一次',
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

// ══════════════════════════════════════════════════════════════════
// 横屏整曲弹唱页面（流水滚动 + 判定线 + 配乐 + 循环）
// ══════════════════════════════════════════════════════════════════

/// 时间轴上的一个事件（和弦或单音）
class _TimelineEvent {
  final double timeSec;
  final double durationSec;
  final String name;
  final int octave;
  final List<int>? frets;
  final int stringIdx; // 弦索引（单音 TAB 用，0-3 = G,C,E,A）
  final int fret; // 品数（单音 TAB 用）
  final String? lyric; // 对应歌词片段（和弦版用）

  _TimelineEvent({
    required this.timeSec,
    required this.durationSec,
    required this.name,
    this.octave = 4,
    this.frets,
    this.stringIdx = -1,
    this.fret = 0,
    this.lyric,
  });
}

class SongLandscapePage extends ConsumerStatefulWidget {
  final PracticeSong song;
  final bool isSingleNote;
  final bool accompaniment;
  final int bpm;
  final int rounds;

  const SongLandscapePage({
    super.key,
    required this.song,
    required this.isSingleNote,
    required this.accompaniment,
    required this.bpm,
    required this.rounds,
  });

  @override
  ConsumerState<SongLandscapePage> createState() => _SongLandscapePageState();
}

class _SongLandscapePageState extends ConsumerState<SongLandscapePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  Timer? _beatTimer;
  StreamSubscription<PitchResult>? _pitchSub;
  ChordRecognizer? _recognizer;

  List<_TimelineEvent> _events = [];
  double _totalDuration = 0;
  int _currentIdx = 0;
  int _currentBeat = 0;
  List<_ItemResult> _results = [];
  bool _matchedInWindow = false;
  DateTime? _lastMatchTime;
  int _currentRound = 0;
  List<int> _roundScores = [];
  bool _accompanimentOn = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _accompanimentOn = widget.accompaniment;
    _buildTimeline();
    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_totalDuration * 1000).round()),
    )..addListener(() => setState(() {}));
    _startRound();
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _pitchSub?.cancel();
    _animCtrl.dispose();
    ref.read(pitchServiceProvider).stop();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _buildTimeline() {
    _events = [];
    final beatSec = 60.0 / widget.bpm;
    var time = 0.0;
    if (widget.isSingleNote) {
      for (final note in widget.song.noteSequence) {
        final dur = note.beats * beatSec;
        int si = 0, fr = 0;
        // 简化品数推算（C4-C5 常用位置）
        if (note.name == 'C' && note.octave == 4) { si = 2; fr = 0; }
        else if (note.name == 'D') { si = 2; fr = 2; }
        else if (note.name == 'E') { si = 1; fr = 0; }
        else if (note.name == 'F') { si = 1; fr = 1; }
        else if (note.name == 'G' && note.octave == 4) { si = 3; fr = 0; }
        else if (note.name == 'A') { si = 0; fr = 0; }
        else if (note.name == 'B') { si = 0; fr = 2; }
        else if (note.name == 'C' && note.octave == 5) { si = 0; fr = 3; }
        _events.add(_TimelineEvent(timeSec: time, durationSec: dur, name: note.name, octave: note.octave, stringIdx: si, fret: fr));
        time += dur;
      }
    } else {
      // 和弦伴奏版：从 lyrics 遍历，关联歌词
      for (final line in widget.song.lyrics) {
        final sorted = List<PracticeChord>.from(line.chords)
          ..sort((a, b) => a.position.compareTo(b.position));
        if (sorted.isEmpty) {
          // 无和弦的纯歌词行（给一个空白和弦占位）
          final dur = beatSec * 2;
          _events.add(_TimelineEvent(timeSec: time, durationSec: dur, name: '', lyric: line.text));
          time += dur;
          continue;
        }
        for (var ci = 0; ci < sorted.length; ci++) {
          final chord = sorted[ci];
          final dur = chord.beats * beatSec;
          // 提取这个和弦对应的歌词片段
          final startPos = chord.position;
          final endPos = ci + 1 < sorted.length ? sorted[ci + 1].position : line.text.length;
          final lyricText = line.text.substring(startPos, endPos.clamp(0, line.text.length));
          _events.add(_TimelineEvent(
            timeSec: time, durationSec: dur, name: chord.name,
            frets: widget.song.chordFrets[chord.name], lyric: lyricText,
          ));
          time += dur;
        }
      }
    }
    _totalDuration = time + beatSec * 2;
  }

  void _startRound() {
    _currentIdx = 0;
    _currentBeat = 0;
    _matchedInWindow = false;
    _results = List.filled(_events.length, _ItemResult.pending);
    _animCtrl.reset();
    _recognizer = ChordRecognizer(ref.read(pitchServiceProvider).actualSampleRate);

    _pitchSub?.cancel();
    ref.read(pitchServiceProvider).start().then((_) {
      _pitchSub = ref.read(pitchServiceProvider).pitchStream.listen(_onPitch);
    }).catchError((_) {});

    _animCtrl.forward();
    final beatMs = 60000 ~/ widget.bpm;
    _playAccompaniment();
    _beatTimer = Timer.periodic(Duration(milliseconds: beatMs), (_) => _onBeat());
  }

  void _onBeat() {
    if (!mounted) return;
    _currentBeat++;
    if (_currentIdx < _events.length) {
      final event = _events[_currentIdx];
      final eventEndBeat = ((event.timeSec + event.durationSec) / (60.0 / widget.bpm)).round();
      if (_currentBeat >= eventEndBeat) {
        if (_results[_currentIdx] == _ItemResult.pending) {
          _results[_currentIdx] = _ItemResult.skip;
        }
        _currentIdx++;
        _matchedInWindow = false;
        if (_currentIdx >= _events.length) {
          _onRoundEnd();
          return;
        }
        _playAccompaniment();
      }
    }
    setState(() {});
  }

  void _playAccompaniment() {
    if (!_accompanimentOn || _currentIdx >= _events.length) return;
    final event = _events[_currentIdx];
    if (widget.isSingleNote) {
      playTone(name: event.name, octave: event.octave, type: ToneType.strum);
    } else {
      playTone(name: event.name, type: ToneType.strum);
    }
  }

  void _onPitch(PitchResult r) {
    if (!mounted || _matchedInWindow || _currentIdx >= _events.length || r.energy < 0.02) return;
    final target = _events[_currentIdx].name;
    bool matched = false;
    if (widget.isSingleNote) {
      if (r.frequency != null) {
        matched = frequencyToNote(r.frequency!).name == target;
      }
    } else if (r.samples != null && r.samples!.isNotEmpty) {
      final result = _recognizer!.recognizeDetailed(r.samples!.toList(), sampleRate: ref.read(pitchServiceProvider).actualSampleRate);
      matched = result.chord == target || (result.bestMatch == target && result.score > 0.6);
    }
    if (matched) {
      final now = DateTime.now();
      if (_lastMatchTime != null && now.difference(_lastMatchTime!) < const Duration(milliseconds: 300)) return;
      _lastMatchTime = now;
      _matchedInWindow = true;
      _results[_currentIdx] = _ItemResult.correct;
      setState(() {});
    }
  }

  void _onRoundEnd() {
    _beatTimer?.cancel();
    _pitchSub?.cancel();
    ref.read(pitchServiceProvider).stop();
    _animCtrl.stop();
    final correct = _results.where((r) => r == _ItemResult.correct).length;
    final score = _events.isEmpty ? 0 : (correct * 100 ~/ _events.length);
    _roundScores.add(score);
    ref.read(gameProvider.notifier).reportPractice(PracticeResult(score: score, durationSeconds: _totalDuration.round(), songCompleted: true));
    _currentRound++;
    setState(() {});
    if (_currentRound < widget.rounds) {
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _startRound(); });
    }
  }

  void _quit() {
    _beatTimer?.cancel();
    _pitchSub?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allDone = _currentRound >= widget.rounds;
    final isResting = !allDone && _currentIdx >= _events.length;
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(child: allDone ? _buildSummary() : (isResting ? _buildRest() : _buildPracticeView())),
    );
  }

  Widget _buildPracticeView() {
    final sw = MediaQuery.of(context).size.width;
    final judgmentX = sw * 0.35;
    final pps = sw * 0.25;
    return Stack(children: [
      Positioned.fill(child: widget.isSingleNote ? _buildTabHighway(sw, judgmentX, pps) : _buildChordHighway(sw, judgmentX, pps)),
      // 判定线
      Positioned(left: judgmentX - 2, top: 0, bottom: 50,
        child: Container(width: 4, decoration: BoxDecoration(color: AppColors.orange,
          boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.5), blurRadius: 12)]))),
      // 顶栏
      Positioned(top: 4, left: 16, right: 16, child: Row(children: [
        GestureDetector(onTap: _quit, child: const Icon(Icons.close, color: Colors.white70, size: 22)),
        const SizedBox(width: 8),
        Text(widget.song.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text('第${_currentRound + 1}/${widget.rounds}轮', style: const TextStyle(color: AppColors.teal, fontSize: 11)),
        const Spacer(),
        Text('${_results.where((r) => r == _ItemResult.correct).length}/${_events.length}',
            style: const TextStyle(color: AppColors.teal, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        GestureDetector(onTap: () => setState(() => _accompanimentOn = !_accompanimentOn),
          child: Text(_accompanimentOn ? '🔊' : '🔇', style: const TextStyle(fontSize: 18))),
      ])),
      // 节拍指示
      Positioned(bottom: 4, left: 0, right: 0, child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final active = i == (_currentBeat % 4);
          return Container(margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 14 : 7, height: 7,
            decoration: BoxDecoration(color: active ? AppColors.orange : Colors.white12, borderRadius: BorderRadius.circular(4)));
        }),
      )),
    ]);
  }

  Widget _buildChordHighway(double sw, double judgmentX, double pps) {
    final elapsed = _currentBeat * (60.0 / widget.bpm);
    return Stack(children: _events.asMap().entries.map((e) {
      final i = e.key; final event = e.value;
      final dx = (event.timeSec - elapsed) * pps + judgmentX;
      if (dx < -150 || dx > sw + 150) return const SizedBox.shrink();
      final result = i < _results.length ? _results[i] : _ItemResult.pending;
      final isCurrent = i == _currentIdx;
      final isPast = i < _currentIdx;
      Color bg = isCurrent ? AppColors.orange
        : (result == _ItemResult.correct ? AppColors.ok.withValues(alpha: 0.3)
        : (isPast ? Colors.white10 : Colors.white.withValues(alpha: 0.08)));
      Color fg = isCurrent ? Colors.white
        : (result == _ItemResult.correct ? AppColors.ok : Colors.white70);
      return Positioned(left: dx, top: 35, bottom: 35, child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 和弦名
          if (event.name.isNotEmpty)
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
                border: isCurrent ? Border.all(color: AppColors.orange, width: 2) : null),
              child: Text(event.name, style: TextStyle(color: fg, fontSize: isCurrent ? 22 : 16, fontWeight: FontWeight.bold))),
          const SizedBox(height: 4),
          // 指法图
          if (event.frets != null)
            Container(width: isCurrent ? 54 : 40, height: isCurrent ? 54 : 40, padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: ChordDiagram(frets: event.frets!, fretCount: 5)),
          const SizedBox(height: 6),
          // 歌词
          if (event.lyric != null && event.lyric!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(event.lyric!,
                style: TextStyle(
                  color: isCurrent ? Colors.white : (isPast ? AppColors.text3 : Colors.white60),
                  fontSize: isCurrent ? 15 : 12,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ));
    }).toList());
  }

  Widget _buildTabHighway(double sw, double judgmentX, double pps) {
    final elapsed = _currentBeat * (60.0 / widget.bpm);
    final sColors = [const Color(0xFF4ADE80), const Color(0xFF60A5FA), const Color(0xFFF87171), const Color(0xFFFBBF24)];
    final sNames = ['G', 'C', 'E', 'A'];
    // 弦线 y 坐标：在屏幕垂直方向均匀分布 4 条弦
    final screenH = MediaQuery.of(context).size.height;
    final stringTop = screenH * 0.15; // 第一条弦距顶部
    final stringGap = screenH * 0.15; // 弦间距
    double stringY(int si) => stringTop + si * stringGap;

    return Stack(children: [
      // 四条弦线（固定背景）
      ...List.generate(4, (si) {
        final y = stringY(si);
        return Positioned(
          left: 20, right: 0, top: y,
          child: Row(children: [
            SizedBox(width: 14, child: Text(sNames[si],
                style: TextStyle(color: sColors[si], fontSize: 10, fontWeight: FontWeight.bold))),
            const SizedBox(width: 4),
            Expanded(child: Container(height: 2, color: sColors[si].withValues(alpha: 0.3))),
          ]),
        );
      }),
      // 音符（数字圆圈压在弦线上）
      ..._events.asMap().entries.map((e) {
        final i = e.key; final event = e.value;
        final dx = (event.timeSec - elapsed) * pps + judgmentX;
        if (dx < -50 || dx > sw + 50 || event.stringIdx < 0 || event.stringIdx > 3) return const SizedBox.shrink();
        final result = i < _results.length ? _results[i] : _ItemResult.pending;
        final isCurrent = i == _currentIdx;
        final isPast = i < _currentIdx;
        final noteSize = isCurrent ? 28.0 : 24.0;
        final y = stringY(event.stringIdx) + 1; // 弦线 center（弦线高 2px，中心+1）
        Color nc = isCurrent ? AppColors.orange
          : (result == _ItemResult.correct ? AppColors.ok
          : (isPast ? Colors.white24 : sColors[event.stringIdx]));
        return Positioned(
          left: dx - noteSize / 2,
          top: y - noteSize / 2, // 圆心对齐弦线
          child: Container(width: noteSize, height: noteSize,
            decoration: BoxDecoration(color: nc, shape: BoxShape.circle,
              border: isCurrent ? Border.all(color: Colors.white, width: 2) : null),
            alignment: Alignment.center,
            child: Text('${event.fret}', style: TextStyle(
              color: isCurrent || isPast ? Colors.white : Colors.black87,
              fontSize: isCurrent ? 16 : 13, fontWeight: FontWeight.bold))),
        );
      }),
    ]);
  }

  Widget _buildRest() {
    final last = _roundScores.isNotEmpty ? _roundScores.last : null;
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (last != null) ...[
        Text('第 $_currentRound 轮完成', style: const TextStyle(color: AppColors.text3, fontSize: 14)),
        const SizedBox(height: 4),
        Text('$last 分', style: TextStyle(color: last >= 80 ? AppColors.ok : AppColors.warn, fontSize: 36, fontWeight: FontWeight.w800)),
      ],
      const SizedBox(height: 20),
      const Text('3 秒后自动开始下一轮...', style: TextStyle(color: AppColors.teal, fontSize: 14)),
    ]));
  }

  Widget _buildSummary() {
    final avg = _roundScores.isEmpty ? 0 : (_roundScores.reduce((a, b) => a + b) / _roundScores.length).round();
    final best = _roundScores.isEmpty ? 0 : _roundScores.reduce((a, b) => a > b ? a : b);
    return Center(child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🎉 全部完成！', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('《${widget.song.title}》${widget.isSingleNote ? '(单音)' : '(和弦)'} ×${widget.rounds}轮',
            style: const TextStyle(color: AppColors.text3, fontSize: 14)),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _stat2('平均分', '$avg', avg >= 80 ? AppColors.ok : AppColors.warn),
          const SizedBox(width: 24),
          _stat2('最高分', '$best', AppColors.ok),
          const SizedBox(width: 24),
          _stat2('轮数', '${widget.rounds}', AppColors.teal),
        ]),
        const SizedBox(height: 24),
        ..._roundScores.asMap().entries.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 60, child: Text('第 ${e.key + 1} 轮', style: const TextStyle(color: AppColors.text3, fontSize: 12))),
            const SizedBox(width: 8),
            SizedBox(width: 200, child: Stack(children: [
              Container(height: 16, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8))),
              FractionallySizedBox(widthFactor: e.value / 100,
                child: Container(height: 16, decoration: BoxDecoration(
                  color: e.value >= 80 ? AppColors.ok : (e.value >= 60 ? AppColors.warn : AppColors.err),
                  borderRadius: BorderRadius.circular(8)))),
            ])),
            const SizedBox(width: 8),
            Text('${e.value}分', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]))),
        const SizedBox(height: 28),
        SizedBox(width: 200, height: 44, child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
          child: const Text('返回', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        )),
      ]),
    ));
  }

  Widget _stat2(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
    ]);
  }
}
