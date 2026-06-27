# ADR-001：乐音识别（Pitch Detection）算法选型 — 采用 YIN

> **状态**：已接受（Accepted）
> **日期**：2026-06-26
> **决策者**：技术方案评审（AI 规划 Agent 起草）
> **关联**：`PRD.md` §4.1、`docs/TDD.md` §3

---

## 1. 背景（Context）

本 App 的核心体验是「**AI 实时听你弹琴并纠错评分**」，乐音识别是其技术心脏。需在移动端（iOS/Android）实现**实时、低延迟、单乐器单声道**的音高与节奏识别：

- **延迟** < 100ms（弹奏→看到反馈的体感门槛）；
- **精度** 误差 < ±5 cents（调音器与评分可信度）；
- **频率范围** C3(130Hz) – C6(1047Hz)，覆盖尤克里里音域（含 Low-G 的 G3=196Hz）；
- **环境** 普通室内、手机麦克风；
- 同时需识别节奏（onset），用于节奏评分。

候选算法包括：YIN、pYIN、CREPE、FCPE、Bitstream Autocorrelation、OneBitPitch、FFT 峰值法。

---

## 2. 决策（Decision）

**实时识别层主算法采用 YIN**（基于时域自相关）。
**节奏识别**采用基于光谱通量（spectral flux）的 onset 检测，与 YIN 共享同一音频流。
**高精度兜底**（复杂弹唱/和弦多音评测）后期引入 **CREPE/FCPE 云端推理**，不进入移动端实时链路。

实现路径（渐进）：
1. **原型阶段**：浏览器用 `pitchfinder`（JS YIN）验证算法可行性与交互形式；
2. **MVP**：Flutter 端先用 `flutter_pitch_detection` / `pitch_detector_plus`（Dart/YIN）快速跑通；
3. **性能不达标则下沉**：用 iOS `AVAudioEngine` + Android `AudioRecord` 原生实现 YIN，经 Platform Channel 回调 Dart。

---

## 3. 理由（Rationale）

| 维度 | YIN 表现 |
|------|---------|
| 延迟 | 时域自相关，理论延迟 ≈ 2×最低音周期；尤克里里最低 Low-G 周期 ≈5ms，缓冲窗 1024–2048 samples（23–46ms@44.1k）即可，**端到端 <100ms 可达** |
| 精度 | 单音（monophonic）场景精度优秀，调音可达 ±1 cent 级；尤克里里旋律/和弦根音属单音场景 |
| 资源 | 时域算法，CPU/功耗低，移动端实时友好 |
| 成熟度 | TarsosDSP(Java)、pitch-detection(Rust)、pitch_detector_dart(Dart)、pitchfinder(JS) 多语言实现，移植/自研风险低 |
| 协同 | onset 检测复用同一路时域能量流，零额外采集成本 |

**为何不选 CREPE（实时）**：6 层 CNN 在原始音频上推理，移动端实时延迟通常 >100ms 且耗电高，违反延迟指标；适合云端离线高精度兜底。
**为何不选 FFT 峰值法**：尤克里里泛音丰富，FFT 峰值易把泛音误判为基音（八度错判），不可靠。
**为何不选 FCPE/Bitstream/OneBitPitch 做主算法**：FCPE 较新生态待验证；Bitstream/OneBitPitch 精度略逊且资料较少，留作后续优化备选。

---

## 4. 后果（Consequences）

### 优点
- 实时延迟与精度可同时满足，移动端实现路径清晰；
- 算法成熟、可移植，降低自研风险；
- 低功耗，利于后台/长时间练琴场景；
- 与节奏识别共享音频流，架构简洁。

### 缺点 / 代价
- **多音（和弦）识别能力有限**：YIN 主要针对单音基频；和弦根音可估，完整和弦音无法精确识别 → MVP 仅评单音旋律与和弦根音，完整和弦评测推迟到云端 CREPE。
- **低频延迟略大**：Low-G(G3) 周期比 High-G 长，缓冲窗需加大；提示用户 High-G 配置体验更佳。
- **需自研或移植原生实现**：若现成 Dart 插件性能不达标，需投入原生开发（iOS/Android 双端）。

### 风险缓解
- 原型阶段已用浏览器 YIN 验证算法可行；
- MVP 采用「先 Dart 插件，不达标再下沉原生」渐进策略；
- 定义统一 Platform Channel 接口，隔离两端实现差异；
- 首次使用做「输入校准」+ 噪声门限，提升环境鲁棒性。

---

## 5. 备选方案（Alternatives Considered）

| 方案 | 为何否决 |
|------|---------|
| CREPE（移动端实时） | 推理延迟 >100ms、耗电高 |
| 纯 FFT 峰值法 | 泛音误判、八度错判，不可靠 |
| FCPE | 生态新、移动端部署案例少 |
| Bitstream AC / OneBitPitch | 精度/资料不及 YIN，留作优化备选 |
| pYIN | 精度更高但延迟略增，可在云端评测层考虑 |

---

## 6. 复核触发条件（Revisit When）

- 当需要**和弦/多音实时评测**且云端方案体验不佳时，重新评估 FCPE/CREPE 移动端量化部署；
- 当出现延迟显著优于 YIN 且精度相当的新算法（如 OneBitPitch 成熟）时；
- 当业务扩展到**低音乐器**（如贝斯）使低频延迟成为瓶颈时。

---

## 7. 参考

- YIN 论文：de Cheveigné & Kawahara, 2002
- 算法基准：https://github.com/lars76/pitch-benchmark
- 实现参考：TarsosDSP、pitch-detection(Rust)、pitchfinder(JS)
- 详细对比见 `docs/TDD.md` §3
