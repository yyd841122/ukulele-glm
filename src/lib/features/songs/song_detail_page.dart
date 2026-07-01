/// 曲谱详情 + 滚动播放器
///
/// - 渐变头部：歌曲信息（标题/歌手/Key/BPM/难度）
/// - 控制条：变速(🐢/正常/🐇) + 播放/暂停 + 变调 + AB循环（占位）
/// - 歌词区：带和弦标注的歌词，播放时逐行高亮 + 自动滚动
/// - 底部：跟弹评分按钮（M6 接入音频引擎）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/feature_gate.dart';
import '../../core/monetization/monetization_model.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../practice/follow_score_page.dart';
import 'song_model.dart';

class SongDetailPage extends ConsumerStatefulWidget {
  final Song song;
  const SongDetailPage({super.key, required this.song});

  @override
  ConsumerState<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends ConsumerState<SongDetailPage> {
  final _scrollController = ScrollController();
  bool _playing = false;
  int _currentLine = 0;
  double _speed = 1.0; // 0.8 / 1.0 / 1.2
  Timer? _timer;

  List<SongLine> get _lines => lyricsFor(widget.song);

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
    } else {
      setState(() => _playing = true);
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    if (!_playing) return;
    // 每行停留时间受 BPM 与倍速影响
    final interval = Duration(
        milliseconds: (2400 / _speed).round());
    _timer = Timer(interval, () {
      if (!mounted) return;
      setState(() {
        _currentLine = (_currentLine + 1) % _lines.length;
      });
      _scrollToCurrent();
      _scheduleNext();
    });
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final target = (_currentLine * 56.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    if (_playing) {
      _timer?.cancel();
      _scheduleNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.song;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 渐变头部
          Container(
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 20),
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text('‹',
                      style: TextStyle(color: Colors.white, fontSize: 28)),
                ),
                const SizedBox(height: 8),
                Text(s.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${s.artist} · 弹唱版',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _metaTag('Key: ${s.keyName}'),
                    _metaTag('BPM: ${s.bpm}'),
                    _metaTag('⭐' * s.difficulty.stars),
                    _metaTag('4/4'),
                  ],
                ),
              ],
            ),
          ),
          // 控制条
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(AppTheme.rCard),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ctrlBtn(
                  label: _speed == 0.8
                      ? '🐢0.8x'
                      : (_speed == 1.2 ? '正常' : '🐢'),
                  onTap: () => _setSpeed(_speed == 0.8 ? 1.0 : 0.8),
                ),
                _ctrlBtn(
                  icon: _playing ? '⏸' : '▶',
                  size: 40,
                  big: true,
                  onTap: _togglePlay,
                ),
                _ctrlBtn(
                  label: _speed == 1.2 ? '🐇1.2x' : '🐇',
                  onTap: () => _setSpeed(_speed == 1.2 ? 1.0 : 1.2),
                ),
                // AB 循环暂未实现，用收藏替代
                _ctrlBtn(
                  label: '⭐',
                  onTap: () => _tip('已收藏（功能完善中）'),
                ),
              ],
            ),
          ),
          // 歌词区
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _lines.length,
              itemExtent: 56,
              itemBuilder: (_, i) {
                final line = _lines[i];
                final now = i == _currentLine && _playing;
                return _LyricLine(line: line, highlight: now);
              },
            ),
          ),
          // 底部练习按钮区
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: AppColors.line.withValues(alpha: 0.6))),
            ),
            child: Column(
              children: [
                const Text(
                  '🟡 免费用户每日可评分 3 次 · 今日剩 0 次',
                  style: TextStyle(fontSize: 11, color: AppColors.text3),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // 整曲弹唱（横屏）
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            // 从曲谱库标题匹配练习歌曲
                            final practiceSong = kSongsForPractice(widget.song.title);
                            if (practiceSong != null) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PracticeSongPicker(song: practiceSong),
                              ));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('这首歌曲暂不支持整曲弹唱，敬请期待')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: const Text('🎵 整曲弹唱',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 跟弹评分
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final result = ref
                                .read(featureGateProvider)
                                .check(FeatureKey.followScore);
                            if (result is Locked) {
                              await showPaywall(context,
                                  feature: result.feature, reason: result.reason);
                              return;
                            }
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const FollowScorePage()));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                          ),
                          child: const Text('🎤 跟弹评分',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _ctrlBtn({
    String? icon,
    String? label,
    double size = 24,
    bool big = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon ?? label ?? '',
              style: TextStyle(
                fontSize: size,
                color: big ? AppColors.orange : AppColors.text1,
              )),
          if (big) const SizedBox(height: 2),
        ],
      ),
    );
  }

  void _tip(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

/// 一行带和弦标注的歌词
class _LyricLine extends StatelessWidget {
  final SongLine line;
  final bool highlight;
  const _LyricLine({required this.line, required this.highlight});

  @override
  Widget build(BuildContext context) {
    // 用 Stack 在歌词上方叠加和弦标签
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.only(left: highlight ? 8 : 0, top: 14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.orange.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // 歌词文本
          Text(
            line.lyrics,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: highlight ? AppColors.orangeDark : AppColors.text1,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          // 和弦标签（按 pos 估算水平位置）
          ...line.chords.map((c) => Positioned(
                left: c.pos * 16.0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(c.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              )),
        ],
      ),
    );
  }
}
