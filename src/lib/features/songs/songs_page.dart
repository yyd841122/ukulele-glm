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
import 'song_editor_page.dart';
import 'user_songs_storage.dart';
import '../practice/follow_score_page.dart' hide kSongs;
import '../practice/song_chord_play_page.dart';
import 'chordpro_parser.dart';

final songSearchProvider = StateProvider<String>((ref) => '');
final songDifficultyProvider = StateProvider<SongDifficulty?>((ref) => null);

class SongsPage extends ConsumerStatefulWidget {
  const SongsPage({super.key});

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  List<UserSong> _userSongs = [];
  bool _loadingUserSongs = true;

  @override
  void initState() {
    super.initState();
    _loadUserSongs();
  }

  Future<void> _loadUserSongs() async {
    final songs = await UserSongsStorage.loadAll();
    if (mounted) setState(() { _userSongs = songs; _loadingUserSongs = false; });
  }

  @override
  Widget build(BuildContext context) {
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SongEditorPage()));
          if (result == true) _loadUserSongs();
        },
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('新建曲谱', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
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
                    borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
                    boxShadow: AppSpacing.shadowLow,
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
                        gradient: selected ? AppColors.brandGradient : null,
                        color: selected ? null : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: AppSpacing.shadowLow,
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
            child: list.isEmpty && _userSongs.isEmpty
                ? const Center(
                    child: Text('没有匹配的曲谱',
                        style: TextStyle(color: AppColors.text3)))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: (_userSongs.isEmpty ? 0 : _userSongs.length + 1) + list.length,
                    itemBuilder: (_, i) {
                      // 用户曲谱区
                      if (_userSongs.isNotEmpty) {
                        if (i == 0) {
                          return _buildUserSongsHeader();
                        }
                        if (i <= _userSongs.length) {
                          return _buildUserSongRow(_userSongs[i - 1]);
                        }
                        return _SongRow(song: list[i - _userSongs.length - 1]);
                      }
                      return _SongRow(song: list[i]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSongsHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        const Text('📝 我的曲谱', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.orange)),
        const Spacer(),
        Text('${_userSongs.length} 首', style: const TextStyle(color: AppColors.text3, fontSize: 12)),
      ]),
    );
  }

  Widget _buildUserSongRow(UserSong userSong) {
    return Dismissible(
      key: ValueKey(userSong.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.err,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        await UserSongsStorage.delete(userSong.id);
        setState(() => _userSongs.removeWhere((s) => s.id == userSong.id));
      },
      child: InkWell(
        onTap: () {
          // 解析并进入和弦弹唱
          final result = parseChordPro(userSong.chordPro);
          if (result.song != null) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => SongChordPlayPage(
                song: result.song!,
                accompaniment: true,
                bpm: userSong.bpm,
                rounds: 1,
              ),
            ));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.error ?? '解析失败')),
            );
          }
        },
        onLongPress: () async {
          // 长按编辑
          final res = await Navigator.push(context, MaterialPageRoute(
            builder: (_) => SongEditorPage(existing: userSong)));
          if (res == true) _loadUserSongs();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            boxShadow: AppSpacing.shadowLow,
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(child: Text('📝', style: TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userSong.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('${userSong.artist} · ${userSong.bpm}BPM',
                    style: const TextStyle(fontSize: 11, color: AppColors.text2)),
              ],
            )),
            const Icon(Icons.music_note, color: AppColors.orange, size: 20),
          ]),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppSpacing.coloredShadow(song.color),
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
