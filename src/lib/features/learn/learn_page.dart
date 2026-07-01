/// 学习页：必修课课程列表
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/monetization_model.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import 'course_detail_page.dart';
import 'course_model.dart';

/// 课程进度（SharedPreferences 持久化）
/// key = courseId, value = 已完成段落数
class CourseProgressNotifier extends StateNotifier<Map<String, int>> {
  CourseProgressNotifier() : super({}) {
    _load();
  }

  static const _key = 'course_progress';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      state = decoded.map((k, v) => MapEntry(k, v as int));
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
  }

  void complete(String courseId, int segments) {
    state = {...state, courseId: segments};
    _save();
  }

  bool isCompleted(String courseId, int totalSegments) {
    return (state[courseId] ?? 0) >= totalSegments;
  }
}

final courseProgressProvider =
    StateNotifierProvider<CourseProgressNotifier, Map<String, int>>((ref) {
  return CourseProgressNotifier();
});

class LearnPage extends ConsumerWidget {
  const LearnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(courseProgressProvider);

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 24),
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🎓 互动课程',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('跟着 AI 私教，从零到弹唱第一首歌',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: kCourses.length,
              itemBuilder: (_, i) {
                final course = kCourses[i];
                final done = progress[course.id] ?? 0;
                final total = course.segments.length;
                final progPercent = total == 0 ? 0 : (done * 100 ~/ total);
                final isCompleted = done >= total;

                return _CourseCard(
                  course: course,
                  progressPercent: progPercent,
                  isCompleted: isCompleted,
                  onTap: () async {
                    // 会员检查：第3课起需会员（演示付费墙）
                    if (!course.isFree) {
                      await showPaywall(context,
                          feature: FeatureKey.courseFull,
                          reason: '开通会员，解锁全部互动课程');
                      return;
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CourseDetailPage(course: course)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  final int progressPercent;
  final bool isCompleted;
  final VoidCallback onTap;
  const _CourseCard({
    required this.course,
    required this.progressPercent,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          boxShadow: const [
            BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // 左侧图标
            Container(
              width: 80,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [course.color, Colors.white]),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.rCard),
                  bottomLeft: Radius.circular(AppTheme.rCard),
                ),
              ),
              alignment: Alignment.center,
              child: Text(course.emoji, style: const TextStyle(fontSize: 36)),
            ),
            // 右侧内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('第 ${course.order} 课',
                            style: const TextStyle(
                                color: AppColors.teal,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        if (!course.isFree)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.purple, AppColors.orange]),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('👑会员', style: TextStyle(fontSize: 9, color: Colors.white)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(course.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(course.subtitle,
                        style: const TextStyle(fontSize: 12, color: AppColors.text2),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progressPercent / 100,
                              minHeight: 6,
                              backgroundColor: const Color(0xFFF3F4F6),
                              valueColor: AlwaysStoppedAnimation(
                                  isCompleted ? AppColors.ok : AppColors.orange),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isCompleted ? '✓ 已完成' : '$progressPercent%',
                          style: TextStyle(
                              fontSize: 11,
                              color: isCompleted ? AppColors.ok : AppColors.text3,
                              fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal),
                        ),
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
