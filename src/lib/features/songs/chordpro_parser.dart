/// ChordPro 文本解析器
///
/// 把用户输入的 ChordPro 风格文本解析成 PracticeSong 数据。
///
/// 支持的格式：
/// ```
/// {title: 小星星}
/// {artist: 英国民谣}
/// {key: C}
/// {bpm: 80}
/// [C]一闪一闪 [G]亮晶晶
/// [Am]满天都是 [F]小星星
/// ```
///
/// 也支持无元数据的纯文本（直接 [C]歌词[G]歌词）。
library;

import '../practice/follow_score_page.dart';
import '../practice/chord_library_page.dart' show kChordFretMap;

/// 解析结果
class ParseResult {
  final PracticeSong? song;
  final List<String> warnings; // 警告（如未知和弦）
  final String? error;

  const ParseResult({this.song, this.warnings = const [], this.error});
}

/// 解析 ChordPro 文本为 PracticeSong
ParseResult parseChordPro(String input) {
  try {
    final lines = input.split('\n');
    String title = '自定义歌曲';
    String artist = '我的曲谱';
    int bpm = 80;
    final lyrics = <PracticeLyric>[];
    final warnings = <String>[];
    final allChordNames = <String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 元数据行 {title: xxx}
      final metaMatch = RegExp(r'^\{(title|artist|key|bpm):\s*(.+)\}$').firstMatch(trimmed);
      if (metaMatch != null) {
        final key = metaMatch.group(1)!;
        final value = metaMatch.group(2)!.trim();
        if (key == 'title') title = value;
        else if (key == 'artist') artist = value;
        else if (key == 'bpm') bpm = int.tryParse(value) ?? 80;
        continue;
      }

      // 跳过其他 {directive} 行
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) continue;
      if (trimmed.startsWith('{') && trimmed.contains('}')) continue;

      // 歌词行：提取 [和弦名]
      final chords = <PracticeChord>[];
      final chordRegex = RegExp(r'\[([A-G][#b]?(m|maj|min|sus|dim|aug|add)?\d*)\]');
      // 也支持简单和弦如 [C] [Am] [G7] [F#m]
      final simpleChordRegex = RegExp(r'\[([A-Za-z][#b]?[a-z0-9#+-]*)\]');

      String lyricText = trimmed;
      final allMatches = <RegExpMatch>[];
      simpleChordRegex.allMatches(trimmed).forEach((m) {
        allMatches.add(m);
      });

      if (allMatches.isEmpty) {
        // 无和弦的纯歌词行
        lyrics.add(PracticeLyric(text: trimmed));
        continue;
      }

      // 计算每个和弦在去除标记后的歌词中的位置
      var textOffset = 0; // 在净化后文本中的偏移
      var rawIdx = 0; // 在原始文本中的位置
      final cleanText = trimmed.replaceAll(simpleChordRegex, '');

      for (final m in allMatches) {
        final chordName = m.group(1)!;
        allChordNames.add(chordName);

        // 计算和弦标记在净化文本中的位置
        final rawPos = m.start;
        // 净化位置 = 原始位置 - 在此之前被删除的字符数
        final charsBefore = trimmed.substring(0, rawPos);
        final deletedBefore = simpleChordRegex.allMatches(charsBefore).fold<int>(0, (sum, match) {
          return sum + match.group(0)!.length;
        });
        final cleanPos = rawPos - deletedBefore;

        chords.add(PracticeChord(name: chordName, position: cleanPos.clamp(0, cleanText.length)));
      }

      lyrics.add(PracticeLyric(text: cleanText, chords: chords));
    }

    if (lyrics.isEmpty) {
      return const ParseResult(error: '没有检测到歌词内容，请至少输入一行歌词');
    }

    // 自动补全和弦指法
    final chordFrets = <String, List<int>>{};
    for (final name in allChordNames) {
      final frets = kChordFretMap[name];
      if (frets != null) {
        chordFrets[name] = frets;
      } else {
        warnings.add('和弦 "$name" 没有指法数据，将使用默认指法');
        chordFrets[name] = [0, 0, 0, 0]; // 默认空弦
      }
    }

    return ParseResult(
      song: PracticeSong(
        title: title,
        artist: artist,
        bpm: bpm,
        lyrics: lyrics,
        chordFrets: chordFrets,
      ),
      warnings: warnings,
    );
  } catch (e) {
    return ParseResult(error: '解析失败：$e');
  }
}

/// 把 PracticeSong 序列化为 ChordPro 文本（用于存储/导出）
String songToChordPro(PracticeSong song) {
  final buf = StringBuffer();
  buf.writeln('{title: ${song.title}}');
  buf.writeln('{artist: ${song.artist}}');
  buf.writeln('{bpm: ${song.bpm}}');
  buf.writeln();
  for (final line in song.lyrics) {
    if (line.chords.isEmpty) {
      buf.writeln(line.text);
    } else {
      // 在歌词中插入和弦标记
      final sorted = List<PracticeChord>.from(line.chords)
        ..sort((a, b) => a.position.compareTo(b.position));
      final sb = StringBuffer();
      var lastPos = 0;
      for (final chord in sorted) {
        final pos = chord.position.clamp(0, line.text.length);
        sb.write(line.text.substring(lastPos, pos));
        sb.write('[${chord.name}]');
        lastPos = pos;
      }
      sb.write(line.text.substring(lastPos));
      buf.writeln(sb.toString());
    }
  }
  return buf.toString();
}
