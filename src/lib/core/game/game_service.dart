/// 游戏化数据模型 + 核心服务
///
/// Phase 2 游戏化系统核心：
/// - 经验值/等级（EXP）+ 升级公式
/// - 成就/勋章系统（解锁条件 + 进度）
/// - 连续打卡（每日记录 + 连续天数）
/// - 练习统计（时长/曲目/和弦数）
/// - 本地持久化（SharedPreferences，为 P2-4 云同步预留接口）
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ────────────────────────────────────────────────────────────
//  经验值 / 等级
// ────────────────────────────────────────────────────────────

/// 等级信息
@immutable
class LevelInfo {
  final int level; // 当前等级（1 起）
  final int totalExp; // 累计经验
  final int currentLevelExp; // 当前等级起点 EXP
  final int nextLevelExp; // 升到下一级所需累计 EXP
  final int levelProgress; // 0-100，当前等级进度百分比

  const LevelInfo({
    required this.level,
    required this.totalExp,
    required this.currentLevelExp,
    required this.nextLevelExp,
    required this.levelProgress,
  });

  /// 距离升级还差多少 EXP
  int get expToNext => nextLevelExp - totalExp;

  String get title => switch (level) {
        <= 3 => '尤克里里萌新',
        <= 6 => '弹唱新手',
        <= 10 => '节奏达人',
        <= 15 => '和弦大师',
        <= 20 => '指弹高手',
        _ => '尤克里里宗师',
      };
}

/// 计算等级（累计经验 → 等级信息）
/// 升级公式：第 n 级需要累计 exp = 100 * n * (n+1) / 2（三角数×100）
///   L1: 0, L2: 300, L3: 600, L4: 1000, L5: 1500...
LevelInfo calcLevel(int totalExp) {
  // 找当前等级
  var level = 1;
  while (true) {
    final need = 100 * level * (level + 1) ~/ 2;
    if (totalExp < need) break;
    level++;
  }
  final currentLevelExp = 100 * (level - 1) * level ~/ 2;
  final nextLevelExp = 100 * level * (level + 1) ~/ 2;
  final progress = nextLevelExp == currentLevelExp
      ? 100
      : ((totalExp - currentLevelExp) * 100 ~/ (nextLevelExp - currentLevelExp))
          .clamp(0, 100);
  return LevelInfo(
    level: level,
    totalExp: totalExp,
    currentLevelExp: currentLevelExp,
    nextLevelExp: nextLevelExp,
    levelProgress: progress,
  );
}

// ────────────────────────────────────────────────────────────
//  成就系统
// ────────────────────────────────────────────────────────────

/// 成就类型
enum AchievementType {
  // 练习类
  firstPractice('🎤', '初次尝试', '完成第一次练习', 1),
  practice10('🎵', '勤奋练习', '累计练习 10 次', 10),
  practice50('💪', '练习狂人', '累计练习 50 次', 50),
  // 打卡类
  streak7('🔥', '坚持一周', '连续打卡 7 天', 7),
  streak30('🏆', '月度坚持', '连续打卡 30 天', 30),
  streak100('💎', '百日筑基', '连续打卡 100 天', 100),
  // 评分类
  perfectScore('⭐', '完美演奏', '获得一次满分(100)', 1),
  score80plus('🌟', '高分玩家', '获得 5 次 80 分以上', 5),
  // 课程类
  finishFirstSong('🎸', '首弹成功', '完整弹唱第一首歌', 1),
  master5Chords('🎹', '和弦收集', '掌握 5 个和弦', 5),
  ;

  final String emoji;
  final String name;
  final String desc;
  final int target; // 目标值
  const AchievementType(this.emoji, this.name, this.desc, this.target);
}

/// 成就解锁状态
@immutable
class AchievementStatus {
  final AchievementType type;
  final int progress; // 当前进度值
  final bool unlocked;
  final DateTime? unlockedAt;

  const AchievementStatus({
    required this.type,
    required this.progress,
    required this.unlocked,
    this.unlockedAt,
  });

  double get progressRatio => (progress / type.target).clamp(0.0, 1.0);
}

// ────────────────────────────────────────────────────────────
//  游戏化状态
// ────────────────────────────────────────────────────────────

@immutable
class GameState {
  final int totalExp; // 累计经验
  final int practiceCount; // 练习总次数
  final int highScoreCount; // 80分以上次数
  final int perfectCount; // 满分次数
  final int songsCompleted; // 完整弹唱曲目数
  final int chordsMastered; // 掌握和弦数
  final Set<String> checkinDays; // 已打卡日期集合（yyyy-MM-dd）
  final int currentStreak; // 当前连续打卡天数
  final DateTime? lastCheckin; // 上次打卡日期
  final Map<AchievementType, AchievementStatus> achievements;
  final int totalPracticeSeconds; // 累计练习秒数

