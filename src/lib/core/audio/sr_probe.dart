/// 采样率探测（条件导入接口）
library;

import 'sr_probe_stub.dart'
    if (dart.library.js_interop) 'sr_probe_web.dart'
    if (dart.library.io) 'sr_probe_io.dart';

/// 探测真实采样率（Web 上读 AudioContext.sampleRate）
int detectActualSampleRate(int fallback) => detectSampleRateImpl(fallback);
