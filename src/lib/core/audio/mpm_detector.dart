/// MPM（McLeod Pitch Method）单音音高检测算法 —— 纯 Dart 实现。
///
/// 替换原 YIN 算法。YIN 在尤克里里真实信号上存在八度误差（G 弦识别成 F#、
/// E 弦卡住不跳）和频率偏移问题；MPM 通过不同的归一化方式（NSDF）+ 过零点
/// 峰值检测 + 抛物线插值，对乐器泛音信号更稳定。
///
/// 参考：
/// - McLeod, "A Smarter Way to Find Pitch" (2005)
/// - sevagh/pitch-detection  pitch_mpm.cpp（C++ 事实标准实现）
/// - TarsosDSP PureMpm（Java）
///
/// 算法三步：
///   1. NSDF（Normalized Square Difference Function）：归一化自相关，值域 [-1, 1]
///   2. 峰值检测：在 NSDF 首个负过零点之后，逐正瓣取局部极大值
///   3. 抛物线插值：在峰值附近做亚样本精度插值（关键稳定性技巧）
///   频率：f = sampleRate / τ_interp
///
/// 设计目标（对应 TDD §3.1）：
/// - 音高精度 < ±5 cents（亚样本插值保证）
/// - 支持 C3(130Hz)–C6(1047Hz)，尤克里里四弦 G4/C4/E4/A4 + Low-G(G3)
/// - 单帧 O(N²) 计算（N=2048 约 2M 次乘加，Dart 下每帧数毫秒，可接受）
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// MPM 检测结果
@immutable
class MpmResult {
  /// 识别到的频率（Hz），null 表示未检测到有效音高
  final double? frequency;

  /// 清晰度（clarity，0~1）：最高峰的 NSDF 插值后的值。
  /// 越接近 1 信号越纯净（接近周期信号）。
  /// 与 YIN 的 probability 语义不同（YIN 是误差，越小越好；这里是清晰度，越大越好）。
  final double clarity;

  const MpmResult({this.frequency, required this.clarity});

  @override
  String toString() =>
      'MpmResult(f=${frequency?.toStringAsFixed(1)}Hz, clarity=${clarity.toStringAsFixed(2)})';
}

/// MPM 音高检测器。
///
/// 用法：
/// ```dart
/// final det = MpmDetector(sampleRate: 44100);
/// final r = det.getPitch(samples); // Float32List [-1,1]
/// if (r.frequency != null) { ... }
/// ```
class MpmDetector {
  /// 采样率（Hz），必须与实际采集一致，否则频率整体偏移。
  final int sampleRate;

  /// 峰值接受的最低清晰度阈值。
  /// McLeod 论文默认 0.1（相当宽松，几乎只过滤纯噪声）。
  /// 真机上调音器/跟弹可按需调高（如 0.5）以减少误报。
  final double clarityThreshold;

  /// 仅检测此频率以上（Hz），限制 τ 上限，减小计算量 + 避免极低频误判。
  /// 默认 70Hz（低于尤克里里最低弦 Low-G G3=196Hz 两个八度，留足余量）。
  final double minFrequency;

  MpmDetector({
    required this.sampleRate,
    this.clarityThreshold = 0.1,
    this.minFrequency = 70,
  });

