/// 首页：打卡 + 快捷工具 + 推荐曲目
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../practice/tuner_page.dart';
import '../songs/song_model.dart';
import '../songs/song_detail_page.dart';

/// 模拟连续打卡天数（MVP 本地，Phase2 接打卡 provider）
final _streakProvider = StateProvider<int>((ref) => 7);
final _todayMinutesProvider = StateProvider<int>((ref) => 12);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(_streakProvider);
    final minutes = ref.watch(_todayMinutesProvider);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 渐变头部
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 26),
              decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('☀️ 早上好',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(height: 2),
                  Text('练琴时间到啦 🎸',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('今天也要开心弹琴哦～',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            // 打卡卡片
            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  color: AppColors.text1, fontSize: 16),
                              children: [
                                const TextSpan(
                                    text: '连续打卡 '),
                                TextSpan(
                                    text: '$streak',
                                    style: const TextStyle(
                                        color: AppColors.orangeDark,
                                        fontWeight: FontWeight.bold)),
                                const TextSpan(text: ' 天 🔥'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('今日已练 $minutes 分钟 · 目标 15 分钟',
                              style: const TextStyle(
                                  color: AppColors.text2, fontSize: 12)),
                        ],
                      ),
                    ),
                    // 周打卡
                    Row(
                      children: List.generate(7, (i) {
                        final done = i < 6;
                        final now = i == 6;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: done
                                ? const LinearGradient(colors: [
                                    AppColors.orange,
                                    AppColors.orangeDark
                                  ])
                                : null,
                            color: now ? AppColors.warn : const Color(0xFFF3F4F6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            ['一', '二', '三', '四', '五', '六', '日'][i],
                            style: TextStyle(
                              color: (done || now) ? Colors.white : AppColors.text3,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            // 快捷工具
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _quickTool(context, '🎼', '调音器', () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TunerPage()))),
                  _quickTool(context, '🎯', '练一练', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音准练习见「曲谱→任一入门曲目→跟弹评分」')))),
                  _quickTool(context, '📚', '曲谱库', () {}),
                  _quickTool(context, '🎵', '和弦', () {}),
                ],
              ),
            ),
            // 推荐曲目
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text('🔥 热门弹唱',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: kSongs.where((s) => !s.isMemberOnly).take(5).map((s) =>
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => SongDetailPage(song: s))),
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 100,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [s.color, s.colorLight]),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.bottomRight,
                              padding: const EdgeInsets.all(8),
                              child: Text(s.emoji, style: const TextStyle(fontSize: 28)),
                            ),
                            const SizedBox(height: 6),
                            Text(s.title,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(s.artist,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.text2)),
                          ],
                        ),
                      ),
                    )).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _quickTool(BuildContext context, String emoji, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 8,
                  offset: Offset(0, 1)),
            ],
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: AppColors.text2)),
            ],
          ),
        ),
      ),
    );
  }
}
