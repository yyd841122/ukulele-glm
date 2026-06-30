/// NCCF（Normalized Cross-Correlation Function）单音音高检测 —— 纯 Dart 实现。
///
/// 归一化自相关法，是 aubio 等专业音频库调音模块的基础算法，比 YIN/MPM
/// 在数学上更直观：直接计算信号与自身延迟版本的归一化相关性，相关性最高
/// 的延迟 τ 即基频周期。配合抛物线插值达到亚样本精度。
///
/// 替代项目早期的 YIN（八度误差）和 MPM（采样率黑盒导致偏移）。
///
/// 算法步骤：
///   1. 计算每个候选 τ 的归一化自相关 NCCF(τ)
///   2. 在音域对应的 τ 范围内找最大峰
///   3. 抛物线插值精确定位峰值
///   4. 用相对阈值（最大值 × 0.4）过滤噪声/无声
///   频率：f = sampleRate / τ_interp
///
/// 设计目标（对应 TDD §3.1）：
/// - 音高精度 < ±5 cents（抛物线插值保证）
/// - 支持 C3(130Hz)–C6(1047Hz)，覆盖尤克里里 G3/G4–C5
/// - 朴素实现 O(N²)，N=2048 约 2M 乘加/帧，Dart 下每帧数毫秒
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// NCCF 检测结果
@immutable
class NccfResult {
  /// 识别到的频率（Hz），null 表示未检测到有效音高
  final double? frequency;

  /// 置信度（0~1）：最大 NCCF 峰值。越接近 1 信号越纯净（接近周期）。
  /// 用于噪声过滤：低于阈值视为噪声/无声。
  final double confidence;

  const NccfResult({this.frequency, required this.confidence});

  @override
  String toString() =>
      'NccfResult(f=${frequency?.toStringAsFixed(1)}Hz, conf=${confidence.toStringAsFixed(2)})';
}

/// NCCF 音高检测器。
///
/// 用法：
/// ```dart
/// final det = NccfDetector(sampleRate: 48000);
/// final r = det.getPitch(samples); // Float32List [-1,1]
/// if (r.frequency != null) { ... }
/// ```
class NccfDetector {
  /// 采样率（Hz），必须与采集层实际数据采样率一致。
  final int sampleRate;

  /// 仅检测此频率以下（Hz），限制 τ 下限，避免高频泛音被误判为基频。
  /// 【关键】必须设为尤克里里最高基频之上、泛音之下。
  /// 尤克里里基频范围 Low-G(196Hz)~最高品 C5(523Hz)，设 600Hz 留余量。
  /// 之前设 1400Hz 导致真实麦克风信号的高次谐波(787/1053/1297Hz)被误判为基频。
  final double maxFrequency;

  /// 仅检测此频率以上（Hz），限制 τ 上限，减小计算量 + 避免极低频误判。
  /// 默认 70Hz（低于尤克里里最低弦 Low-G G3=196Hz 两个八度，留足余量）。
  final double minFrequency;

  NccfDetector({
    required this.sampleRate,
    this.maxFrequency = 600,
    this.minFrequency = 70,
  });

