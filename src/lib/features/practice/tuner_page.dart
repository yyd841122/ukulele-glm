/// 调音器页面（MVP 核心 · 音频引擎 PoC）
///
/// 用 PitchDetectionService 实时识别尤克里里音高，可视化反馈：
/// - 指针表盘显示 cents 偏差
/// - 音名 + 频率显示
/// - 4 弦引导（G-C-E-A），调准自动标记
/// - High-G / Low-G 切换
///
/// 这个页面同时是 M1 PoC 的验收载体：验证识别精度与延迟。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/music_utils.dart';
import '../../core/audio/pitch_service.dart';
import '../../core/theme/app_theme.dart';

/// 当前选中的弦 index provider
final selectedStringProvider = StateProvider<int>((ref) => 0);

/// Low-G 模式 provider
final lowGProvider = StateProvider<bool>((ref) => false);

/// 调音器页面状态（识别结果 + 是否调准）
class TunerState {
  final NoteInfo? note; // 当前识别到的音
  final double? frequency;
  final bool isRunning;
  final Set<String> tunedStrings; // 已调准的弦（音名+八度）

  const TunerState({
    this.note,
    this.frequency,
    this.isRunning = false,
    this.tunedStrings = const {},
  });

  TunerState copyWith({
    NoteInfo? note,
    double? frequency,
    bool? isRunning,
    Set<String>? tunedStrings,
    bool clearNote = false,
  }) {
    return TunerState(
      note: clearNote ? null : (note ?? this.note),
      frequency: clearNote ? null : (frequency ?? this.frequency),
      isRunning: isRunning ?? this.isRunning,
      tunedStrings: tunedStrings ?? this.tunedStrings,
    );
  }
}

class TunerNotifier extends StateNotifier<TunerState> {
  final PitchDetectionService _pitchService;
  final Ref _ref;
  StreamSubscription? _sub;

  TunerNotifier(this._pitchService, this._ref) : super(const TunerState());

  List<UkuleleString> get _tuning =>
      _ref.read(lowGProvider) ? kLowGTuning : kHighGTuning;

  Future<void> toggle() async {
    if (state.isRunning) {
      await stop();
    } else {
      await start();
    }
  }

