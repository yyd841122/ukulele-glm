/// 尤克里里 AI 学园 · MVP 入口
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: UkuleleApp()));
}

class UkuleleApp extends StatelessWidget {
  const UkuleleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '尤克里里 AI 学园',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppShell(),
    );
  }
}
