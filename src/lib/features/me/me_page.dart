/// 我的页：数据看板 + 打卡日历 + 成就墙 + 会员入口
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';

/// 成就数据
const List<({String emoji, String label, bool unlocked})> _kAchievements = [
  (emoji: '🔥', label: '连续7天', unlocked: true),
  (emoji: '🎵', label: '掌握10和弦', unlocked: true),
  (emoji: '🎤', label: '首弹成功', unlocked: true),
  (emoji: '🏆', label: '连续30天', unlocked: false),
  (emoji: '⭐', label: '满分曲目', unlocked: false),
  (emoji: '💎', label: 'Lv.10', unlocked: false),
  (emoji: '🎯', label: '指弹入门', unlocked: false),
];

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 渐变头部（头像+等级+经验条）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 70),
              decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              child: const Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white24,
                    child: Text('🧑', style: TextStyle(fontSize: 36)),
                  ),
                  SizedBox(height: 8),
                  Text('尤克里里爱好者',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('⭐ Lv.5 弹唱新手 · 680/1000 EXP',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            // 数据看板
            Transform.translate(
              offset: const Offset(0, -48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _stat('23', '练习小时'),
                    const SizedBox(width: 10),
                    _stat('8', '弹过曲目'),
                    const SizedBox(width: 10),
                    _stat('12', '掌握和弦'),
                  ],
                ),
              ),
            ),
            // 打卡日历
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('📅 打卡日历',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('本月已练 18 天',
                            style: TextStyle(color: AppColors.teal, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildCalendar(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 成就墙
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text('🏅 成就墙',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Spacer(),
                  Text('3/7',
                      style: TextStyle(color: AppColors.text3, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _kAchievements
                    .map((a) => Container(
                          width: 72,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: a.unlocked
                                      ? const LinearGradient(colors: [
                                          AppColors.orange,
                                          AppColors.teal
                                        ])
                                      : null,
                                  color: a.unlocked ? null : const Color(0xFFE5E7EB),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(a.emoji,
                                    style: TextStyle(
                                        fontSize: 26,
                                        color: a.unlocked
                                            ? Colors.white
                                            : AppColors.text3)),
                              ),
                              const SizedBox(height: 4),
                              Text(a.label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: a.unlocked
                                          ? AppColors.text2
                                          : AppColors.text3)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            // 菜单
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
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
                child: Column(
                  children: [
                    ListTile(
                      leading: const Text('👑'),
                      title: const Text('会员中心',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Text('开通永久会员 ›',
                          style: TextStyle(
                              color: AppColors.orangeDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      onTap: () => showPaywall(context,
                          reason: '开通永久会员，解锁尤克里里全部内容'),
                    ),
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      leading: const Text('🎯'),
                      title: const Text('学习目标'),
                      trailing: Text('每日 15min ›',
                          style: TextStyle(color: AppColors.text3, fontSize: 13)),
                      onTap: () {},
                    ),
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      leading: const Text('⚙️'),
                      title: const Text('设置'),
                      trailing: Text('乐器/音频校准 ›',
                          style: TextStyle(color: AppColors.text3, fontSize: 13)),
                      onTap: () {},
                    ),
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      leading: const Text('💬'),
                      title: const Text('帮助与反馈'),
                      trailing: Text('›',
                          style: TextStyle(color: AppColors.text3, fontSize: 13)),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _stat(String n, String l) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
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
        child: Column(
          children: [
            Text(n,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.orangeDark)),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 11, color: AppColors.text2)),
          ],
        ),
      ),
    );
  }

  /// 简单的 4 周日历（示例数据）
  Widget _buildCalendar() {
    final pattern = [
      1, 1, 1, 1, 0, 1, 1,
      1, 1, 1, 1, 1, 0, 1,
      1, 0, 1, 1, 1, 1, 1,
      1, 1, 0, 1, 1, 0, 1,
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
      ),
      itemCount: pattern.length,
      itemBuilder: (_, i) {
        final on = pattern[i] == 1;
        final today = i == pattern.length - 2;
        return Container(
          decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(colors: [AppColors.orange, AppColors.orangeDark])
                : null,
            color: on ? null : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(6),
            border: today ? Border.all(color: AppColors.orange, width: 2) : null,
          ),
        );
      },
    );
  }
}
