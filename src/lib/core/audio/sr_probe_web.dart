/// 采样率探测 - Web 实现（读 AudioContext.sampleRate）
library;

import 'package:web/web.dart' as web;

int detectSampleRateImpl(int fallback) {
  try {
    final ctx = web.AudioContext();
    final sr = ctx.sampleRate.toInt();
    ctx.close();
    return sr > 0 ? sr : fallback;
  } catch (_) {
    return fallback;
  }
}
