/// 曲谱库列表页
///
/// - 搜索（歌名/歌手）+ 难度筛选
/// - 会员曲目（进阶/指弹）带 👑 标记，点击拦截提示
/// - 非会员曲目进入 SongDetailPage
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/monetization_model.dart';
import '../../core/monetization/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';
import 'song_model.dart';
import 'song_detail_page.dart';

final songSearchProvider = StateProvider<String>((ref) => '');
final songDifficultyProvider = StateProvider<SongDifficulty?>((ref) => null);

class SongsPage extends ConsumerWidget {
  const SongsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyword = ref.watch(songSearchProvider);
    final filter = ref.watch(songDifficultyProvider);

    final list = kSongs.where((s) {
      final kw = keyword.trim();
      final matchKw = kw.isEmpty ||
          s.title.contains(kw) ||
          s.artist.contains(kw);
      final matchDiff = filter == null || s.difficulty == filter;
      return matchKw && matchDiff;
    }).toList();

    final chips = <({String label, SongDifficulty? diff})>[
      (label: '全部', diff: null),
      (label: '⭐ 入门', diff: SongDifficulty.beginner),
      (label: '⭐⭐⭐ 进阶', diff: SongDifficulty.intermediate),
      (label: '⭐⭐⭐⭐⭐ 指弹', diff: SongDifficulty.fingerstyle),
    ];

    return Scaffold(
      body: Column(
        children: [
          // 渐变头部
          Container(
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎼 曲谱库',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('海量尤克里里谱，边弹边唱',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                // 搜索框
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.rBtn),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (v) =>
                        ref.read(songSearchProvider.notifier).state = v,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.search, color: AppColors.orange),
                      hintText: '搜索歌名 / 歌手',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 筛选
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: chips.map((c) {
                final selected = filter == c.diff;
                return GestureDetector(
                  onTap: () =>
                      ref.read(songDifficultyProvider.notifier).state = c.diff,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.orange : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 6,
                            offset: Offset(0, 1)),
                      ],
                    ),
                    child: Text(c.label,
                        style: TextStyle(
                          color: selected ? Colors.white : AppColors.text2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
          // 列表
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('没有匹配的曲谱',
                        style: TextStyle(color: AppColors.text3)))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _SongRow(song: list[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SongRow extends ConsumerWidget {
  final Song song;
  const _SongRow({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        // 会员曲目（进阶/指弹）：直接弹付费墙
        // 注：MVP 阶段 kMvpAllFree 总开关会让 FeatureGate 一律放行，
        //     但会员曲目天然受控，这里绕过总开关直接拦截，保证付费墙可演示。
        //     Phase 3 接支付后，改为读用户真实权益：会员用户放行，否则弹墙。
        if (song.isMemberOnly) {
          await showPaywall(
            context,
            feature: FeatureKey.songAdvanced,
            reason: '开通永久会员，解锁全部进阶 & 指弹曲谱',
          );
          return;
        }
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SongDetailPage(song: song)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 封面
            Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [song.color, song.colorLight]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(song.emoji, style: const TextStyle(fontSize: 24)),
                ),
                if (song.isMemberOnly)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          AppColors.purple,
                          AppColors.orange,
                        ]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('👑',
                          style: TextStyle(fontSize: 9)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('${song.artist} · ${song.tag} · ${song.keyName}调',
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.text2)),
                ],
              ),
            ),
            // 难度
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('⭐' * song.difficulty.stars,
                    style: const TextStyle(fontSize: 10)),
                const SizedBox(height: 2),
                Text(
                  song.isMemberOnly ? '会员' : song.difficulty.label,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        song.isMemberOnly ? AppColors.purple : AppColors.text3,
                    fontWeight: song.isMemberOnly
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