  const GameState({
    this.totalExp = 0,
    this.practiceCount = 0,
    this.highScoreCount = 0,
    this.perfectCount = 0,
    this.songsCompleted = 0,
    this.chordsMastered = 0,
    this.checkinDays = const {},
    this.currentStreak = 0,
    this.lastCheckin,
    this.achievements = const {},
    this.totalPracticeSeconds = 0,
  });

  LevelInfo get level => calcLevel(totalExp);
  int get totalCheckinDays => checkinDays.length;
  int get practiceHours => totalPracticeSeconds ~/ 3600;

  GameState copyWith({
    int? totalExp,
    int? practiceCount,
    int? highScoreCount,
    int? perfectCount,
    int? songsCompleted,
    int? chordsMastered,
    Set<String>? checkinDays,
    int? currentStreak,
    DateTime? lastCheckin,
    Map<AchievementType, AchievementStatus>? achievements,
    int? totalPracticeSeconds,
  }) {
    return GameState(
      totalExp: totalExp ?? this.totalExp,
      practiceCount: practiceCount ?? this.practiceCount,
      highScoreCount: highScoreCount ?? this.highScoreCount,
      perfectCount: perfectCount ?? this.perfectCount,
      songsCompleted: songsCompleted ?? this.songsCompleted,
      chordsMastered: chordsMastered ?? this.chordsMastered,
      checkinDays: checkinDays ?? this.checkinDays,
      currentStreak: currentStreak ?? this.currentStreak,
      lastCheckin: lastCheckin ?? this.lastCheckin,
      achievements: achievements ?? this.achievements,
      totalPracticeSeconds: totalPracticeSeconds ?? this.totalPracticeSeconds,
    );
  }
}

// ────────────────────────────────────────────────────────────
//  游戏化服务（StateNotifier）
// ────────────────────────────────────────────────────────────

/// 练习结果（用于上报获得奖励）
@immutable
class PracticeResult {
  final int score; // 本次评分（0-100，-1 表示无评分）
  final int durationSeconds; // 练习时长
  final bool songCompleted; // 是否完整弹完一首歌
  const PracticeResult({
    this.score = -1,
    this.durationSeconds = 0,
    this.songCompleted = false,
  });
}

class GameService extends StateNotifier<GameState> {
  GameService() : super(const GameState()) {
    _load();
  }

  static const _prefix = 'game_';

  /// 从本地加载
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final checkinDays = prefs.getStringList('${_prefix}checkinDays')?.toSet() ?? {};
      final lastCheckinStr = prefs.getString('${_prefix}lastCheckin');
      final achRaw = prefs.getString('${_prefix}achievements') ?? '';

      final achievements = <AchievementType, AchievementStatus>{};
      for (final type in AchievementType.values) {
        achievements[type] = AchievementStatus(
          type: type,
          progress: _progressFor(type, prefs),
          unlocked: achRaw.split(',').contains(type.name),
          unlockedAt: null,
        );
      }

