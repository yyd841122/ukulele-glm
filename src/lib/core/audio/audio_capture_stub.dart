/// 音频采集 - 占位（默认分支，不应被执行）
library;

import 'audio_capture.dart';

AudioCapturer createAudioCapturerImpl() =>
    throw UnsupportedError('当前平台不支持音频采集');
