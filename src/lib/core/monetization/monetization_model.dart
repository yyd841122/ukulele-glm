/// 商业化核心模型（会员/权益/FeatureGate）
///
/// 对应 TDD §4.2 商业化域实体 + §6.5 FeatureGate 架构 + MONETIZATION.md。
/// MVP 阶段即建立这套接口，功能暂全免费放行，Phase 3 接支付时业务页面零改动。
library;

import 'package:flutter/foundation.dart';

/// 会员档位（枚举只追加不删改）
///
/// 优先级（就高原则）：LIFETIME > VIP_ALL > TRIAL > FREE
enum Tier {
  /// 免费版（受限）
  free,

  /// 试用期（注册赠送，7 天全权益）
  trial,

  /// 永久会员（一次付费，永久解锁尤克里里全部）
  lifetime,

  /// 全品类 VIP（远期，多乐器）
  vipAll;

  /// 优先级数值，越大越高
  int get priority => switch (this) {
        Tier.free => 0,
        Tier.trial => 1,
        Tier.lifetime => 3,
        Tier.vipAll => 2,
      };
}

/// 受控功能 Key（与 MONETIZATION.md §2 权益矩阵一一对应）
///
/// 新增功能需受权益控制时，在此枚举追加，禁止散落字符串。
enum FeatureKey {
  // 工具
  tunerBasic, // 基础调音 🟢免费
  metronomeBasic, // 基础节拍 🟢免费
  metronomeAdvanced, // 节拍细分/自定义节奏型 🔴会员
  chordLibraryBasic, // 基础和弦 🟢免费
  chordLibraryAdvanced, // 进阶和弦全库 🔴会员

  // 曲谱
  songBeginner, // 入门曲目 🟢免费
  songAdvanced, // 进阶/指弹曲目 🔴会员

  // 播放器
  playerBasic, // 滚动播放/变速变调 🟢免费
  followScore, // 跟弹 AI 评分 🟡免费每日3次/会员无限

  // 课程
  courseBasic, // 必修课前若干节 🟢免费
  courseFull, // 全部课程（必修+选修+Pro） 🔴会员

  // 游戏化/数据
  gamificationBasic, // 打卡/基础成就 🟢免费
  leaderboard, // 排行榜/好友PK 🔴会员
  cloudSync, // 云端同步/多设备 🔴会员
}

/// 权益矩阵：每个功能在不同档位下的可用性
///
/// 配置集中在此，调整免费/会员边界只改这一处。
/// 见 MONETIZATION.md §2。
@immutable
class FeatureRule {
  final FeatureKey feature;

  /// 免费档是否可用
  final bool freeAllowed;

  /// 免费档每日限额（null=无限，>0=每日N次）。仅当 freeAllowed=true 时有意义。
  final int? freeDailyLimit;

  /// 试用/会员档是否可用（试用与终身会员都视为全开）
  static const _paidAllowed = true;

  const FeatureRule({
    required this.feature,
    required this.freeAllowed,
    this.freeDailyLimit,
  });

  /// 判定某档位是否可用（不计限额）
  bool allowedFor(Tier tier) {
    if (tier == Tier.free) return freeAllowed;
    return _paidAllowed; // trial/lifetime/vipAll 全开
  }

  /// 免费档每日限额（仅 free 档有意义）
  int? dailyLimitFor(Tier tier) {
    if (tier == Tier.free) return freeDailyLimit;
    return null; // 付费档无限
  }
}

/// 权益矩阵表（单一事实来源）
const Map<FeatureKey, FeatureRule> kFeatureRules = {
  FeatureKey.tunerBasic: FeatureRule(feature: FeatureKey.tunerBasic, freeAllowed: true),
  FeatureKey.metronomeBasic: FeatureRule(feature: FeatureKey.metronomeBasic, freeAllowed: true),
  FeatureKey.metronomeAdvanced: FeatureRule(feature: FeatureKey.metronomeAdvanced, freeAllowed: false),
  FeatureKey.chordLibraryBasic: FeatureRule(feature: FeatureKey.chordLibraryBasic, freeAllowed: true),
  FeatureKey.chordLibraryAdvanced: FeatureRule(feature: FeatureKey.chordLibraryAdvanced, freeAllowed: false),
  FeatureKey.songBeginner: FeatureRule(feature: FeatureKey.songBeginner, freeAllowed: true),
  FeatureKey.songAdvanced: FeatureRule(feature: FeatureKey.songAdvanced, freeAllowed: false),
  FeatureKey.playerBasic: FeatureRule(feature: FeatureKey.playerBasic, freeAllowed: true),
  // 跟弹评分：免费每日 3 次，会员无限
  FeatureKey.followScore: FeatureRule(feature: FeatureKey.followScore, freeAllowed: true, freeDailyLimit: 3),
  FeatureKey.courseBasic: FeatureRule(feature: FeatureKey.courseBasic, freeAllowed: true),
  FeatureKey.courseFull: FeatureRule(feature: FeatureKey.courseFull, freeAllowed: false),
  FeatureKey.gamificationBasic: FeatureRule(feature: FeatureKey.gamificationBasic, freeAllowed: true),
  FeatureKey.leaderboard: FeatureRule(feature: FeatureKey.leaderboard, freeAllowed: false),
  FeatureKey.cloudSync: FeatureRule(feature: FeatureKey.cloudSync, freeAllowed: false),
};
