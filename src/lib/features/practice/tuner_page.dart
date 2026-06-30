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
  final int hitCount; // 诊断：当前弦命中帧数
  final bool isCurrentTuned; // 诊断：当前弦是否判准
  final double? rawFreq; // 诊断：原始识别频率（校正前）
  final int sampleRate; // 诊断：实际采样率
  final String freqHistory; // 诊断：最近频率历史（看跳变）

  const TunerState({
    this.note,
    this.frequency,
    this.isRunning = false,
    this.tunedStrings = const {},
    this.hitCount = 0,
    this.isCurrentTuned = false,
    this.rawFreq,
    this.sampleRate = 44100,
    this.freqHistory = '',
  });

  TunerState copyWith({
    NoteInfo? note,
    double? frequency,
    bool? isRunning,
    Set<String>? tunedStrings,
    bool clearNote = false,
    int? hitCount,
    bool? isCurrentTuned,
    double? rawFreq,
    int? sampleRate,
    String? freqHistory,
  }) {
    return TunerState(
      note: clearNote ? null : (note ?? this.note),
      frequency: clearNote ? null : (frequency ?? this.frequency),
      isRunning: isRunning ?? this.isRunning,
      tunedStrings: tunedStrings ?? this.tunedStrings,
      hitCount: hitCount ?? this.hitCount,
      isCurrentTuned: isCurrentTuned ?? this.isCurrentTuned,
      rawFreq: rawFreq ?? this.rawFreq,
      sampleRate: sampleRate ?? this.sampleRate,
      freqHistory: freqHistory ?? this.freqHistory,
    );
  }
}

class TunerNotifier extends StateNotifier<TunerState> {
  final PitchDetectionService _pitchService;
  final Ref _ref;
  StreamSubscription? _sub;
  final List<bool> _hitWindow = []; // 滑动窗口：最近几帧是否命中（容忍抖动）
  bool _autoSwitched = false; // 当前弦是否已自动切换过（防重复）
  final List<String> _freqLog = []; // 诊断：最近频率日志

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
    // 重新开始调音：清空已调准标记 + 命中窗口 + 回到第1根弦(G)
    state = TunerState(isRunning: true, tunedStrings: {});
    _ref.read(selectedStringProvider.notifier).state = 0; // 回到 G 弦
    try {
      _hitWindow.clear();
      _autoSwitched = false;
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
    // 停止时清空已调准标记，确保下次进入是干净状态
    state = const TunerState(isRunning: false, tunedStrings: {});
  }

  void _onPitch(PitchResult r) {
    // 噪声门限：双重过滤电扇等环境噪声。
    //   - energy > 0.015（电扇 RMS < 0.01，拨弦 > 0.03）
    //   - confidence > 0.3（NCCF 真实信号 confidence 波动大，0.3 已能滤掉纯噪声）
    // 之前用 0.5 太严，E 弦（细弦信号弱）部分帧被过滤，导致凑不够命中窗口不跳弦。
    if (r.frequency == null ||
        r.frequency! <= 0 ||
        r.energy <= 0.015 ||
        (r.probability ?? 0) <= 0.3) {
      state = state.copyWith(clearNote: true, tunedStrings: state.tunedStrings);
      return;
    }

    final tuned = Set<String>.from(state.tunedStrings);

    final curIdx = _ref.read(selectedStringProvider);
    final cur = _tuning[curIdx];
    final targetFreq = cur.frequency;
    final rawFreq = r.frequency!;

    // 诊断：记录最近 6 帧的原始频率（校正前），用于看频率跳变模式
    _freqLog.add(rawFreq.toStringAsFixed(0));
    if (_freqLog.length > 6) _freqLog.removeAt(0);

    // 八度校正：NCCF 可能识别成高/低八度。
    // 策略：如果识别频率和目标频率比值接近 2 或 0.5（八度），
    // 且校正后的音名匹配目标，则用校正频率。
    var effectiveFreq = rawFreq;
    final ratio = rawFreq / targetFreq;
    if (ratio > 1.8 && ratio < 2.2) {
      // 可能是高八度（识别频率是目标的~2倍）→ 除2校正
      effectiveFreq = rawFreq / 2;
    } else if (ratio > 0.45 && ratio < 0.55) {
      // 可能是低八度（识别频率是目标的~0.5倍）→ 乘2校正
      effectiveFreq = rawFreq * 2;
    } else if (ratio > 3.8 && ratio < 4.2) {
      // 两个八度差
      effectiveFreq = rawFreq / 4;
    } else if (ratio > 0.23 && ratio < 0.27) {
      effectiveFreq = rawFreq * 4;
    }

    final effectiveInfo = frequencyToNote(effectiveFreq);
    final freqDiff = (effectiveFreq - targetFreq).abs() / targetFreq;
    final isCurrentInTune = freqDiff <= 0.03;

    // 滑动窗口：记录最近 3 帧的命中情况
    // 弹响且调准后连续 2 帧即跳弦（快速响应，又防偶发误触）
    _hitWindow.add(isCurrentInTune);
    if (_hitWindow.length > 3) _hitWindow.removeAt(0);
    final hitCount = _hitWindow.where((h) => h).length;

    if (isCurrentInTune) {
      tuned.add(cur.fullName);
    }

    state = TunerState(
      note: effectiveInfo,
      frequency: effectiveFreq,
      isRunning: true,
      tunedStrings: tuned,
      hitCount: hitCount,
      isCurrentTuned: isCurrentInTune,
      rawFreq: rawFreq,
      sampleRate: _pitchService.actualSampleRate,
      freqHistory: _freqLog.join(','),
    );

    // 自动切换：连续 2 帧调准即跳（弹响就跳，快速流畅）
    if (hitCount >= 2 && !_autoSwitched) {
      _autoSwitched = true; // 防重复
      final currentTuning = _ref.read(lowGProvider) ? kLowGTuning : kHighGTuning;
      final nextIdx = _findNextUntunedString(curIdx, tuned, currentTuning);
      if (nextIdx != null && nextIdx != curIdx) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (state.isRunning) {
            _ref.read(selectedStringProvider.notifier).state = nextIdx;
            // 重置窗口，准备下一根弦
            _hitWindow.clear();
            _autoSwitched = false;
          }
        });
      }
    }
  }

  /// 找下一根未调准的弦（从当前弦之后顺序找）
  int? _findNextUntunedString(int fromIdx, Set<String> tuned, List<UkuleleString> tuning) {
    for (var offset = 1; offset <= tuning.length; offset++) {
      final idx = (fromIdx + offset) % tuning.length;
      if (!tuned.contains(tuning[idx].fullName)) {
        return idx;
      }
    }
    return null;
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

class TunerPage extends ConsumerStatefulWidget {
  const TunerPage({super.key});

  @override
  ConsumerState<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends ConsumerState<TunerPage> {
  @override
  void initState() {
    super.initState();
    // 进入页面时重置调音器状态：清空已调准标记、回到 G 弦、停止运行
    // 避免上次调音的残留状态影响本次（退出再进入会复现上次结果）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(tunerProvider.notifier);
      if (ref.read(tunerProvider).isRunning) {
        notifier.stop();
      }
      ref.read(selectedStringProvider.notifier).state = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
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

            // 表盘
            _Dial(state: state),

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
                '📋 标准调音：G4 - C4 - E4 - A4\n依次弹响单弦，调准后自动跳下一弦',
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
                    '点击后允许使用麦克风 · 用 MPM 算法实时识别音高',
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
  const _Dial({required this.state});

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
              // 诊断信息（真机调试用，放大便于读取采样率）
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
