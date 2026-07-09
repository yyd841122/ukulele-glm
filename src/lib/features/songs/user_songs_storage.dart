/// 用户曲谱本地存储（SharedPreferences + JSON）
///
/// 存储用户自建的 ChordPro 曲谱，重启不丢失。
/// 数据结构：List<JSON>，每个 JSON = {title, artist, bpm, chordPro}
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserSong {
  final String id; // 唯一 ID（时间戳）
  final String title;
  final String artist;
  final int bpm;
  final String chordPro; // ChordPro 原始文本

  const UserSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.bpm,
    required this.chordPro,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'artist': artist, 'bpm': bpm, 'chordPro': chordPro,
  };

  factory UserSong.fromJson(Map<String, dynamic> json) => UserSong(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    bpm: json['bpm'] as int? ?? 80,
    chordPro: json['chordPro'] as String,
  );
}

class UserSongsStorage {
  static const _key = 'user_songs';

  /// 获取所有用户曲谱
  static Future<List<UserSong>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => UserSong.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 保存用户曲谱（新增或更新）
  static Future<void> save(UserSong song) async {
    final all = await loadAll();
    final idx = all.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      all[idx] = song;
    } else {
      all.add(song);
    }
    await _write(all);
  }

  /// 删除用户曲谱
  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((s) => s.id == id);
    await _write(all);
  }

  static Future<void> _write(List<UserSong> songs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(songs.map((s) => s.toJson()).toList());
    await prefs.setString(_key, json);
  }
}