      state = GameState(
        totalExp: prefs.getInt('${_prefix}exp') ?? 0,
        practiceCount: prefs.getInt('${_prefix}practiceCount') ?? 0,
        highScoreCount: prefs.getInt('${_prefix}highScore') ?? 0,
        perfectCount: prefs.getInt('${_prefix}perfect') ?? 0,
        songsCompleted: prefs.getInt('${_prefix}songs') ?? 0,
        chordsMastered: prefs.getInt('${_prefix}chords') ?? 0,
        checkinDays: checkinDays,
        currentStreak: prefs.getInt('${_prefix}streak') ?? 0,
        lastCheckin: lastCheckinStr != null ? DateTime.parse(lastCheckinStr) : null,
        achievements: achievements,
        totalPracticeSeconds: prefs.getInt('${_prefix}seconds') ?? 0,
      );
      _refreshAchievements();
    } catch (e) {
      debugPrint('game load failed: $e');
    }
  }

  int _progressFor(AchievementType t, SharedPreferences p) {
    return switch (t) {
      AchievementType.firstPractice ||
      AchievementType.practice10 ||
      AchievementType.practice50 =>
        p.getInt('${_prefix}practiceCount') ?? 0,
      AchievementType.streak7 ||
      AchievementType.streak30 ||
      AchievementType.streak100 =>
        p.getInt('${_prefix}streak') ?? 0,
      AchievementType.perfectScore => p.getInt('${_prefix}perfect') ?? 0,
      AchievementType.score80plus => p.getInt('${_prefix}highScore') ?? 0,
      AchievementType.finishFirstSong => p.getInt('${_prefix}songs') ?? 0,
      AchievementType.master5Chords => p.getInt('${_prefix}chords') ?? 0,
    };
  }

  // ─── 持久化 ───
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('${_prefix}exp', state.totalExp);
    await p.setInt('${_prefix}practiceCount', state.practiceCount);
    await p.setInt('${_prefix}highScore', state.highScoreCount);
    await p.setInt('${_prefix}perfect', state.perfectCount);
    await p.setInt('${_prefix}songs', state.songsCompleted);
    await p.setInt('${_prefix}chords', state.chordsMastered);
    await p.setStringList('${_prefix}checkinDays', state.checkinDays.toList());
    await p.setInt('${_prefix}streak', state.currentStreak);
    if (state.lastCheckin != null) {
      await p.setString('${_prefix}lastCheckin', state.lastCheckin!.toIso8601String());
    }
    await p.setInt('${_prefix}seconds', state.totalPracticeSeconds);
    final unlockedNames = state.achievements.entries
        .where((e) => e.value.unlocked)
        .map((e) => e.key.name)
        .join(',');
    await p.setString('${_prefix}achievements', unlockedNames);
  }

  /// 今日日期字符串
  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ─── 公开操作 ───

  /// 今日是否已打卡
  bool get isCheckedInToday => state.checkinDays.contains(_today);

  /// 打卡（每日一次）
  /// 返回获得的 EXP
  int checkIn() {
    if (isCheckedInToday) return 0;
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final yStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    // 连续打卡判断：上次打卡是昨天 → streak+1；否则重置为 1
    int newStreak;
    if (state.lastCheckin != null) {
      final lastStr = '${state.lastCheckin!.year}-${state.lastCheckin!.month.toString().padLeft(2, '0')}-${state.lastCheckin!.day.toString().padLeft(2, '0')}';
      newStreak = lastStr == yStr ? state.currentStreak + 1 : 1;
    } else {
      newStreak = 1;
    }

    final expGain = 50 + newStreak * 10; // 连续越久奖励越多
    state = state.copyWith(
      totalExp: state.totalExp + expGain,
      checkinDays: {...state.checkinDays, _today},
      currentStreak: newStreak,
      lastCheckin: today,
    );
    _refreshAchievements();
    _save();
    return expGain;
  }

  /// 上报一次练习结果
  /// 返回获得的 EXP
  int reportPractice(PracticeResult result) {
    int expGain = 20; // 基础经验
    if (result.score >= 80) expGain += 30;
    if (result.score == 100) expGain += 50;

    state = state.copyWith(
      totalExp: state.totalExp + expGain,
      practiceCount: state.practiceCount + 1,
      highScoreCount: state.highScoreCount + (result.score >= 80 ? 1 : 0),
      perfectCount: state.perfectCount + (result.score == 100 ? 1 : 0),
      songsCompleted: state.songsCompleted + (result.songCompleted ? 1 : 0),
      totalPracticeSeconds: state.totalPracticeSeconds + result.durationSeconds,
    );
    _refreshAchievements();
    _save();
    return expGain;
  }

  /// 设置掌握和弦数（从和弦库统计）
  void setChordsMastered(int count) {
    state = state.copyWith(chordsMastered: count);
    _refreshAchievements();
    _save();
  }

  // ─── 成就检查 ───
  void _refreshAchievements() {
    final updated = <AchievementType, AchievementStatus>{};
    for (final type in AchievementType.values) {
      final progress = switch (type) {
        AchievementType.firstPractice ||
        AchievementType.practice10 ||
        AchievementType.practice50 =>
          state.practiceCount,
        AchievementType.streak7 ||
        AchievementType.streak30 ||
        AchievementType.streak100 =>
          state.currentStreak,
        AchievementType.perfectScore => state.perfectCount,
        AchievementType.score80plus => state.highScoreCount,
        AchievementType.finishFirstSong => state.songsCompleted,
        AchievementType.master5Chords => state.chordsMastered,
      };
      final wasUnlocked = state.achievements[type]?.unlocked ?? false;
      final nowUnlocked = wasUnlocked || progress >= type.target;
      updated[type] = AchievementStatus(
        type: type,
        progress: progress,
        unlocked: nowUnlocked,
        unlockedAt: nowUnlocked && !wasUnlocked ? DateTime.now() : state.achievements[type]?.unlockedAt,
      );
    }
    state = state.copyWith(achievements: updated);
  }

  /// 获取本次操作新解锁的成就（用于弹窗提示）
  List<AchievementType> newlyUnlocked() {
    return state.achievements.entries
        .where((e) => e.value.unlocked && e.value.unlockedAt != null &&
            DateTime.now().difference(e.value.unlockedAt!) < const Duration(seconds: 5))
        .map((e) => e.key)
        .toList();
  }
}

// ─── Provider ───
final gameProvider = StateNotifierProvider<GameService, GameState>((ref) {
  return GameService();
});
