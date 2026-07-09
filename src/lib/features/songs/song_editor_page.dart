/// 曲谱编辑器（ChordPro 风格文本输入 + 和弦快捷面板）
///
/// 用户输入歌词+和弦标记，App 解析后生成可弹唱的曲谱。
///
/// 用法：
/// ```
/// {title: 小星星}
/// {artist: 英国民谣}
/// {bpm: 80}
/// [C]一闪一闪 [G]亮晶晶
/// [Am]满天都是 [F]小星星
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../practice/follow_score_page.dart';
import 'chordpro_parser.dart';
import 'user_songs_storage.dart';

class SongEditorPage extends StatefulWidget {
  final UserSong? existing; // 编辑已有曲谱时传入
  const SongEditorPage({super.key, this.existing});

  @override
  State<SongEditorPage> createState() => _SongEditorPageState();
}

class _SongEditorPageState extends State<SongEditorPage> {
  late TextEditingController _controller;
  final _scrollCtrl = ScrollController();
  ParseResult? _preview;
  bool _saved = false;

  // 常用和弦快捷面板
  static const _quickChords = [
    'C', 'Am', 'F', 'G', 'Em', 'Dm', 'G7', 'C7', 'A7', 'D7', 'E7', 'Bm',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _controller = TextEditingController(text: widget.existing!.chordPro);
    } else {
      _controller = TextEditingController(text: _template);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static const _template = '''{title: 我的歌曲}
{artist: 自定义}
{bpm: 80}

[C]在这里输入歌词 [G]点击上方和弦按钮插入
[Am]和弦会自动标注到 [F]歌词位置''';

  void _insertChord(String chord) {
    final text = _controller.text;
    final sel = _controller.selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final newText = '${text.substring(0, pos)}[$chord]${text.substring(pos)}';
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: pos + chord.length + 2);
    setState(() {});
  }

  void _parse() {
    final result = parseChordPro(_controller.text);
    setState(() => _preview = result);
  }

  Future<void> _save() async {
    final result = parseChordPro(_controller.text);
    if (result.song == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '解析失败')),
      );
      return;
    }
    final song = result.song!;
    final userSong = UserSong(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: song.title,
      artist: song.artist,
      bpm: song.bpm,
      chordPro: _controller.text,
    );
    await UserSongsStorage.save(userSong);
    setState(() => _saved = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ 曲谱已保存到"我的曲谱"')),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.existing != null ? '编辑曲谱' : '新建曲谱',
            style: const TextStyle(fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text1,
        elevation: 0,
        actions: [
          TextButton(onPressed: _parse, child: const Text('预览')),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Column(
        children: [
          // 和弦快捷面板
          Container(
            height: 48,
            color: Colors.white,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: _quickChords.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _insertChord(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // 文本编辑区
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15, height: 1.6),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                  hintText: '输入歌词和和弦...',
                ),
                onChanged: (_) => setState(() => _preview = null),
              ),
            ),
          ),
          // 预览区
          if (_preview != null)
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: _preview!.error != null
                  ? Center(child: Text(_preview!.error!, style: const TextStyle(color: AppColors.err)))
                  : _buildPreview(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final song = _preview!.song!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(song.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('${song.bpm} BPM', style: const TextStyle(color: AppColors.text3, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(song.artist, style: const TextStyle(color: AppColors.text2, fontSize: 13)),
        if (_preview!.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._preview!.warnings.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              const Text('⚠️', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(child: Text(w, style: const TextStyle(color: AppColors.warn, fontSize: 11))),
            ]),
          )),
        ],
        const SizedBox(height: 12),
        const Text('歌词预览：', style: TextStyle(color: AppColors.text3, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...song.lyrics.map((line) => _buildLyricLine(line)),
      ],
    );
  }

  Widget _buildLyricLine(PracticeLyric line) {
    if (line.chords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(line.text, style: const TextStyle(fontSize: 14)),
      );
    }
    final sorted = List<PracticeChord>.from(line.chords)
      ..sort((a, b) => a.position.compareTo(b.position));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 和弦行
          Wrap(
            children: _buildChordRow(sorted, line.text.length),
          ),
          const SizedBox(height: 2),
          // 歌词行
          Text(line.text, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }

  List<Widget> _buildChordRow(List<PracticeChord> sorted, int textLen) {
    final widgets = <Widget>[];
    var lastPos = 0;
    for (final c in sorted) {
      final gap = (c.position - lastPos) * 8.0;
      if (gap > 0) widgets.add(SizedBox(width: gap));
      widgets.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(c.name, style: const TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
      ));
      lastPos = c.position + c.name.length;
    }
    return widgets;
  }
}
