/// 我的页：等级/经验 + 数据看板 + 打卡 + 成就墙入口 + 会员入口
///
/// Phase 2：接入 gameProvider 真实数据（等级/经验/统计/打卡）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game/game_service.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';
import 'achievement_page.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final level = game.level;
    final unlockedAch = game.achievements.values.where((a) => a.unlocked).length;
    final totalAch = game.achievements.length;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 渐变头部（头像+等级+经验条）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 70),
              decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white24,
                    child: Text('🧑', style: TextStyle(fontSize: 36)),
                  ),
                  const SizedBox(height: 8),
                  const Text('尤克里里爱好者',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  // 等级头衔
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '⭐ Lv.${level.level} ${level.title} · ${level.totalExp}/${level.nextLevelExp} EXP',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 经验条
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: level.levelProgress / 100.0,
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
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
                    _stat('${game.practiceHours}', '练习小时'),
                    const SizedBox(width: 10),
                    _stat('${game.songsCompleted}', '弹过曲目'),
                    const SizedBox(width: 10),
                    _stat('${game.chordsMastered}', '掌握和弦'),
                  ],
                ),
              ),
            ),
            // 打卡卡片
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CheckinCard(game: game, ref: ref),
            ),
            const SizedBox(height: 16),
            // 成就墙入口（点击跳转）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AchievementPage())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.rCard),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: const BoxDecoration(
                            gradient: AppColors.islandGradient, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Text('🏅', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('成就墙',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('已解锁 $unlockedAch / $totalAch',
                                style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                          ],
                        ),
                      ),
                      const Text('›', style: TextStyle(color: AppColors.text3, fontSize: 20)),
                    ],
                  ),
                ),
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
                    BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Text('👑'),
                      title: const Text('会员中心', style: TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Text('开通永久会员 ›',
                          style: TextStyle(
                              color: AppColors.orangeDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      onTap: () => showPaywall(context, reason: '开通永久会员，解锁尤克里里全部内容'),
                    ),
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      leading: const Text('⚙️'),
                      title: const Text('设置'),
                      trailing: Text('乐器/音频校准 ›',
                          style: TextStyle(color: AppColors.text3, fontSize: 13)),
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => Container(
                            padding: const EdgeInsets.all(24),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('⚙️ 设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                SizedBox(height: 16),
                                Text('乐器类型：尤克里里（High-G）', style: TextStyle(fontSize: 14)),
                                SizedBox(height: 8),
                                Text('采样率：自动检测（Web 48000Hz）', style: TextStyle(fontSize: 14)),
                                SizedBox(height: 8),
                                Text('更多设置选项将在后续版本开放', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      leading: const Text('💬'),
                      title: const Text('帮助与反馈'),
                      trailing: Text('›', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => Container(
                            padding: const EdgeInsets.all(24),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('💬 帮助与反馈', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                SizedBox(height: 16),
                                Text('常见问题：', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                SizedBox(height: 8),
                                Text('• 调音器没反应？请检查麦克风权限', style: TextStyle(fontSize: 13)),
                                Text('• 识别不准？建议在安静环境使用', style: TextStyle(fontSize: 13)),
                                Text('• 配乐干扰？建议佩戴耳机', style: TextStyle(fontSize: 13)),
                                SizedBox(height: 16),
                                Text('反馈邮箱：support@ukulele-app.com', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        );
                      },
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
            BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Text(n,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.orangeDark)),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 11, color: AppColors.text2)),
          ],
        ),
      ),
    );
  }
}

/// 打卡卡片（真实逻辑：每日一次，连续打卡）
class _CheckinCard extends StatelessWidget {
  final GameState game;
  final WidgetRef ref;
  const _CheckinCard({required this.game, required this.ref});

  @override
  Widget build(BuildContext context) {
    final checked = ref.read(gameProvider.notifier).isCheckedInToday;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
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
                    style: const TextStyle(color: AppColors.text1, fontSize: 16),
                    children: [
                      const TextSpan(text: '连续打卡 '),
                      TextSpan(
                          text: '${game.currentStreak}',
                          style: const TextStyle(
                              color: AppColors.orangeDark, fontWeight: FontWeight.bold)),
                      const TextSpan(text: ' 天 🔥'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('累计打卡 ${game.totalCheckinDays} 天',
                    style: const TextStyle(color: AppColors.text2, fontSize: 12)),
              ],
            ),
          ),
          // 打卡按钮
          GestureDetector(
            onTap: checked
                ? null
                : () {
                    final exp = ref.read(gameProvider.notifier).checkIn();
                    if (exp > 0 && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ 打卡成功！连续 ${game.currentStreak + 1} 天，获得 $exp EXP'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                gradient: checked ? null : AppColors.brandGradient,
                color: checked ? const Color(0xFFF3F4F6) : null,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                checked ? '✓ 已打卡' : '📅 打卡',
                style: TextStyle(
                  color: checked ? AppColors.text3 : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
