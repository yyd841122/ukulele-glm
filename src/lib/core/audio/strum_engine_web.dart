/// 扫弦引擎 - Web 实现（采样拼接 v3）
///
/// v3 改进：使用预录制的真实采样（assets/sounds/strum/*.wav）替代合成。
/// - 启动时预加载 WAV 到 AudioBuffer 缓存
/// - 扫弦时按和弦名查找采样，用 AudioBufferSourceNode 播放
/// - 4 弦错峰触发（和单音采样模拟扫弦效果）
/// - 延迟可控在 10ms 内（AudioBufferSourceNode 直接 start）
///
/// 采样命名：strum_<和弦名>.wav（如 strum_C.wav, strum_Am.wav）
/// 单音命名：strum_<音名><八度>.wav（如 strum_C4.wav）
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'strum_types.dart';

/// 预加载的采样缓存：文件名 → AudioBuffer
final Map<String, web.AudioBuffer> _sampleCache = {};

/// AudioContext（共享）
web.AudioContext? _cachedCtx;

/// 已预加载的和弦名集合
final Set<String> _loadedChords = {};

/// 预加载常用和弦采样（启动时调用一次）
Future<void> preloadStrumSamplesImpl(List<String> chordNames) async {
  final ctx = _getCtx();
  if (ctx == null) return;
  for (final name in chordNames) {
    if (_sampleCache.containsKey('strum_$name.wav')) continue;
    try {
      final response = await web.window.fetch('assets/sounds/strum/strum_$name.wav'.toJS).toDart;
      final arrayBuffer = await response.arrayBuffer().toDart;
      final audioBuffer = await ctx.decodeAudioData(arrayBuffer).toDart;
      _sampleCache['strum_$name.wav'] = audioBuffer;
      _loadedChords.add(name);
    } catch (_) {
      // 采样不存在，静默跳过
    }
  }
}

/// 获取 AudioContext
web.AudioContext? _getCtx() {
  if (_cachedCtx != null) {
    if (_cachedCtx!.state != 'closed') {
      if (_cachedCtx!.state == 'suspended') {
        _cachedCtx!.resume().toDart;
      }
      return _cachedCtx;
    }
  }
  try {
    _cachedCtx = web.AudioContext();
    return _cachedCtx;
  } catch (_) {
    return null;
  }
}

void playStrumImpl({
  required List<double> frequencies,
  required StrumDirection direction,
  required double volume,
}) {
  try {
    final ctx = _getCtx();
    if (ctx == null) return;
    final now = ctx.currentTime;

    // 尝试从频率推断和弦名（用于查采样）
    final chordName = _inferChordName(frequencies);

    // 优先用采样播放
    if (chordName != null && _sampleCache.containsKey('strum_$chordName.wav')) {
      _playSample(ctx, now, 'strum_$chordName.wav', volume, direction);
      return;
    }

    // 兜底：用单音采样错峰播放（模拟扫弦）
    final order = direction == StrumDirection.down ? [0, 1, 2, 3] : [3, 2, 1, 0];
    for (var i = 0; i < order.length; i++) {
      final freq = frequencies[order[i]];
      if (freq <= 0) continue;
      final delay = (direction == StrumDirection.down ? 0.018 : 0.012) * i;
      final dynamics = direction == StrumDirection.down
          ? 1.0 - i * 0.08
          : 0.6 + i * 0.13;
      _playNoteSample(ctx, now + delay, freq, volume * dynamics);
    }
  } catch (_) {}
}

/// 播放和弦采样（完整扫弦录音）
void _playSample(web.AudioContext ctx, double startTime, String sampleKey, double volume, StrumDirection direction) {
  final buffer = _sampleCache[sampleKey];
  if (buffer == null) return;

  final src = ctx.createBufferSource();
  src.buffer = buffer;
  // 上扫时反向播放（近似上扫效果）
  if (direction == StrumDirection.up) {
    src.playbackRate.value = 1.1; // 稍快一点模拟上扫的轻快感
  }

  final gain = ctx.createGain();
  gain.gain.setValueAtTime(0.0, startTime);
  gain.gain.linearRampToValueAtTime(volume * 1.2, startTime + 0.003);
  gain.gain.exponentialRampToValueAtTime(0.001, startTime + buffer.duration.toDouble());

  src.connect(gain);
  gain.connect(ctx.destination);
  src.start(startTime);
}

