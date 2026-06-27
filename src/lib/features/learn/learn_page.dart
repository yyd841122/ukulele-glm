/// 学习页（占位，V1 完善）
library;

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LearnPage extends StatelessWidget {
  const LearnPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                Text('跟着 AI 私教，7 天弹唱第一首歌',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Text('📚 互动视频教学\nV1 阶段开发',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.text2, height: 1.8)),
            ),
          ),
        ],
      ),
    );
  }
}
