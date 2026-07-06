/// App 主题（对应 DESIGN-SPEC.md 活力年轻渐变风）
///
/// v2.0 美化升级：
/// - 统一设计令牌（Design Tokens）：圆角/阴影/间距
/// - 新增辅助渐变色（日落/海洋/晨光）
/// - 通用组件：GlassCard（毛玻璃）/ ShadowCard（阴影卡片）
/// - 背景：淡渐变替代纯灰
library;

import 'package:flutter/material.dart';

class AppColors {
  // 品牌渐变
  static const orange = Color(0xFFFF8A3D);
  static const orangeDark = Color(0xFFFF6B2C);
  static const orangeLight = Color(0xFFFFB880);
  static const teal = Color(0xFF2DD4BF);
  static const tealDark = Color(0xFF14B8A6);
  static const purple = Color(0xFF7C3AED);
  static const purpleLight = Color(0xFFA78BFA);

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
  static const bgGradientStart = Color(0xFFFFFBF5); // 淡橙白
  static const bgGradientEnd = Color(0xFFF5F3FF);   // 淡紫白

  // 暗色模式
  static const darkBg = Color(0xFF111827);
  static const darkCard = Color(0xFF1E293B);
  static const darkCardLight = Color(0xFF334155);

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

  /// 日落渐变（紫→橙）
  static const sunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple, orange],
  );

  /// 海洋渐变（青→蓝绿）
  static const oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, Color(0xFF0EA5E9)],
  );

  /// 晨光渐变（橙→黄）
  static const dawnGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, Color(0xFFFCD34D)],
  );

  /// 背景渐变（极淡橙→极淡紫）
  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgGradientStart, bgGradientEnd],
  );
}

/// 设计令牌（Design Tokens）—— 统一圆角、阴影、间距
class AppSpacing {
  /// 卡片圆角（统一 16px）
  static const double cardRadius = 16;

  /// 小圆角（按钮/标签）
  static const double smallRadius = 12;

  /// 超大圆角（底部弹窗）
  static const double xlRadius = 24;

  /// 阴影（低）
  static List<BoxShadow> get shadowLow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// 阴影（中）
  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// 阴影（高，特色卡片用）
  static List<BoxShadow> get shadowHigh => [
    BoxShadow(
      color: AppColors.orange.withValues(alpha: 0.15),
      blurRadius: 20,
      spreadRadius: 2,
      offset: const Offset(0, 6),
    ),
  ];

  /// 彩色阴影（渐变卡片用）
  static List<BoxShadow> coloredShadow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.3),
      blurRadius: 16,
      spreadRadius: 1,
      offset: const Offset(0, 4),
    ),
  ];
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
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
      ),
    );
  }

  /// 卡片圆角（兼容旧代码）
  static const double rCard = AppSpacing.cardRadius;
  static const double rBtn = AppSpacing.smallRadius;
}

// ════════════════════════════════════════════════════════════════
// 通用美化组件
// ════════════════════════════════════════════════════════════════

/// 阴影卡片：统一的圆角 + 阴影 + 白色背景
class ShadowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  const ShadowCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.shadows,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow: shadows ?? AppSpacing.shadowLow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 渐变按钮：替代纯色 ElevatedButton
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Gradient? gradient;
  final double height;
  final double borderRadius;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.gradient,
    this.height = 50,
    this.borderRadius = 999,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.brandGradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: AppSpacing.coloredShadow(AppColors.orange),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 渐变图标背景：给 emoji/icon 加圆形渐变底色
class GradientIconBg extends StatelessWidget {
  final String icon;
  final Gradient? gradient;
  final double size;

  const GradientIconBg({
    super.key,
    required this.icon,
    this.gradient,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.brandGradient,
        shape: BoxShape.circle,
        boxShadow: AppSpacing.shadowLow,
      ),
      child: Center(
        child: Text(icon, style: TextStyle(fontSize: size * 0.5)),
      ),
    );
  }
}
