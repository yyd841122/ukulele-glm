/// 跟弹评分模型 + 评分引擎
///
/// 对应 PRD §3.2.2 / TDD §3.6。
/// 给定一段应弹音符序列（含时长），实时接收音高事件，
/// 判定每个音符是否弹对（音准），输出 ✓/✗ 反馈与最终评分。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/music_utils.dart';
import '../audio/pitch_service.dart';

/// 应弹的一个音符
@immutable
class TargetNote {
  final String name; // 音名，如 "C"
  final int octave; // 八度，如 4
  final Duration start; // 在序列中的起始时间
  final Duration duration; // 持续时长

  const TargetNote({
    required this.name,
    required this.octave,
    required this.start,
    required this.duration,
  });

  double get frequency => noteToFrequency(name, octave);
  String get fullName => '$name$octave';
}

/// 单个音符的判定结果
@immutable
class NoteJudgement {
  final TargetNote target;
  final bool correct; // 是否弹对（音准在容差内）
  final int centsError; // 音准误差（绝对值）
  const NoteJudgement({
    required this.target,
    required this.correct,
    required this.centsError,
  });
}

/// 跟弹评分状态
@immutable
class ScoringState {
  final bool isRunning;
  final int currentIndex; // 当前应弹的音符 index
  final List<NoteJudgement> judgements; // 已判定的结果
  final int? lastPitchCents; // 最近一帧的 cents 偏差（用于实时指针）

  const ScoringState({
    this.isRunning = false,
    this.currentIndex = 0,
    this.judgements = const [],
    this.lastPitchCents,
  });

  /// 已弹对的数量
  int get correctCount => judgements.where((j) => j.correct).length;

  /// 音准得分（0-100）
  int get pitchScore {
    if (judgements.isEmpty) return 0;
    final sumAccuracy = judgements.fold<double>(0, (s, j) {
      // cents 误差转准确度：0 误差=100分，50 cents(半音)=0分
      final acc = (100 - (j.centsError * 2)).clamp(0, 100);
      return s + acc;
    });
    return (sumAccuracy / judgements.length).round();
  }

  /// 完成度（已判定/总数）
  double get progress =>
      judgements.isEmpty ? 0 : judgements.length / totalNotes;

  int get totalNotes => judgements.length;
}

/// 跟弹评分引擎
class ScoringEngine extends StateNotifier<ScoringState> {
  final PitchDetectionService _pitchService;
  StreamSubscription<PitchResult>? _sub;
  List<TargetNote> _notes = [];
  DateTime _startTime = DateTime.now();
  int _currentNoteIndex = 0;

  /// 音准容差（cents）：|偏差| ≤ 此值视为弹对
  static const int _toleranceCents = 25;

  ScoringEngine(this._pitchService) : super(const ScoringState());

  /// 开始跟弹评分
  ///
  /// [notes] 为按时间排列的应弹音符序列。
  Future<void> start(List<TargetNote> notes) async {
    _notes = notes;
    _currentNoteIndex = 0;
    state = ScoringState(isRunning: true, currentIndex: 0, judgements: []);

    _sub = _pitchService.pitchStream.listen(_onPitch);
    _startTime = DateTime.now();

    try {
      await _pitchService.start();
    } catch (e) {
      state = const ScoringState(isRunning: false);
      rethrow;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _pitchService.stop();
    // 评定未判定的剩余音符为"未弹"（错误）
    final remaining = <NoteJudgement>[];
    while (_currentNoteIndex < _notes.length) {
      remaining.add(NoteJudgement(
        target: _notes[_currentNoteIndex],
        correct: false,
        centsError: 50,
      ));
      _currentNoteIndex++;
    }
    if (remaining.isNotEmpty) {
      state = ScoringState(
        isRunning: false,
        judgements: [...state.judgements, ...remaining],
      );
    } else {
      state = ScoringState(
        isRunning: false,
        judgements: state.judgements,
      );
    }
  }

  void _onPitch(PitchResult r) {
    if (!state.isRunning) return;

    // 当前应弹音符
    if (_currentNoteIndex >= _notes.length) {
      // 全部判完
      stop();
      return;
    }
    final target = _notes[_currentNoteIndex];

    // 检查是否已超过当前音符的截止时间
    final elapsed = DateTime.now().difference(_startTime);
    final noteEnd = target.start + target.duration;

    if (r.hasPitch) {
      final info = frequencyToNote(r.frequency!);
      // 音名+八度匹配，或在容差内
      final nameMatch = info.name == target.name && info.octave == target.octave;
      if (nameMatch && info.cents.abs() <= _toleranceCents) {
        // 弹对！判定并前进
        final judge = NoteJudgement(
          target: target,
          correct: true,
          centsError: info.cents.abs(),
        );
        _advance(judge);
        return;
      }
      // 实时显示当前 cents 偏差（相对目标音）
      state = ScoringState(
        isRunning: true,
        currentIndex: _currentNoteIndex,
        judgements: state.judgements,
        lastPitchCents: info.cents,
      );
    }

    // 时间到，未弹对 → 判错，前进
    if (elapsed >= noteEnd) {
      final judge = NoteJudgement(
        target: target,
        correct: false,
        centsError: 50,
      );
      _advance(judge);
    }
  }

  void _advance(NoteJudgement judge) {
    final newJudgements = [...state.judgements, judge];
    _currentNoteIndex++;
    final nextIndex = _currentNoteIndex;
    if (nextIndex >= _notes.length) {
      // 全部完成
      state = ScoringState(
        isRunning: false,
        judgements: newJudgements,
      );
      stop();
    } else {
      state = ScoringState(
        isRunning: true,
        currentIndex: nextIndex,
        judgements: newJudgements,
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// 评分引擎 Provider
final scoringEngineProvider =
    StateNotifierProvider<ScoringEngine, ScoringState>((ref) {
  return ScoringEngine(ref.read(pitchServiceProvider));
});
