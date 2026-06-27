/// App 主壳：底部 5 Tab 导航
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/home/home_page.dart';
import 'features/learn/learn_page.dart';
import 'features/me/me_page.dart';
import 'features/practice/practice_page.dart';
import 'features/songs/songs_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  final _pages = const [
    HomePage(),
    LearnPage(),
    PracticePage(),
    SongsPage(),
    MePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line.withValues(alpha: 0.5))),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _tab('🏠', '首页', 0),
                _tab('🎓', '学习', 1),
                _tab('🎸', '练琴', 2),
                _tab('🎼', '曲谱', 3),
                _tab('👤', '我的', 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String icon, String label, int i) {
    final active = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? AppColors.orange : AppColors.text3,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
