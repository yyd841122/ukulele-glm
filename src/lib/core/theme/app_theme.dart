/// App 主题（对应 DESIGN-SPEC.md 活力年轻渐变风）
library;

import 'package:flutter/material.dart';

class AppColors {
  // 品牌渐变
  static const orange = Color(0xFFFF8A3D);
  static const orangeDark = Color(0xFFFF6B2C);
  static const teal = Color(0xFF2DD4BF);
  static const purple = Color(0xFF7C3AED);

  // 功能色
  static const ok = Color(0xFF22C55E);
  static const warn = Color(0xFFF59E0B);
  static const err = Color(0xFFEF4444);

  // 中性色
  static const text1 = Color(0xFF1F2937);
  static const text2 = Color(0xFF6B7280);
  static const text3 = Color(0xFF9CA3AF);
  static const line = Color(0xFFE5E7EB);
  static const bg = Color(0xFFF9FAFB);

  // 渐变
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, orangeDark],
  );

  static const islandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, teal],
  );
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.orange,
        primary: AppColors.orange,
      ),
      fontFamily: null, // 用系统默认（苹方/HarmonyOS Sans）
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text1,
      ),
    );
  }

  /// 卡片圆角
  static const double rCard = 16;
  static const double rBtn = 12;
}