/// 播放单音采样（兜底方案）
void _playNoteSample(web.AudioContext ctx, double startTime, double freq, double volume) {
  // 频率 → 音名+八度 → 文件名
  final noteName = _freqToNoteName(freq);
  final sampleKey = 'strum_$noteName.wav';

  if (_sampleCache.containsKey(sampleKey)) {
    final buffer = _sampleCache[sampleKey]!;
    final src = ctx.createBufferSource();
    src.buffer = buffer;

    final gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0, startTime);
    gain.gain.linearRampToValueAtTime(volume, startTime + 0.002);
    gain.gain.exponentialRampToValueAtTime(0.001, startTime + 0.6);

    src.connect(gain);
    gain.connect(ctx.destination);
    src.start(startTime);
  } else {
    // 最终兜底：简单合成
    _synthesizeString(ctx, startTime, freq, volume);
  }
}

/// 从频率列表推断和弦名（简单的模式匹配）
String? _inferChordName(List<double> freqs) {
  // 把频率转成音名集合
  final noteNames = <String>{};
  for (final f in freqs) {
    if (f > 0) noteNames.add(_freqToNoteNameBase(f));
  }
  // 匹配常用和弦
  // C = {C,E,G}, Am = {A,C,E}, F = {F,A,C}, G = {G,B,D}
  // Em = {E,G,B}, Dm = {D,F,A}, G7 = {G,B,D,F}
  if (noteNames.containsAll({'C', 'E', 'G'})) return 'C';
  if (noteNames.containsAll({'A', 'C', 'E'})) return 'Am';
  if (noteNames.containsAll({'F', 'A', 'C'})) return 'F';
  if (noteNames.containsAll({'G', 'B', 'D'})) return 'G';
  if (noteNames.containsAll({'E', 'G', 'B'})) return 'Em';
  if (noteNames.containsAll({'D', 'F', 'A'})) return 'Dm';
  return null;
}

/// 频率 → 音名+八度（如 C4, A#4）
String _freqToNoteName(double freq) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final midi = (69 + 12 * _log2(freq / 440)).round().clamp(0, 127);
  // 用对数算
  final midiFloat = 69 + 12 * (_log2(freq / 440));
  final midiRound = midiFloat.round();
  final idx = ((midiRound % 12) + 12) % 12;
  final octave = (midiRound / 12).floor() - 1;
  return '${names[idx]}$octave';
}

/// 频率 → 基础音名（不含八度）
String _freqToNoteNameBase(double freq) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final midiFloat = 69 + 12 * (_log2(freq / 440));
  final midiRound = midiFloat.round();
  final idx = ((midiRound % 12) + 12) % 12;
  return names[idx];
}

/// log2
double _log2(double x) {
  // ln(x)/ln(2)
  return _ln(x) / 0.6931471805599453;
}

/// 自然对数（泰勒近似，足够精度）
double _ln(double x) {
  if (x <= 0) return -1000;
  // 用 dart:math 的 log 更准，但避免额外 import
  // 这里用简单近似：log(x) ≈ 2*atanh((x-1)/(x+1))
  final t = (x - 1) / (x + 1);
  return 2 * (t + t * t * t / 3 + t * t * t * t * t / 5);
}

/// 最终兜底合成（采样都没有时）
void _synthesizeString(web.AudioContext ctx, double startTime, double freq, double vol) {
  final osc = ctx.createOscillator();
  osc.type = 'sawtooth';
  osc.frequency.value = freq;

  final gain = ctx.createGain();
  gain.gain.setValueAtTime(0.0, startTime);
  gain.gain.linearRampToValueAtTime(vol * 0.8, startTime + 0.002);
  gain.gain.exponentialRampToValueAtTime(0.0001, startTime + 0.5);

  final filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = freq * 6;

  osc.connect(filter);
  filter.connect(gain);
  gain.connect(ctx.destination);
  osc.start(startTime);
  osc.stop(startTime + 0.6);
}