  /// 对一帧 Float32 样本做音高检测。
  NccfResult getPitch(Float32List input) {
    final n = input.length;
    if (n < 4) return const NccfResult(confidence: 0);

    // —— 信号预处理（业界标准 pipeline，解决真实麦克风信号不稳定）——
    // 1. DC 去除：减去均值，去直流偏移
    // 2. 一阶高通/预加重：y[n] = x[n] - 0.97·x[n-1]，抑制电扇低频噪声 + 强化高频基频
    // 3. 中心削波：保留强周期成分、抑制低幅谐波串扰，让基频峰更突出
    final samples = _preprocess(input);

    // τ 的搜索范围：τ = sampleRate / frequency
    // 低频 → 大 τ，高频 → 小 τ
    final minTau = (sampleRate / maxFrequency).floor();
    final maxTau = math.min(n ~/ 2, (sampleRate / minFrequency).floor());
    if (maxTau <= minTau) return const NccfResult(confidence: 0);

    // 预计算整个信号的能量前缀和，用于 O(1) 取区域能量
    // prefixSq[k] = Σ_{i=0}^{k-1} samples[i]²
    final prefixSq = Float64List(n + 1);
    for (var i = 0; i < n; i++) {
      prefixSq[i + 1] = prefixSq[i] + samples[i] * samples[i];
    }

    // —— 第 1 步：计算所有候选 τ 的 NCCF ——
    // NCCF(τ) = Σ x[n]·x[n+τ] / sqrt(Σx²[n] · Σx²[n+τ])
    // 分子 r(τ) = Σ_{n=0}^{N-τ-1} x[n]·x[n+τ]   （naive O(N²) 内层循环）
    // 分母 sqrt(e1 · e2)，其中
    //   e1 = Σ_{n=0}^{N-τ-1} x²[n]   = prefixSq[N-τ]
    //   e2 = Σ_{n=0}^{N-τ-1} x²[n+τ] = prefixSq[N] - prefixSq[τ]
    final nccf = Float64List(maxTau + 1);
    var globalMax = 0.0;
    for (var tau = minTau; tau <= maxTau; tau++) {
      double r = 0;
      final windowLen = n - tau;
      for (var j = 0; j < windowLen; j++) {
        r += samples[j] * samples[j + tau];
      }
      final e1 = prefixSq[n - tau];
      final e2 = prefixSq[n] - prefixSq[tau];
      final denom = e1 * e2;
      if (denom <= 0) {
        nccf[tau] = 0;
        continue;
      }
      final val = r / math.sqrt(denom);
      nccf[tau] = val;
      if (val > globalMax) globalMax = val;
    }

    // 第 2 步：峰值选择策略（双重防护，避免两个方向的错误）
    //
    // 【防护 1】maxFrequency=600 已排除高次泛音（787/1053/1297Hz 等），
    //   真实麦克风信号的高泛音不再进入搜索范围。
    //
    // 【防护 2】在剩余的基频范围内，用"第一个显著峰"而非"全局最大峰"。
    //   原因：带谐波的信号在基频的 2 倍周期处（更低八度的 τ）NCCF 同样
    //   接近 1.0，选最大峰会系统性偏低八度（实测 C4→130、E4→109、G4→196）。
    //   基频对应最小 τ，是范围内首个显著峰。
    //
    // 阈值：全局最大值的 85%（相对），且绝对下限 0.5（过滤纯噪声/弱泛音峰）。
    // 之前 0.4/0.8 太松，真实信号的弱泛音峰会误入。拨弦稳态段 NCCF 通常 > 0.8。
    final threshold = math.max(0.5, globalMax * 0.85);
    var bestTau = 0;
    for (var tau = minTau + 1; tau < maxTau; tau++) {
      if (nccf[tau] >= threshold &&
          nccf[tau] >= nccf[tau - 1] &&
          nccf[tau] > nccf[tau + 1]) {
        bestTau = tau;
        break;
      }
    }

    if (bestTau == 0) {
      return NccfResult(frequency: null, confidence: globalMax);
    }

    // —— 第 4 步：抛物线插值精确定位峰值 ——
    // 在 bestTau 邻域 (τ-1, τ, τ+1)（NCCF 值 a, b, c）上拟合抛物线：
    //   偏移 x0 = 0.5·(a-c)/(a-2b+c)
    //   精确 τ = τ + x0
    final a = nccf[bestTau - 1];
    final b = nccf[bestTau];
    final c = nccf[bestTau + 1];
    double betterTau = bestTau.toDouble();
    final denom = a - 2 * b + c;
    if (denom.abs() > 1e-9) {
      final x0 = 0.5 * (a - c) / denom;
      // 限制插值偏移在 [-1, 1] 避免外推失真
      if (x0.abs() <= 1.0) {
        betterTau = bestTau + x0;
      }
    }

    final frequency = sampleRate / betterTau;
    return NccfResult(frequency: frequency, confidence: b);
  }

  /// 信号预处理 pipeline（业界标准，让真实麦克风信号在自相关前更干净）。
  /// 1. DC 去除：减去样本均值，去直流偏移（麦克风常有 DC 漂移）
  /// 2. 一阶高通/预强调：y[n] = x[n] - 0.97·x[n-1]
  ///    - 抑制电扇等低频噪声（50-200Hz）
  ///    - 强化高频基频边缘（让基频峰更突出）
  /// 3. 中心削波：阈值 = 0.3 × max(|x|)，绝对值低于阈值的样本置 0
  ///    - 保留强周期成分，抑制低幅谐波串扰和噪声
  ///    - 让基频对应的自相关峰更尖锐，减少误锁泛音
  Float32List _preprocess(Float32List input) {
    final n = input.length;
    final out = Float32List(n);

    // 1. DC 去除
    double mean = 0;
    for (var i = 0; i < n; i++) {
      mean += input[i];
    }
    mean /= n;

    // 2. 一阶高通/预强调（DC 去除 + 高通合并：先去 DC，再做预强调）
    for (var i = 0; i < n; i++) {
      final dcRemoved = input[i] - mean;
      if (i == 0) {
        out[i] = dcRemoved;
      } else {
        out[i] = dcRemoved - 0.97 * (input[i - 1] - mean);
      }
    }

    // 3. 中心削波：找最大绝对值，阈值 = 0.3 × max
    double maxAbs = 0;
    for (var i = 0; i < n; i++) {
      final abs = out[i].abs();
      if (abs > maxAbs) maxAbs = abs;
    }
    final clipLevel = maxAbs * 0.3;
    if (clipLevel > 0) {
      for (var i = 0; i < n; i++) {
        if (out[i].abs() < clipLevel) {
          out[i] = 0;
        }
      }
    }

    return out;
  }
}