  /// 对一帧 Float32 样本做音高检测。
  MpmResult getPitch(Float32List samples) {
    final n = samples.length;
    if (n < 4) return const MpmResult(clarity: 0);

    // τ 的最大值：maxLag = sampleRate / minFrequency（最低可测频率对应的周期）。
    // 同时不超过 n/2（自相关在 τ>n/2 时窗口太短无意义）。
    final maxLag = math.min(n ~/ 2, (sampleRate / minFrequency).floor());
    if (maxLag < 2) return const MpmResult(clarity: 0);

    // —— 第 1 步：计算 NSDF ——
    // r(τ) = Σ_{j=0}^{n-τ-1} x_j · x_{j+τ}        （自相关，naive O(N²)）
    // m(τ) = Σ_{j=0}^{n-τ-1} x_j² + Σ_{j=0}^{n-τ-1} x_{j+τ}²
    //      = prefixSquares[n-τ] + prefixSquares[n] - prefixSquares[τ]   （前缀和加速）
    // NSDF(τ) = m(τ)==0 ? 0 : 2·r(τ)/m(τ)
    //
    // 预计算 x² 的前缀和，m(τ) 用 O(1) 查表；r(τ) 仍需 O(n-τ) 内层循环。
    final nsdf = Float64List(maxLag + 1);
    final prefixSq = Float64List(n + 1);
    for (var i = 0; i < n; i++) {
      prefixSq[i + 1] = prefixSq[i] + samples[i] * samples[i];
    }

    for (var tau = 0; tau <= maxLag; tau++) {
      // r(τ): 内层求和（窗口 0..n-tau-1）
      double r = 0;
      final windowLen = n - tau;
      for (var j = 0; j < windowLen; j++) {
        r += samples[j] * samples[j + tau];
      }
      // m(τ): sum1 = Σ_{0}^{n-τ-1} x_j² = prefixSq[n-τ] - prefixSq[0]
      //       sum2 = Σ_{τ}^{n-1} x_j²    = prefixSq[n] - prefixSq[τ]
      final sum1 = prefixSq[n - tau];
      final sum2 = prefixSq[n] - prefixSq[tau];
      final m = sum1 + sum2;
      nsdf[tau] = m == 0 ? 0.0 : (2 * r) / m;
    }

    // —— 第 2 步：峰值检测 ——
    // 跳过 τ=0 起始的正区（NSDF(0)=1，单调下降到首个负过零点），
    // 之后逐正瓣（相邻两个负过零点之间的正区）取一个局部极大值。
    final peaks = <int>[];
    var pos = 0;
    final len = nsdf.length;

    // 跳过起始正区
    while (pos < len - 1 && nsdf[pos] > 0) {
      pos++;
    }
    // 跳过负区到下一个正区起点
    while (pos < len - 1 && nsdf[pos] <= 0) {
      pos++;
    }
    if (pos == 0) pos = 1;

    // 逐正瓣找峰
    while (pos < len - 1) {
      if (nsdf[pos] > nsdf[pos - 1] && nsdf[pos] >= nsdf[pos + 1]) {
        // 局部极大：记录并跳到本正瓣结束（下一个负过零点之后）
        peaks.add(pos);
        // 跳过本正瓣剩余部分 + 后续负区
        while (pos < len - 1 && nsdf[pos] > 0) {
          pos++;
        }
        while (pos < len - 1 && nsdf[pos] <= 0) {
          pos++;
        }
      } else {
        pos++;
      }
    }

    if (peaks.isEmpty) return const MpmResult(clarity: 0);

    // —— 第 3 步：抛物线插值 + 选第一个显著峰 ——
    // McLeod 论文：取"第一个 clarity ≥ threshold 的峰"，而非全局最高峰。
    // 原因：带谐波的信号在基频倍周期处（更大 τ）也有清晰度接近 1.0 的峰，
    // 若选全局最高会系统性偏向低八度（实测 392Hz→98Hz 的根因）。
    // 基频对应最小 τ，是峰值扫描中第一个显著峰。
    var bestTau = 0.0;
    var bestVal = 0.0;
    for (final tau in peaks) {
      final a = tau > 0 ? nsdf[tau - 1] : 0.0;
      final b = nsdf[tau];
      final c = tau + 1 < len ? nsdf[tau + 1] : 0.0;
      final denom = a - 2 * b + c;
      double betterTau = tau.toDouble();
      double peakValue = b;
      if (denom.abs() > 1e-9) {
        final x0 = 0.5 * (a - c) / denom;
        betterTau = tau + x0;
        peakValue = b - 0.25 * (a - c) * x0;
      }
      // 取第一个超过阈值的峰即返回（基频优先）
      if (peakValue >= clarityThreshold) {
        return MpmResult(frequency: sampleRate / betterTau, clarity: peakValue);
      }
      // 记录最高值，用于无峰可达阈值时的回退
      if (peakValue > bestVal) {
        bestVal = peakValue;
        bestTau = betterTau;
      }
    }

    if (bestTau <= 0) {
      return MpmResult(frequency: null, clarity: bestVal);
    }
    return MpmResult(frequency: sampleRate / bestTau, clarity: bestVal);
  }
}
