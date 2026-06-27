/// 练琴页：工具宫格（调音器为核心入口）
library;

import 'package:flutter/material.dart';
import 'tuner_page.dart';
import 'metronome_page.dart';
import 'chord_library_page.dart';
import '../../core/theme/app_theme.dart';

class PracticePage extends StatelessWidget {
  const PracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 渐变头部
            Container(
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 60),
              decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🎸 练琴工具',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('调好琴、找好谱、随时开练',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            // 工具宫格
            Transform.translate(
              offset: const Offset(0, -48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // 调音器（特色大卡）
                    _FeatureCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TunerPage()),
                      ),
                      gradient: AppColors.islandGradient,
                      isFeature: true,
                      icon: '🎼',
                      title: '智能调音器',
                      subtitle: '麦克风实时听音 · 精准到 ±1 音分',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ToolCard(
                            icon: '⏱️',
                            title: '节拍器',
                            subtitle: '40-240 BPM',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MetronomePage()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ToolCard(
                            icon: '🎵',
                            title: '和弦库',
                            subtitle: '指法图+听音',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ChordLibraryPage()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _ToolCard(icon: '🥁', title: '节奏练习', subtitle: '扫弦节奏型')),
                        const SizedBox(width: 12),
                        Expanded(child: _ToolCard(icon: '🔁', title: '和弦转换', subtitle: '提速训练')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final VoidCallback onTap;
  final Gradient gradient;
  final bool isFeature;
  final String icon;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.onTap,
    required this.gradient,
    required this.isFeature,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          boxShadow: const [
            BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
        child: isFeature
            ? Row(children: [
                Text(icon, style: const TextStyle(fontSize: 46)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 8),
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.text2)),
                ],
              ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      height: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(icon, style: const TextStyle(fontSize: 30)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.text2)),
            ],
          ),
        ],
      ),
    );
    return onTap == null ? card : GestureDetector(onTap: onTap, child: card);
  }
}
