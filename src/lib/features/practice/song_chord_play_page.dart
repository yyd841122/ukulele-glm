/// 竖屏和弦弹唱页面（Chordify 式）
///
/// 对标 Chordify/OnSong/Ukeoke 的弹唱体验：
/// - 上半屏：当前和弦超大指法图 + 和弦名 + 节拍指示 + 判定反馈
/// - 下半屏：歌词+和弦整页匀速上滚（teleprompter），当前行高亮
/// - 配乐：StrumPatternScheduler 循环扫弦
/// - 判定：Chroma 和弦识别（弹对变绿，弹错/没弹标灰）
///
/// 与 SongLandscapePage（横屏高速路）的区别：
/// - 竖屏，不强制旋转
/// - 歌词可整句连读（弹唱核心需求）
/// - 当前和弦独占大图（新手看清指法）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/chord_recognizer.dart';
import '../../core/audio/music_utils.dart';
import '../../core/audio/pitch_service.dart';
import '../../core/audio/strum_engine.dart';
import '../../core/audio/tone_player.dart';
import '../../core/game/game_service.dart';
import '../../core/theme/app_theme.dart';
import 'chord_library_page.dart' show ChordDiagram;
import 'follow_score_page.dart';

class SongChordPlayPage extends ConsumerStatefulWidget {
  final PracticeSong song;
  final bool accompaniment;
  final int bpm;
  final int rounds;

  const SongChordPlayPage({
    super.key,
    required this.song,
    required this.accompaniment,
    required this.bpm,
    required this.rounds,
  });

  @override
  ConsumerState<SongChordPlayPage> createState() => _SongChordPlayPageState();
}

class _SongChordPlayPageState extends ConsumerState<SongChordPlayPage> {
  Timer? _beatTimer;
  StreamSubscription<PitchResult>? _pitchSub;
  ChordRecognizer? _recognizer;
  StrumPatternScheduler? _strumScheduler;

  // 时间轴（复用 follow_score 的 _TimelineEvent 结构）
  List<_ChordEvent> _events = [];
  double _totalDuration = 0;

  int _currentIdx = 0;
  int _currentBeat = 0;
  List<_Result> _results = [];
  bool _matchedInWindow = false;
  DateTime? _lastMatchTime;

  int _currentRound = 0;
  List<int> _roundScores = [];
  bool _accompanimentOn = true;
  bool _finished = false;
  bool _isResting = false;

