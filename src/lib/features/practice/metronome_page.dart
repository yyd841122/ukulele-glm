/// 节拍器页面：可调 BPM + 拍号 + 重音 + 视觉/声音反馈
///
/// - BPM 40-240，Slider + 加减按钮，大数字显示
/// - 拍号 2/4、3/4、4/4、6/8
/// - 重音开关：每小节第一拍高亮
/// - 当前拍位橙色变大圆点
/// - 节拍驱动：Timer.periodic(60000 ~/ bpm)，每 tick 播 SystemSound.click
///
/// 注意：SystemSound 在 web 上无声，以视觉闪烁为主要反馈。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/tick_player.dart' as tick;
import '../../core/theme/app_theme.dart';

/// 节拍器状态
class MetronomeState {
  final int bpm; // 40-240
  final int beatsPerBar; // 每小节拍数（2/3/4/6）
  final bool accentOn; // 是否开启重音
  final bool isPlaying;
  final int currentBeat; // 当前拍 index（0 起），-1 表示未运行

  const MetronomeState({
    this.bpm = 90,
    this.beatsPerBar = 4,
    this.accentOn = true,
    this.isPlaying = false,
    this.currentBeat = -1,
  });

  MetronomeState copyWith({
    int? bpm,
    int? beatsPerBar,
    bool? accentOn,
    bool? isPlaying,
    int? currentBeat,
  }) {
    return MetronomeState(
      bpm: bpm ?? this.bpm,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      accentOn: accentOn ?? this.accentOn,
      isPlaying: isPlaying ?? this.isPlaying,
      currentBeat: currentBeat ?? this.currentBeat,
    );
  }
}

class MetronomeNotifier extends StateNotifier<MetronomeState> {
  Timer? _timer;

  MetronomeNotifier() : super(const MetronomeState());

  /// 设置 BPM（限定 40-240）
  void setBpm(int v) {
    final clamped = v.clamp(40, 240);
    state = state.copyWith(bpm: clamped);
    if (state.isPlaying) {
      _restart();
    }
  }

  /// 设置拍号
  void setBeatsPerBar(int beats) {
    state = state.copyWith(beatsPerBar: beats);
    if (state.isPlaying) {
      _restart();
    }
  }

  void toggleAccent() => state = state.copyWith(accentOn: !state.accentOn);

  /// 播放/暂停切换
  void toggle() {
    if (state.isPlaying) {
      stop();
    } else {
      start();
    }
  }

  void start() {
    state = state.copyWith(isPlaying: true, currentBeat: -1);
    _restart();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(isPlaying: false, currentBeat: -1);
  }

  void _restart() {
    _timer?.cancel();
    // 第一个 tick 立即触发
    _onTick();
    final interval = Duration(milliseconds: 60000 ~/ state.bpm);
    _timer = Timer.periodic(interval, (_) => _onTick());
  }

  void _onTick() {
    final next = (state.currentBeat + 1) % state.beatsPerBar;
    // 发声：重音拍（第一拍）用更高频率区分（TickPlayer 自动按平台发声）
    final isFirstBeat = next == 0;
    tick.playTick(accent: isFirstBeat && state.accentOn);
    state = state.copyWith(currentBeat: next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final metronomeProvider =
    StateNotifierProvider<MetronomeNotifier, MetronomeState>((ref) {
  return MetronomeNotifier();
});

// ────────────────────────────────────────────────────────────
//  拍号选项
// ────────────────────────────────────────────────────────────
const List<({String label, int beats})> kTimeSignatures = [
  (label: '2/4', beats: 2),
  (label: '3/4', beats: 3),
  (label: '4/4', beats: 4),
  (label: '6/8', beats: 6),
];

// ────────────────────────────────────────────────────────────
//  UI
// ────────────────────────────────────────────────────────────
class MetronomePage extends ConsumerWidget {
  const MetronomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(metronomeProvider);
    final notifier = ref.read(metronomeProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // 渐变头部
          Container(
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 28),
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: Row(
              children: [
                const BackButton(color: Colors.white),
                const SizedBox(width: 4),
                const Text('⏱️ 节拍器',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // 内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                children: [
                  // BPM 大数字 + 闪烁主圆
                  _BeatVisualizer(state: state, onTap: notifier.toggle),
                  const SizedBox(height: 24),

                  // BPM 加减 + 数字
                  _BpmControl(
                    bpm: state.bpm,
                    onDecrement: () => notifier.setBpm(state.bpm - 1),
                    onIncrement: () => notifier.setBpm(state.bpm + 1),
                  ),
                  const SizedBox(height: 16),

                  // BPM Slider
                  Slider(
                    value: state.bpm.toDouble(),
                    min: 40,
                    max: 240,
                    divisions: 200,
                    activeColor: AppColors.orange,
                    inactiveColor: AppColors.line,
                    label: '${state.bpm} BPM',
                    onChanged: (v) => notifier.setBpm(v.round()),
                  ),
                  const SizedBox(height: 20),

                  // 拍号选择
                  const _SectionTitle(text: '拍号'),
                  const SizedBox(height: 8),
                  Row(
                    children: kTimeSignatures.map((ts) {
                      final selected = state.beatsPerBar == ts.beats;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => notifier.setBeatsPerBar(ts.beats),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.orange : Colors.white,
                              borderRadius: BorderRadius.circular(AppTheme.rBtn),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x1A000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2)),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              ts.label,
                              style: TextStyle(
                                color:
                                    selected ? Colors.white : AppColors.text2,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 重音开关
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.rCard),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 12,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Text('🔊 重音（第一拍加重）',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Switch.adaptive(
                          value: state.accentOn,
                          activeThumbColor: AppColors.orange,
                          onChanged: (_) => notifier.toggleAccent(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 开始/停止按钮
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: notifier.toggle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: state.isPlaying
                            ? AppColors.err
                            : AppColors.orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      icon: Icon(
                          state.isPlaying ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        state.isPlaying ? '停止' : '开始',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 节拍视觉器：中央大圆 + 一行拍位圆点
class _BeatVisualizer extends StatelessWidget {
  final MetronomeState state;
  final VoidCallback onTap;
  const _BeatVisualizer({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAccent =
        state.isPlaying && state.currentBeat == 0 && state.accentOn;
    return Column(
      children: [
        // 中央大圆（随当前拍脉冲）
        GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: isAccent ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                gradient: AppColors.islandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.orange.withValues(alpha: 0.3),
                    blurRadius: isAccent ? 32 : 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${state.bpm}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('BPM',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 一行拍位圆点
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(state.beatsPerBar, (i) {
            final active = state.isPlaying && i == state.currentBeat;
            final isBeat1 = i == 0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: active ? 22 : 14,
              height: active ? 22 : 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? (isBeat1 && state.accentOn
                        ? AppColors.teal
                        : AppColors.orange)
                    : AppColors.line,
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// BPM 加减控件（左右按钮 + 中间数字）
class _BpmControl extends StatelessWidget {
  final int bpm;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  const _BpmControl({
    required this.bpm,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _roundBtn(icon: Icons.remove, onTap: onDecrement),
        const SizedBox(width: 24),
        SizedBox(
          width: 90,
          child: Column(
            children: [
              Text('$bpm',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text1)),
              const Text('BPM',
                  style: TextStyle(color: AppColors.text3, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 24),
        _roundBtn(icon: Icons.add, onTap: onIncrement),
      ],
    );
  }

  Widget _roundBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.orange, size: 24),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.text1)),
    );
  }
}
