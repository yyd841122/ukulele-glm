/// 统一付费墙组件（PaywallSheet）
///
/// 对应 TDD §6.5.4。全 App 单一付费墙，由 FeatureGate 返回 Locked 时触发。
/// 展示会员权益与开通入口（安卓：商店内购 + 微信/支付宝）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'monetization_model.dart';

/// 付费墙权益列表（与 MONETIZATION.md §2 一致）
const List<({String label, bool free, bool paid})> _kBenefits = [
  (label: '🎼 智能调音器', free: true, paid: true),
  (label: '⏱️ 节拍器（基础）', free: true, paid: true),
  (label: '🎵 和弦库（全部）', free: false, paid: true),
  (label: '🎼 全部曲谱（进阶 & 指弹）', free: false, paid: true),
  (label: '🎤 AI 跟弹评分', free: false, paid: true),
  (label: '🎓 全部课程（必修+选修+Pro）', free: false, paid: true),
  (label: '🏆 排行榜 / 好友 PK', free: false, paid: true),
  (label: '☁️ 云端同步 / 多设备', free: false, paid: true),
];

/// 弹出付费墙
///
/// [reason] 来自 FeatureGate.Locked.reason；[feature] 标识触发功能。
/// 业务页面这样用：
/// ```dart
/// final r = ref.read(featureGateProvider).check(FeatureKey.followScore);
/// if (r is Locked) {
///   await showPaywall(context, feature: r.feature, reason: r.reason);
///   return;
/// }
/// ```
Future<void> showPaywall(
  BuildContext context, {
  FeatureKey? feature,
  required String reason,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaywallSheet(),
  );
}

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // 标题
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.purple, AppColors.orange]),
              shape: BoxShape.circle,
            ),
            child: const Text('👑', style: TextStyle(fontSize: 32)),
          ),
          const SizedBox(height: 10),
          const Text('开通永久会员',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('一次买断 · 永久使用 · 无续费压力',
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
          const SizedBox(height: 16),

          // 权益列表
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: _kBenefits
                  .map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(b.label,
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ),
                            Text(b.paid ? '✅' : '—',
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),

          // 价格
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text('¥',
                    style: TextStyle(
                        color: AppColors.orangeDark, fontSize: 14)),
                SizedBox(width: 2),
                Text('99',
                    style: TextStyle(
                        color: AppColors.orangeDark,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1)),
                SizedBox(width: 6),
                Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('永久买断 · 原价 ¥199',
                      style: TextStyle(
                          color: AppColors.text3, fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 开通按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              // TODO(Phase3): 接安卓商店内购 + 微信/支付宝直连
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          '📦 模拟下单：永久会员 ¥99（Phase 3 接入真实支付）')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text('👑 立即开通 ¥99',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          // 次要操作
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _secondaryAction(
                  '🎁 先免费试用', '注册赠 7 天全权益', () => Navigator.pop(context)),
              _secondaryAction(
                  '↻ 恢复购买', '比对渠道订单补开通', () => Navigator.pop(context)),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('以后再说',
                      style: TextStyle(color: AppColors.text3, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _secondaryAction(String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: const TextStyle(color: AppColors.text3, fontSize: 9)),
        ],
      ),
    );
  }
}