  // 歌词滚动
  final ScrollController _lyricScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _accompanimentOn = widget.accompaniment;
    _buildTimeline();
    _startRound();
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _pitchSub?.cancel();
    _strumScheduler?.stop();
    _lyricScrollCtrl.dispose();
    ref.read(pitchServiceProvider).stop();
    super.dispose();
  }

  void _buildTimeline() {
    _events = [];
    final beatSec = 60.0 / widget.bpm;
    var time = 0.0;

    for (final line in widget.song.lyrics) {
      final sorted = List<PracticeChord>.from(line.chords)
        ..sort((a, b) => a.position.compareTo(b.position));
      if (sorted.isEmpty) {
        final dur = beatSec * 2;
        _events.add(_ChordEvent(timeSec: time, durationSec: dur, name: '', lyric: line.text));
        time += dur;
        continue;
      }
      for (var ci = 0; ci < sorted.length; ci++) {
        final chord = sorted[ci];
        final dur = chord.beats * beatSec;
        final startPos = chord.position;
        final endPos = ci + 1 < sorted.length ? sorted[ci + 1].position : line.text.length;
        final lyricText = line.text.substring(startPos, endPos.clamp(0, line.text.length));
        _events.add(_ChordEvent(
          timeSec: time, durationSec: dur, name: chord.name,
          frets: widget.song.chordFrets[chord.name], lyric: lyricText,
        ));
        time += dur;
      }
    }
    _totalDuration = time + beatSec * 2;
  }

  void _startRound() {
    _currentIdx = 0;
    _currentBeat = 0;
    _matchedInWindow = false;
    _results = List.filled(_events.length, _Result.pending);
    _recognizer = ChordRecognizer(ref.read(pitchServiceProvider).actualSampleRate);

    _pitchSub?.cancel();
    ref.read(pitchServiceProvider).start().then((_) {
      _pitchSub = ref.read(pitchServiceProvider).pitchStream.listen(_onPitch);
    }).catchError((_) {});

    // 预加载采样 + 启动扫弦调度器
    _strumScheduler?.stop();
    if (_accompanimentOn && _events.isNotEmpty) {
      final frets = _events[0].frets ?? [0, 0, 0, 3];
      preloadStrumSamples(widget.song.chordFrets.keys.toList());
      _strumScheduler = StrumPatternScheduler(bpm: widget.bpm, pattern: kPatternFolk, volume: 0.20);
      _strumScheduler!.setChord(frets);
      _strumScheduler!.start();
    }

    final beatMs = 60000 ~/ widget.bpm;
    _beatTimer = Timer.periodic(Duration(milliseconds: beatMs), (_) => _onBeat());
    setState(() {});
  }

  void _onBeat() {
    if (!mounted) return;
    _currentBeat++;

    if (_currentIdx < _events.length) {
      final event = _events[_currentIdx];
      final eventEndBeat = ((event.timeSec + event.durationSec) / (60.0 / widget.bpm)).round();
      if (_currentBeat >= eventEndBeat) {
        if (_results[_currentIdx] == _Result.pending) {
          _results[_currentIdx] = _Result.skip;
        }
        _currentIdx++;
        _matchedInWindow = false;

        if (_currentIdx >= _events.length) {
          _onRoundEnd();
          return;
        }
        // 切换配乐和弦
        if (_strumScheduler != null && _events[_currentIdx].frets != null) {
          _strumScheduler!.setChord(_events[_currentIdx].frets!);
        }
        // 滚动歌词到当前位置
        _scrollToCurrent();
      }
    }
    setState(() {});
  }

  void _scrollToCurrent() {
    // 计算当前事件在歌词中的大致行位置，滚动
    final lineHeight = 52.0;
    final offset = _currentIdx * lineHeight;
    _lyricScrollCtrl.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPitch(PitchResult r) {
    if (!mounted || _matchedInWindow || _currentIdx >= _events.length || r.energy < 0.02) return;
    final target = _events[_currentIdx].name;
    if (target.isEmpty) return;
    bool matched = false;
    if (r.samples != null && r.samples!.isNotEmpty) {
      final result = _recognizer!.recognizeDetailed(r.samples!.toList(), sampleRate: ref.read(pitchServiceProvider).actualSampleRate);
      matched = result.chord == target || (result.bestMatch == target && result.score > 0.6);
    }
    if (matched) {
      final now = DateTime.now();
      if (_lastMatchTime != null && now.difference(_lastMatchTime!) < const Duration(milliseconds: 300)) return;
      _lastMatchTime = now;
      _matchedInWindow = true;
      _results[_currentIdx] = _Result.correct;
      setState(() {});
    }
  }

  void _onRoundEnd() {
    _beatTimer?.cancel();
    _pitchSub?.cancel();
    _strumScheduler?.stop();
    ref.read(pitchServiceProvider).stop();
    final correct = _results.where((r) => r == _Result.correct).length;
    final score = _events.isEmpty ? 0 : (correct * 100 ~/ _events.length);
    _roundScores.add(score);
    ref.read(gameProvider.notifier).reportPractice(
      PracticeResult(score: score, durationSeconds: _totalDuration.round(), songCompleted: true),
    );
    _currentRound++;
    setState(() {});
    if (_currentRound < widget.rounds) {
      _isResting = true;
      setState(() {});
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _isResting = false;
          _startRound();
        }
      });
    } else {
      _finished = true;
      setState(() {});
    }
  }

  void _quit() {
    _beatTimer?.cancel();
    _pitchSub?.cancel();
    _strumScheduler?.stop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildSummary();
    if (_isResting) return _buildRest();
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(child: _buildPlayView()),
    );
  }

  Widget _buildPlayView() {
    final event = _currentIdx < _events.length ? _events[_currentIdx] : null;
    final result = _currentIdx < _results.length ? _results[_currentIdx] : _Result.pending;
    final isCorrect = result == _Result.correct;
    final frets = event?.frets;
    final nextEvent = _currentIdx + 1 < _events.length ? _events[_currentIdx + 1] : null;

    return Column(
      children: [
        // 顶栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              GestureDetector(onTap: _quit, child: const Icon(Icons.close, color: Colors.white70, size: 22)),
              const SizedBox(width: 8),
              Text(widget.song.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('第${_currentRound + 1}/${widget.rounds}轮', style: const TextStyle(color: AppColors.teal, fontSize: 11)),
              const Spacer(),
              Text('${_results.where((r) => r == _Result.correct).length}/${_events.length}',
                  style: const TextStyle(color: AppColors.teal, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() {
                  _accompanimentOn = !_accompanimentOn;
                  if (!_accompanimentOn) {
                    _strumScheduler?.stop();
                  } else if (_strumScheduler == null || !_strumScheduler!.isRunning) {
                    if (_currentIdx < _events.length && _events[_currentIdx].frets != null) {
                      _strumScheduler = StrumPatternScheduler(bpm: widget.bpm, pattern: kPatternFolk, volume: 0.20);
                      _strumScheduler!.setChord(_events[_currentIdx].frets!);
                      _strumScheduler!.start();
                    }
                  }
                }),
                child: Text(_accompanimentOn ? '🔊' : '🔇', style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
        // 上半屏：当前和弦大图 + 节拍
        Expanded(
          flex: 5,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 当前和弦名
                if (event != null && event.name.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCorrect ? AppColors.ok : AppColors.orange,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: AppSpacing.shadowHigh,
                    ),
                    child: Text(event.name,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 12),
                // 当前和弦指法图（大）
                if (frets != null)
                  Container(
                    width: 160, height: 160,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCorrect ? AppColors.ok : AppColors.orange,
                        width: isCorrect ? 3 : 2,
                      ),
                      boxShadow: [BoxShadow(
                        color: (isCorrect ? AppColors.ok : AppColors.orange).withValues(alpha: 0.3),
                        blurRadius: 20, spreadRadius: 3,
                      )],
                    ),
                    child: ChordDiagram(frets: frets, fretCount: 5),
                  ),
                const SizedBox(height: 10),
                // 下一个和弦预览
                if (nextEvent != null && nextEvent.name.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('下一个 → ', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(nextEvent.name, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                // 节拍闪烁
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final active = i == (_currentBeat % 4);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 16 : 8, height: 8,
                      decoration: BoxDecoration(
                        color: active ? AppColors.orange : Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        // 下半屏：歌词整页滚动
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E293B), Color(0xFF111827)],
              ),
            ),
            child: ListView.builder(
              controller: _lyricScrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 50),
              itemCount: _events.length,
              itemBuilder: (_, i) {
                final e = _events[i];
                final isCurrent = i == _currentIdx;
                final isPast = i < _currentIdx;
                final r = i < _results.length ? _results[i] : _Result.pending;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 和弦标签
                      if (e.name.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCurrent ? AppColors.orange
                              : (r == _Result.correct ? AppColors.ok.withValues(alpha: 0.3) : Colors.white10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(e.name, style: TextStyle(
                            color: isCurrent ? Colors.white
                              : (r == _Result.correct ? AppColors.ok : Colors.white54),
                            fontSize: isCurrent ? 16 : 13,
                            fontWeight: FontWeight.bold,
                          )),
                        ),
                      // 歌词
                      Expanded(
                        child: Text(e.lyric ?? '', style: TextStyle(
                          color: isCurrent ? Colors.white
                            : (isPast ? AppColors.text3 : Colors.white38),
                          fontSize: isCurrent ? 18 : 14,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          height: 1.4,
                        )),
                      ),
                      // 判定标记
                      if (r == _Result.correct)
                        const Text('✓', style: TextStyle(color: AppColors.ok, fontSize: 14)),
                      if (r == _Result.skip && isPast)
                        const Text('—', style: TextStyle(color: AppColors.text3, fontSize: 14)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRest() {
    final last = _roundScores.isNotEmpty ? _roundScores.last : null;
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (last != null) ...[
          Text('第 $_currentRound 轮完成', style: const TextStyle(color: AppColors.text3, fontSize: 14)),
          const SizedBox(height: 4),
          Text('$last 分', style: TextStyle(color: last >= 80 ? AppColors.ok : AppColors.warn, fontSize: 36, fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 20),
        const Text('3 秒后自动开始下一轮...', style: TextStyle(color: AppColors.teal, fontSize: 14)),
      ])),
    );
  }

  Widget _buildSummary() {
    final avg = _roundScores.isEmpty ? 0 : (_roundScores.reduce((a, b) => a + b) / _roundScores.length).round();
    final best = _roundScores.isEmpty ? 0 : _roundScores.reduce((a, b) => a > b ? a : b);
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🎉 全部完成！', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('《${widget.song.title}》×${widget.rounds}轮', style: const TextStyle(color: AppColors.text3, fontSize: 14)),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _stat('平均分', '$avg', avg >= 80 ? AppColors.ok : AppColors.warn),
            const SizedBox(width: 24),
            _stat('最高分', '$best', AppColors.ok),
            const SizedBox(width: 24),
            _stat('轮数', '${widget.rounds}', AppColors.teal),
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
      )),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
    ]);
  }
}

/// 时间轴和弦事件
class _ChordEvent {
  final double timeSec;
  final double durationSec;
  final String name;
  final List<int>? frets;
  final String? lyric;
  _ChordEvent({required this.timeSec, required this.durationSec, required this.name, this.frets, this.lyric});
}

/// 判定结果
enum _Result { pending, correct, skip }
