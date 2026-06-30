/// 跟弹评分模型 + 评分引擎
///
/// 对应 PRD §3.2.2 / TDD §3.6。
/// 给定一段应弹音符序列（含时长），实时接收音高事件，
/// 判定每个音符是否弹对（音准），输出 ✓/✗ 反馈与最终评分。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_utils.dart';
import '../audio/pitch_service.dart';
import 'chord_recognizer.dart';

/// 应弹的一个音符
@immutable
class TargetNote {
  final String name; // 音名，如 "C"
  final int octave; // 八度，如 4
  final Duration start; // 在序列中的起始时间
  final Duration duration; // 持续时长
  final bool isChord; // 是否为和弦（和弦模式走 Chroma 识别，单音走 NCCF）

  const TargetNote({
    required this.name,
    required this.octave,
    required this.start,
    required this.duration,
    this.isChord = false,
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
  int _currentNoteIndex = 0;
  DateTime? _lastAdvanceTime; // 上次推进时间，用于冷却期防误触

  /// 和弦识别器（和弦模式用 Chroma 识别整和弦，而非单音匹配）
  ChordRecognizer? _chordRecognizer;

  ScoringEngine(this._pitchService) : super(const ScoringState());

  /// 开始跟弹评分
  ///
  /// [notes] 为按时间排列的应弹音符序列。
  Future<void> start(List<TargetNote> notes) async {
    _notes = notes;
    _currentNoteIndex = 0;
    _lastAdvanceTime = null;
    state = ScoringState(isRunning: true, currentIndex: 0, judgements: []);

    _sub = _pitchService.pitchStream.listen(_onPitch);

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
      stop();
      return;
    }
    final target = _notes[_currentNoteIndex];
    final isChord = target.isChord;

    // 单音模式用 frequency 匹配，和弦模式用 samples(Chroma) 匹配。
    // 能量门限 0.02：过滤电扇等环境噪声（电扇 RMS < 0.01，拨弦 > 0.03）。
    // 之前 0.0005 太低，电扇噪声也触发匹配导致一下子跳完。
    final bool hasInput = isChord
        ? (r.samples != null && r.samples!.isNotEmpty && r.energy > 0.02)
        : (r.frequency != null && r.energy > 0.02);
    if (hasInput) {
      final matched = isChord
          ? _matchChord(target, r)
          : _matchSingleNote(target, r);

      // 匹配即推进：弹响且音名对就跳下一音。
      // 冷却期：推进后 300ms 内不响应新匹配，避免余音/快速连弹误触。
      if (matched &&
          (_lastAdvanceTime == null ||
              DateTime.now().difference(_lastAdvanceTime!) >
                  const Duration(milliseconds: 300))) {
        _lastAdvanceTime = DateTime.now();
        final judge = NoteJudgement(
          target: target,
          correct: true,
          centsError: 0,
        );
        _advance(judge);
        return;
      }
    }

    // 实时显示当前 cents 偏差（仅单音模式）
    if (!isChord && r.frequency != null) {
      final info = frequencyToNote(r.frequency!);
      state = ScoringState(
        isRunning: true,
        currentIndex: _currentNoteIndex,
        judgements: state.judgements,
        lastPitchCents: info.cents,
      );
    }

    // 设计：不超时跳走！等你弹对才前进（新手友好）。
    // 不弹 → 一直停在这个音等你；弹错 → 显示偏差但不跳，继续等你弹对。
  }

  /// 和弦模式匹配：用 Chroma 识别整和弦。
  /// 匹配条件：识别结果 == 目标和弦，或目标和弦是最佳匹配且分数足够高。
  bool _matchChord(TargetNote target, PitchResult r) {
    _chordRecognizer ??= ChordRecognizer(_pitchService.actualSampleRate);
    final result = _chordRecognizer!.recognizeDetailed(
      r.samples!.toList(),
      sampleRate: _pitchService.actualSampleRate,
    );
    // 完全匹配，或目标是最佳匹配且分数 > 0.6（放宽，Chroma 对扫弦有抖动）
    return result.chord == target.name ||
        (result.bestMatch == target.name && result.score > 0.6);
  }

  /// 单音模式匹配：频率落在目标音名（任意八度）的 ±2 半音内即匹配。
  /// NCCF 对真实弱信号/短促信号不稳定，可能输出 C/C#/D 等相邻音名。
  /// 用半音距离判定（而非精确音名相等），容忍 ±2 半音抖动。
  bool _matchSingleNote(TargetNote target, PitchResult r) {
    if (r.frequency == null || r.frequency! < 100 || r.frequency! > 2000) {
      return false;
    }
    final info = frequencyToNote(r.frequency!);
    // 精确音名匹配（忽略八度）。
    // 之前用 ±2 半音太宽：C 弦余音(269Hz) 能匹配到相邻的 D(293Hz, 距 1.5 半音)，
    // 导致弹一个音后余音把后续音全"匹配"了。改为精确音名相等。
    // （八度由 frequencyToNote 的 midi 计算自动归类，269=C4，538=C5，音名都是 C）
    return info.name == target.name;
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