  Future<void> start() async {
    state = state.copyWith(isRunning: true);
    try {
      await _pitchService.start();
      _sub = _pitchService.pitchStream.listen(_onPitch);
    } catch (e) {
      state = state.copyWith(isRunning: false);
      rethrow;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _pitchService.stop();
    state = TunerState(
      isRunning: false,
      tunedStrings: state.tunedStrings,
    );
  }

  void _onPitch(PitchResult r) {
    if (r.frequency == null || r.frequency! <= 0) {
      // 未检测到（太安静）
      state = state.copyWith(clearNote: true, tunedStrings: state.tunedStrings);
      return;
    }

    final info = frequencyToNote(r.frequency!);
    final tuned = Set<String>.from(state.tunedStrings);

    // 判断是否对应当前选中弦且调准
    final cur = _tuning[_ref.read(selectedStringProvider)];
    if (info.name == cur.name &&
        info.octave == cur.octave &&
        info.isInTune(threshold: 5)) {
      tuned.add(cur.fullName);
    }

    state = TunerState(
      note: info,
      frequency: r.frequency,
      isRunning: true,
      tunedStrings: tuned,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final tunerProvider =
    StateNotifierProvider<TunerNotifier, TunerState>((ref) {
  return TunerNotifier(ref.read(pitchServiceProvider), ref);
});

// ────────────────────────────────────────────────────────────
//  UI
// ────────────────────────────────────────────────────────────

class TunerPage extends ConsumerWidget {
  const TunerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tunerProvider);
    final tuning = ref.watch(lowGProvider) ? kLowGTuning : kHighGTuning;
    final selectedIdx = ref.watch(selectedStringProvider);
    final lowG = ref.watch(lowGProvider);

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
                  const BackButton(color: Colors.white),
                  const Spacer(),
                  const Text('🎼 智能调音器',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => ref.read(lowGProvider.notifier).state =
                        !lowG,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        lowG ? 'Low-G' : 'High-G',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 表盘（带诊断信息：真机调试用）
            _Dial(
              state: state,
              diagText: state.isRunning
                  ? '采集包:${ref.read(pitchServiceProvider).audioPackets} 识别:${ref.read(pitchServiceProvider).detectCalls}'
                  : null,
            ),

            // 4 弦
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(tuning.length, (i) {
                  final s = tuning[i];
                  final selected = i == selectedIdx;
                  final tuned = state.tunedStrings.contains(s.fullName);
                  return GestureDetector(
                    onTap: () =>
                        ref.read(selectedStringProvider.notifier).state = i,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? AppColors.orange.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.08),
                              border: Border.all(
                                color: tuned
                                    ? AppColors.ok
                                    : (selected
                                        ? AppColors.orange
                                        : Colors.transparent),
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              s.name,
                              style: TextStyle(
                                color: tuned
                                    ? AppColors.ok
                                    : Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(s.label,
                              style: const TextStyle(
                                  color: AppColors.text3, fontSize: 10)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: Text(
                '📋 标准调音：G4 - C4 - E4 - A4\n依次弹响单弦，指针居中即调准',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text3, fontSize: 12, height: 1.7),
              ),
            ),

            const Spacer(),

            // 开始/停止按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await ref.read(tunerProvider.notifier).toggle();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: state.isRunning
                            ? AppColors.err
                            : AppColors.orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      child: Text(
                        state.isRunning ? '⏹ 停止调音' : '🎤 开始调音',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '点击后允许使用麦克风 · 用 YIN 算法实时识别音高',
                    style: TextStyle(color: AppColors.text3, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 调音表盘
class _Dial extends StatelessWidget {
  final TunerState state;
  final String? diagText; // 诊断信息（真机调试：采集包数/识别次数）
  const _Dial({required this.state, this.diagText});

  @override
  Widget build(BuildContext context) {
    final note = state.note;
    final cents = note?.cents ?? 0;
    final inTune = note != null && note.isInTune(threshold: 5);
    // -50..+50 → -60..+60 度
    final angle = (cents * 1.2).clamp(-60.0, 60.0) * math.pi / 180;

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 弧形刻度
          CustomPaint(
            size: const Size(260, 260),
            painter: _DialPainter(),
          ),
          // 指针
          AnimatedRotation(
            turns: angle / (2 * math.pi),
            duration: const Duration(milliseconds: 100),
            child: Align(
              alignment: const Alignment(0, -0.42),
              child: Container(
                width: 4,
                height: 110,
                decoration: BoxDecoration(
                  color: inTune ? AppColors.ok : AppColors.err,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          // 中央音名
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note?.name ?? '—',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note != null ? '${note.octave}' : '',
                style: const TextStyle(color: AppColors.text3, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                state.frequency != null
                    ? '${state.frequency!.toStringAsFixed(1)} Hz'
                    : (state.isRunning ? '请弹响琴弦…' : '未开始'),
                style: const TextStyle(color: AppColors.text3, fontSize: 12),
              ),
              // 诊断信息（真机调试用）
              if (diagText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(diagText!,
                      style:
                          TextStyle(color: AppColors.text3.withValues(alpha: 0.5), fontSize: 9)),
                ),
              const SizedBox(height: 8),
              if (note != null)
                Text(
                  inTune
                      ? '✓ 调准了！'
                      : (cents < 0 ? '偏低 ↑ 拧紧' : '偏高 ↓ 拧松'),
                  style: TextStyle(
                    color: inTune
                        ? AppColors.ok
                        : (cents < 0 ? const Color(0xFF60A5FA) : const Color(0xFFF87171)),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${cents > 0 ? '+' : ''}$cents cents',
                    style: const TextStyle(color: AppColors.text3, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 20);
    final radius = size.width / 2 - 30;

    // 背景弧
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.85,
      math.pi * 1.3,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round,
    );

    // 左侧（偏低）蓝色
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.85,
      math.pi * 0.5,
      false,
      Paint()
        ..color = const Color(0xFF60A5FA).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round,
    );

    // 右侧（偏高）红色
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.35,
      math.pi * 0.5,
      false,
      Paint()
        ..color = const Color(0xFFF87171).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round,
    );

    // 中央绿色达标区
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.45,
      math.pi * 0.1,
      false,
      Paint()
        ..color = AppColors.ok
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
