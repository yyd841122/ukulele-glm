/// FeatureGate 权限控制层 + 权益 Provider
///
/// 对应 TDD §6.5。所有受控功能必须经 FeatureGate.check() 统一判定，
/// 禁止业务页面硬编码 isMember 判断。
///
/// MVP 阶段策略：
/// - 默认生效档位 = FREE，但 [kMvpAllFree] 为 true 时全部放行（当前阶段）
/// - Phase 2 切换为 trial + 限额生效
/// - Phase 3 接支付后，从后端/缓存读真实 Entitlement
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'monetization_model.dart';

/// MVP 阶段总开关：true = 所有功能免费放行（架构已搭好，权限暂不拦截）
///
/// Phase 2 设为 false 启用试用期与免费限额；Phase 3 接支付读真实权益。
const bool kMvpAllFree = true;

/// 权限检查结果
@immutable
sealed class AccessResult {
  const AccessResult();
}

/// 放行（无限额）
class Granted extends AccessResult {
  const Granted();
}

/// 放行但受每日限额约束
class GrantedWithQuota extends AccessResult {
  final int used;
  final int limit;
  const GrantedWithQuota({required this.used, required this.limit});

  int get remaining => (limit - used).clamp(0, limit);
}

/// 被锁定（需弹付费墙）
class Locked extends AccessResult {
  final FeatureKey feature;
  final String reason;
  const Locked({required this.feature, required this.reason});
}

/// 当前生效档位 Provider（就高原则）
///
/// MVP：返回 FREE（kMvpAllFree 时业务层全放行）。
/// 未来接入真实权益：从此 provider 读取用户最高档 Entitlement。
final currentTierProvider = StateProvider<Tier>((ref) => Tier.free);

/// 每日用量计数（限额功能，如跟弹评分）
///
/// key = "{featureKey}_{yyyy-MM-dd}"，存于 SharedPreferences。
/// MVP 阶段不真正计数（kMvpAllFree），但接口已就绪。
final usageQuotaProvider =
    StateNotifierProvider<UsageQuotaNotifier, Map<String, int>>((ref) {
  return UsageQuotaNotifier();
});

class UsageQuotaNotifier extends StateNotifier<Map<String, int>> {
  UsageQuotaNotifier() : super({});

  static String _key(FeatureKey f) {
    final today = DateTime.now();
    final d =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return '${f.name}_$d';
  }

  int usedOf(FeatureKey f) => state[_key(f)] ?? 0;

  Future<void> increment(FeatureKey f) async {
    final k = _key(f);
    final next = {...state, k: (state[k] ?? 0) + 1};
    state = next;
    // 持久化（MVP 可选）
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('quota_$k', next[k]!);
    } catch (e) {
      debugPrint('quota persist failed: $e');
    }
  }
}

/// FeatureGate：权限检查入口
class FeatureGate {
  final Ref _ref;
  FeatureGate(this._ref);

  /// 检查某功能当前用户的访问权限
  ///
  /// 返回：
  /// - [Granted]：放行
  /// - [GrantedWithQuota]：限额内放行（可读 remaining）
  /// - [Locked]：需弹付费墙
  AccessResult check(FeatureKey feature) {
    // MVP 阶段：全部放行，但埋点已就绪
    if (kMvpAllFree) {
      return const Granted();
    }

    final tier = _ref.read(currentTierProvider);
    final rule = kFeatureRules[feature] ??
        FeatureRule(feature: feature, freeAllowed: false);

    if (rule.allowedFor(tier)) {
      // 付费档或免费允许
      final limit = rule.dailyLimitFor(tier);
      if (limit != null) {
        final used = _ref.read(usageQuotaProvider.notifier).usedOf(feature);
        if (used >= limit) {
          return Locked(
              feature: feature,
              reason: '今日免费次数已用完（$limit 次/天），开通会员解锁无限使用');
        }
        return GrantedWithQuota(used: used, limit: limit);
      }
      return const Granted();
    }

    return Locked(
        feature: feature, reason: _lockReason(feature));
  }

  String _lockReason(FeatureKey f) => switch (f) {
        FeatureKey.songAdvanced =>
          '开通会员，解锁全部进阶 & 指弹曲谱',
        FeatureKey.followScore =>
          '今日免费评分次数已用完，开通会员解锁无限次 AI 实时评分',
        FeatureKey.courseFull => '开通会员，解锁全部课程（必修+选修+Pro）',
        FeatureKey.leaderboard => '开通会员，解锁排行榜与好友 PK',
        FeatureKey.cloudSync => '开通会员，解锁云端同步与多设备',
        _ => '开通永久会员即可解锁',
      };
}

/// FeatureGate Provider
final featureGateProvider = Provider<FeatureGate>((ref) {
  return FeatureGate(ref);
});
