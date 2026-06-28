/// 和弦识别服务（基于 Chroma 色度特征）
///
/// 用 FFT 算频谱 → 频率按 12 个音类(C..B)归类累加能量 → 12 维色度向量
/// → 与和弦模板做余弦相似度匹配 → 得到最可能的和弦。
///
/// 这是业界标准方案（区别于 YIN 单音识别），能处理扫弦（多音叠加）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// 音名（12 个音类）
const List<String> kPitchClasses = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

/// 识别结果
class ChordResult {
  final String? chord;       // 最匹配和弦（null=未达阈值）
  final String? bestMatch;   // 相似度最高的和弦名（诊断用，无论是否过阈值）
  final double score;        // 最高相似度分数
  final List<double> chroma; // 12 维色度向量（诊断用）
  const ChordResult({this.chord, this.bestMatch, required this.score, required this.chroma});
}

/// 和弦识别器
class ChordRecognizer {
  final int _sampleRate;
  late final int _fftSize;
  late final FFT _fft;
  late final Float64List _window; // 汉宁窗，减少频谱泄漏

  ChordRecognizer(this._sampleRate, {int fftSize = 4096}) {
    _fftSize = fftSize;
    _fft = FFT(fftSize);
    _window = _hannWindow(fftSize);
  }

  /// 详细识别（返回和弦 + 相似度 + 色度向量）
  ///
  /// [sampleRate] 可覆盖构造时的采样率（用于 Web 实际采样率可能不同）
  ChordResult recognizeDetailed(List<double> samples, {int? sampleRate}) {
    final sr = sampleRate ?? _sampleRate;
    // 1. 能量检查（噪声门限）
    double sumSq = 0;
    for (final s in samples) {
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / samples.length);
    if (rms < 0.012) {
      return const ChordResult(chord: null, bestMatch: null, score: 0, chroma: []);
    }

    // 2. 补零到 fftSize + 加汉宁窗
    final padded = List<double>.filled(_fftSize, 0);
    final n = math.min(samples.length, _fftSize);
    for (var i = 0; i < n; i++) {
      padded[i] = samples[i] * _window[i];
    }

    // 3. FFT
    final freqData = _fft.realFft(padded);

    // 4. 计算 12 维色度向量（高斯软分配，避免半音边界跳变）
    // 关键改进：不用 round 硬取整，而是把每个 bin 的能量按高斯权重
    // 分配到最近的几个音类。这样边界频率不会突然归到相邻半音。
    final chroma = List<double>.filled(12, 0);
    final binCount = _fftSize ~/ 2;
    // 高斯标准差：约 0.5 个半音（能量主要落在最近音类，少量给相邻）
    const gaussSigma = 0.5;
    for (var bin = 1; bin < binCount; bin++) {
      final freq = bin * sr / _fftSize;
      if (freq < 130 || freq > 1100) continue; // 尤克里里音域
      final re = freqData[bin].x;
      final im = freqData[bin].y;
      final magnitude = math.sqrt(re * re + im * im);
      final midi = 69 + 12 * (math.log(freq / 440) / math.log(2));
      // 软分配：找最近的两个音类，按高斯分配能量
      final pcFloat = midi % 12; // 连续音类值（如 11.7 = 接近 B）
      final lower = pcFloat.floor() % 12;
      final upper = (lower + 1) % 12;
      final frac = pcFloat - pcFloat.floor(); // 到 lower 的距离（0~1 半音）
      // 高斯权重：离得近的音类分得多
      final wLower = math.exp(-(frac * frac) / (2 * gaussSigma * gaussSigma));
      final wUpper = math.exp(-((1 - frac) * (1 - frac)) / (2 * gaussSigma * gaussSigma));
      chroma[lower] += magnitude * wLower;
      chroma[upper] += magnitude * wUpper;
    }

    // 5. 归一化（L2）
    double norm = 0;
    for (final c in chroma) {
      norm += c * c;
    }
    norm = math.sqrt(norm);
    if (norm < 0.001) {
      return const ChordResult(chord: null, bestMatch: null, score: 0, chroma: []);
    }
    for (var i = 0; i < 12; i++) {
      chroma[i] /= norm;
    }

    // 6. 匹配
    return _matchChord(chroma);
  }

  ChordResult _matchChord(List<double> chroma) {
    String? best;
    double bestScore = -1;
    for (final entry in _chordTemplates.entries) {
      final template = entry.value;
      double dot = 0;
      double tNorm = 0;
      for (var i = 0; i < 12; i++) {
        dot += chroma[i] * template[i];
        tNorm += template[i] * template[i];
      }
      tNorm = math.sqrt(tNorm);
      if (tNorm == 0) continue;
      final score = dot / tNorm;
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
    return ChordResult(
      chord: bestScore > 0.7 ? best : null,
      bestMatch: best,
      score: bestScore,
      chroma: chroma,
    );
  }

  Float64List _hannWindow(int size) {
    final w = Float64List(size);
    for (var i = 0; i < size; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1));
    }
    return w;
  }

  /// 和弦模板（大三/小三/属七，各 12 个）
  static final Map<String, List<double>> _chordTemplates = _buildTemplates();

  static Map<String, List<double>> _buildTemplates() {
    final result = <String, List<double>>{};
    for (var i = 0; i < 12; i++) {
      // 大三和弦：根音 + 大三度(+4) + 纯五度(+7)
      final major = List<double>.filled(12, 0);
      major[i] = 1; major[(i + 4) % 12] = 1; major[(i + 7) % 12] = 1;
      result[kPitchClasses[i]] = major;
      // 小三和弦：根音 + 小三度(+3) + 纯五度(+7)
      final minor = List<double>.filled(12, 0);
      minor[i] = 1; minor[(i + 3) % 12] = 1; minor[(i + 7) % 12] = 1;
      result['${kPitchClasses[i]}m'] = minor;
      // 属七和弦：根音 + 大三度(+4) + 纯五度(+7) + 小七度(+10)
      final dom7 = List<double>.filled(12, 0);
      dom7[i] = 1; dom7[(i + 4) % 12] = 1; dom7[(i + 7) % 12] = 1; dom7[(i + 10) % 12] = 1;
      result['${kPitchClasses[i]}7'] = dom7;
    }
    return result;
  }
}
