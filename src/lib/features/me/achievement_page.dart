/// 成就墙页面：展示全部成就的解锁进度与详情
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game/game_service.dart';
import '../../core/theme/app_theme.dart';

class AchievementPage extends ConsumerWidget {
  const AchievementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final achievements = AchievementType.values
        .map((t) => game.achievements[t]!)
        .toList(growable: false);
    final unlockedCount = achievements.where((a) => a.unlocked).length;
    final totalCount = achievements.length;
    final overallRatio =
        totalCount == 0 ? 0.0 : unlockedCount / totalCount;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(unlockedCount, totalCount, overallRatio)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _AchievementCard(
                  status: achievements[index],
                  onTap: () => _showDetailSheet(context, achievements[index]),
                ),
                childCount: achievements.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int unlocked, int total, double ratio) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 28),
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              BackButton(color: Colors.white),
              SizedBox(width: 4),
              Text('🏅 成就墙',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已解锁 $unlocked / $total',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, AchievementStatus status) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(status: status),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.status, required this.onTap});
  final AchievementStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = status.unlocked;
    return AnimatedScale(
      scale: unlocked ? 1.0 : 0.96,
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.rCard),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                Stack(children: [
                  _Badge(unlocked: unlocked, emoji: status.type.emoji),
                  if (!unlocked)
                    const Positioned(
                        top: 0, right: 0,
                        child: Text('🔒', style: TextStyle(fontSize: 14))),
                ]),
                const SizedBox(height: 8),
                Text(status.type.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: unlocked ? AppColors.text1 : AppColors.text3)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(status.type.desc,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: unlocked ? AppColors.text2 : AppColors.text3)),
                ),
                const SizedBox(height: 8),
                unlocked ? const _UnlockedChip() : _ProgressBar(status: status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.unlocked, required this.emoji});
  final bool unlocked;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unlocked ? AppColors.islandGradient : null,
        color: unlocked ? null : const Color(0xFFE5E7EB),
        boxShadow: unlocked
            ? const [BoxShadow(color: Color(0x33FF8A3D), blurRadius: 12, offset: Offset(0, 3))]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(emoji,
          style: TextStyle(fontSize: 28, color: unlocked ? Colors.white : AppColors.text3)),
    );
  }
}

class _UnlockedChip extends StatelessWidget {
  const _UnlockedChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ok.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.rBtn),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✓', style: TextStyle(fontSize: 12, color: AppColors.ok, fontWeight: FontWeight.bold)),
          SizedBox(width: 2),
          Text('已解锁', style: TextStyle(fontSize: 11, color: AppColors.ok, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.status});
  final AchievementStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('${status.progress}/${status.type.target}',
              style: const TextStyle(fontSize: 11, color: AppColors.text3)),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: status.progressRatio,
            minHeight: 5,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
          ),
        ),
      ],
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.status});
  final AchievementStatus status;

  @override
  Widget build(BuildContext context) {
    final unlocked = status.unlocked;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: unlocked ? AppColors.islandGradient : null,
              color: unlocked ? null : const Color(0xFFE5E7EB),
              boxShadow: unlocked
                  ? const [BoxShadow(color: Color(0x44FF8A3D), blurRadius: 20, offset: Offset(0, 6))]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(status.type.emoji,
                style: TextStyle(fontSize: 48, color: unlocked ? Colors.white : AppColors.text3)),
          ),
          const SizedBox(height: 16),
          Text(status.type.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text1)),
          const SizedBox(height: 8),
          Text(status.type.desc,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.text2)),
          const SizedBox(height: 20),
          if (unlocked)
            const _UnlockedChip()
          else
            Text('进度 ${status.progress} / ${status.type.target}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.orangeDark)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rBtn)),
              ),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }
}
