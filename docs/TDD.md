# TDD · 尤克里里 AI 学园 — 技术方案设计文档

> **文档版本**：v2.0  ｜  **创建**：2026-06-26  ｜  **更新**：2026-07-01
> **配套**：`PRD.md` §4 技术需求  ｜  **重点章节**：§3 乐音识别技术选型、§3.7 整曲节奏模式
> **状态**：音频引擎 v2.0 已验证（NCCF + AudioWorklet），整曲节奏模式开发中

---

## 0. 文档目的与范围

本文档定义本 App 的**整体技术架构**与**关键技术选型**，为 MVP 及后续阶段的开发提供技术蓝本。
重点且最优先攻克的难点是 **§3 实时乐音识别（Pitch Detection）** —— 它是整个产品的技术心脏，直接决定体验上限。

阅读对象：开发实现者（AI Agent / 人类工程师）、技术评审。

---

## 1. 系统总体架构

### 1.1 分层架构

```
┌─────────────────────────────────────────────────────────┐
│                   表现层 (Presentation)                  │
│   Flutter UI · 首页/学习/练琴/曲谱/我的                  │
├─────────────────────────────────────────────────────────┤
│  应用层 (Application)        │   音频引擎层 (Audio Core) │
│  · 状态管理(Riverpod)        │   · 音频采集(原生)        │
│  · 路由                      │   · YIN 音高识别          │
│  · 业务编排                  │   · Onset 节奏识别        │
├──────────────────────────────┴─────────────────────────┤
│   数据层 (Data)                                             │
│   本地: Isar(缓存·离线) · 远程: REST API                  │
├─────────────────────────────────────────────────────────┤
│   服务端 (Backend)                                          │
│   Node.js Fastify / Python FastAPI · MySQL · Redis · OSS │
└─────────────────────────────────────────────────────────┘
```

### 1.2 数据流（以"曲谱跟弹评分"为例）

```
麦克风 ──PCM流──► 音频采集(原生) ──buffer──► YIN识别器 ──音高f──► 评分器
                                                              │
                                                              ▼
曲谱数据(应弹音符序列) ──► 时间对齐器 ◄──Onset时间戳◄── 节奏识别
                              │
                              ▼
                    评分(音准+节奏) ──► UI 实时反馈(✓/✗/仪表盘)
```

---

## 2. 技术栈选型

| 层 | 选型 | 备选 | 理由 |
|----|------|------|------|
| 移动端 | **Flutter 3.x (Dart)** | React Native / 原生 | 跨平台一致 UI；音频插件生态可用；单代码库降本 |
| 状态管理 | **Riverpod 2** | Bloc / Provider | 类型安全、可测试、适合中大型 App |
| 本地存储 | **Isar** | Hive / SQLite | 高性能对象存储，离线缓存首选 |
| 音频采集 | **原生通道 + record 插件** | mic_stream | 需低延迟原始 PCM，原生最可控 |
| 音高识别 | **YIN（原生实现，必要时自研插件）** | pitch_detector_dart | 详见 §3 |
| 后端 | **Node.js + Fastify** | Python FastAPI | 高并发 IO、生态成熟；Python 留给后续 AI 模型 |
| 数据库 | **MySQL 8** | PostgreSQL | 业务数据稳定可靠 |
| 缓存 | **Redis** | — | 排行榜、会话、热数据 |
| 对象存储 | **阿里云 OSS / 七牛** | AWS S3 | 教学视频、音频、曲谱文件 |
| CI/CD | GitHub Actions + Fastlane | — | 自动构建发布 |

---

## 3. 乐音识别技术选型决策 ⭐（核心）

> 本节为整个项目**最关键的技术决策**。结论先行：**实时层采用 YIN 算法 + 原生音频采集**，高精度兜底层 CREPE/FCPE 后期上云。

### 3.1 需求指标（来自 PRD §4.1）

| 指标 | 目标值 | 约束来源 |
|------|--------|---------|
| 音高识别延迟 | **< 100ms** | 用户弹奏到看到反馈的体感门槛 |
| 音高精度 | **误差 < ±5 cents** | 调音器与评分可信度要求 |
| 支持频率范围 | **C3(130Hz) – C6(1047Hz)** | 尤克里里音域（含 Low-G 的 G3=196Hz 到 1弦 C6） |
| 环境鲁棒 | 普通室内、手机麦克风 | 真实使用场景 |
| 节拍对齐误差 | < 50ms | 节奏评分可信度 |

> ⚠️ 尤克里里特殊性：High-G 第 4 弦 G4 与第 1 弦 A4 是高音弦，但 **Low-G 配置下第 4 弦是 G3(196Hz)**，低频周期长，对 YIN 的最小延迟有直接影响（见 3.4）。

### 3.2 候选算法对比

基于权威基准（[lars76/pitch-benchmark](https://github.com/lars76/pitch-benchmark)）与多源资料：

| 算法 | 类型 | 延迟 | 精度 | 移动端适用性 | 成熟度 |
|------|------|------|------|------------|--------|
| **YIN** | 时域自相关 | 低（≈2×最低音周期） | 良（单音准） | ✅ 优秀 | ⭐⭐⭐⭐⭐ |
| **pYIN** | 概率 YIN | 略高 | 较高 | ✅ 良好 | ⭐⭐⭐⭐ |
| **CREPE** | 深度 CNN | 高（推理） | **最高** | ⚠️ 需量化优化 | ⭐⭐⭐ |
| **FCPE** | 轻量神经（深度可分离卷积） | 低 | 高 | ✅ 有潜力（较新） | ⭐⭐ |
| **Bitstream AC** | 1-bit 自相关 | 极低 | 中 | ✅ 优秀 | ⭐⭐⭐ |
| **OneBitPitch** | 超高速 | 极低 | 良 | ✅ 优秀 | ⭐⭐ |
| **FFT 峰值** | 频域 | 中 | 差（泛音误判） | ✅ 但不可靠 | ⭐⭐ |

### 3.3 决策结论：~~YIN~~ → **NCCF + AudioWorklet 直采**（v2.0 架构升级）

> **⚠️ 架构变更（2026-07-01）**：初版选用 YIN，但实测在真实麦克风信号上存在严重不稳定
>（采样率黑盒、泛音锁定、瞬态失败）。经多轮调研验证后，改为 **NCCF（归一化自相关）
> + 信号预处理流水线 + AudioWorklet 直采**方案。详见 [ADR-003](DECISIONS/ADR-003-nccf-audioworklet.md)。

**为什么从 YIN 改为 NCCF + 预处理流水线？**
1. **YIN 的八度误差**：YIN 在尤克里里真实信号上系统性偏八度（G 弦识别成 F#），且频率偏移无法消除。
2. **record 包采样率黑盒**：record 包在 Web 上自管 AudioContext，外部探测的采样率和实际数据采样率对不上，导致频率系统性偏移。**根本解法是 Web 端抛弃 record 包，用 AudioWorklet 直采**。
3. **NCCF + 预处理更鲁棒**：NCCF（归一化自相关）配合业界标准预处理（DC去除+高通+中心削波）+ 后处理（RMS门限+状态机+中值平滑），对真实麦克风信号稳定可靠。

**新算法的关键参数**：NCCF maxFrequency=600Hz（排除泛音）、confidence 阈值 0.5、RMS 门限 0.01、attack/stable/release 状态机。

**为什么不选 CREPE / 纯 FFT？**
- CREPE 精度最高但移动端实时推理延迟 > 100ms，留作 V2 云端兜底。
- 纯 FFT 峰值法对泛音丰富的尤克里里极易八度错判。

### 3.4 架构设计：音频引擎（v2.0 重写版）

```
┌─────────────────────────────────────────────────────────┐
│ L3  UI 反馈层  (Flutter/Dart)                            │
│     调音器/跟弹/和弦转换/整曲 → 渲染反馈                  │
├─────────────────────────────────────────────────────────┤
│ L2  评分编排层  (Dart, 平台无关)                          │
│     PitchDetectionService:                               │
│       ① RMS 门限过滤（电扇等噪声）                        │
│       ② NCCF confidence 过滤                             │
│       ③ attack/stable/release 状态机（瞬态兜底）          │
│       ④ 3 帧中值平滑（抑制跳变）                          │
│     ScoringEngine: 单音/和弦匹配 + 冷却期                 │
├─────────────────────────────────────────────────────────┤
│ L1b 音高检测  (纯 Dart, 跨平台)                           │
│     NccfDetector:                                        │
│       预处理(DC去+高通+削波) → NCCF → 第一个显著峰        │
│       → 抛物线插值 → frequency + confidence               │
├─────────────────────────────────────────────────────────┤
│ L1a 音频采集  (条件导入, 平台分流)                        │
│     Web: AudioWorklet 直采 (pitch_worklet.js)             │
│           → AudioContext.sampleRate 为采样率真值           │
│     移动: record 包 (hasPermission + startStream)         │
└─────────────────────────────────────────────────────────┘
```

**为什么 L1a Web 端用 AudioWorklet 而非 record 包？**
- record 包在 Web 上是采样率黑盒（自管 AudioContext + 内部重采样），外部永远拿不到真实采样率；
- AudioWorklet 直采：自己控制 AudioContext，sampleRate 100% 确定，采样率不再需要探测。

**为什么 L1b 用纯 Dart NCCF 而非原生？**
- 实测 Dart 层 NCCF + 预处理每帧约 3-5ms，满足 <100ms 延迟指标；
- 纯 Dart 跨平台一致（Web/Android/iOS 行为相同），无需维护三套原生代码。

### 3.5 关键参数

| 参数 | 取值 | 说明 |
|------|------|------|
| 采样率 | Web: AudioContext.sampleRate（通常 48000）；移动: 44100 | 采集层提供真值，不再探测 |
| 缓冲帧数 | **2048 samples** | 延迟与精度平衡点 |
| 重叠 | 50% | 提升时间分辨率，平滑识别 |
| NCCF maxFrequency | **600 Hz** | 排除高次泛音（尤克里里基频 < 523Hz） |
| NCCF confidence 阈值 | **0.5** | 过滤低质量检测（噪声 < 0.5） |
| RMS 门限 | **0.01** | 过滤电扇等环境噪声（拨弦 > 0.03） |
| 状态机 | attack/stable/release | 拨弦瞬态用上一稳定值兜底 |
| 中值平滑窗口 | 3 帧 | 抑制单帧跳变 |

### 3.6 评分模型（L2）

**音准分**：在某个音符的时间窗 [t_start, t_end] 内，统计识别到的基频 f 与应弹音符标准频率 f0 的 cents 偏差分布：
```
cents = 1200 * log2(f / f0)
分值 = clip(100 - |平均cents| * k, 0, 100)   // k为缩放系数
```
- |cents| ≤ 5 → 满分区间；
- 超出半音(50 cents) → 0 分。

**节奏分**：识别到的 onset 时间点与曲谱节拍网格对齐度（误差 < 50ms 满分）。

**总分** = 加权（音准 0.6 + 节奏 0.4，权重可配置）。

### 3.7 整曲节奏模式（流水滚动跟弹）⭐ 新增

> 对标 AI 音乐学园核心体验：配乐按 BPM 流水滚动，按节奏走不停（不等用户）。
> 分**和弦伴奏版**和**单音旋律版**两种 UI 范式，均横屏。

#### 3.7.1 核心理念

从"弹对才走"（逐音等待）→ "按节奏流水走动"（节奏驱动）：
- 配乐按 BPM 自动播放和弦/旋律序列
- 歌词+曲谱+指法图按节奏从右向左滚动（判定线固定在屏幕中央）
- 在每个和弦/音符的时间窗口内实时判定用户弹的对错
- 弹对→变绿，弹错→标红，没弹到→标灰，但传送带不停

#### 3.7.2 两种 UI 范式

**和弦伴奏版（路线 A：和弦谱滚动）**
```
横屏 ← 滚动方向（从右向左）←

         判定线
           ↓
  C          G          Am         F
 [指法图]  [指法图]   [指法图]  [指法图]   ← 第1行：指法图（小，40×40）
 一闪一闪   亮晶晶     满天      都是      ← 第2行：歌词
```
- 和弦名 + 指法图 + 歌词三层垂直对齐，同步滚动
- 到达判定线时高亮 + 配乐提示
- 判定走 Chroma 和弦识别

**单音旋律版（路线 B：四线谱 TAB 滚动）**
```
横屏 ← 音符从右向左滚 ←

  A弦 ──────3──────0──────────2─────  ← 数字=按第几品
  E弦 ──────────────────1───────0────
  C弦 ────0──────2───────────────────
  G弦 ───────────────0───────────────
                     ↑ 判定线
```
- 4 条弦各一行（G/C/E/A 四色），数字标注品数
- 到达判定线时弹对应音
- 判定走 NCCF 单音识别（音名匹配，不要求精确弦+品）

#### 3.7.3 数据结构（时间轴驱动）

```dart
class PracticeChord {
  final String name;       // 和弦名
  final int position;      // 歌词字符位置
  final int beats;         // 持续拍数（节奏驱动核心）
}
class PracticeNote {
  final String name;       // 音名
  final int octave;
  final int beats;         // 持续拍数
}
class PracticeSong {
  final int bpm;           // 建议速度
  final List<PracticeLyric> lyrics;
  final Map<String, List<int>> chordFrets;  // 和弦→指法[G,C,E,A]
}
```

#### 3.7.4 节奏引擎（PracticeSongTracker）

- 启动时按 BPM 累加每个和弦/音符的时间点（`beats × 60000/bpm`）
- `Timer.periodic`（每拍）驱动"当前指针"前进，同时播放配乐
- 麦克风并行识别：每个时间窗口内匹配→标 correct，窗口结束未匹配→标 skip
- 配乐用 tone_player（拨弦音色），音量可控，可开关

#### 3.7.5 BPM 可调

用户可在开始前调速度（慢速 50 → 原速 80 → 快速 120），适配不同水平。

#### 3.7.6 横屏锁定

进入整曲模式时 `SystemChrome.setPreferredOrientations([landscape])`，退出时恢复。

### 3.8 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 配乐声被麦克风收到 | 建议戴耳机；配乐默认低音量可开关 |
| 滚动性能 | AnimationController + 只渲染屏幕内音符（虚拟化） |
| 四线谱绘制复杂 | CustomPaint 或 4 Row 叠加，数字用 Text Widget |
| 环境噪声干扰 | RMS 门限 + NCCF confidence 过滤 |
| 和弦(多音)识别不准 | Chroma 模板匹配 + 根音加权 |

### 3.8 验证计划（MVP 前置 PoC）

**第一步：浏览器 PoC（本次原型已实现）**
- 用 Web Audio API + `pitchfinder`(JS YIN) 在浏览器实时识别尤克里里音高，验证「算法可行、反馈直观」。

**第二步：Flutter PoC（MVP 启动前）**
1. Flutter + `pitch_detector_plus`/`flutter_pitch_detection`，麦克风实时显示音高与 cents 偏差；
2. 用真实尤克里里测试 4 根空弦（G/C/E/A），记录延迟与精度；
3. **通过标准**：4 弦识别正确率 > 95%，端到端延迟体感 < 150ms（先放宽，后续优化）；
4. 不通过 → 下沉原生 YIN。

> 详见 `docs/DECISIONS/ADR-001-pitch-detection.md`。

---

## 4. 数据模型概要

> 完整 Schema 见 `docs/DATA-SCHEMA.md`（待补）。此处列核心实体，分为**业务域**与**商业化域**（§4.2）。会员/支付相关模型**在 MVP 阶段即建表预留**，确保 Phase 3 接支付时无需回溯改库。

### 4.1 业务域实体

| 实体 | 关键字段 | 说明 |
|------|---------|------|
| User | id, phone, nickname, level, exp, created_at | 用户 |
| Course | id, type(必修/选修/Pro), title, level, lessons[] | 课程 |
| Lesson | id, course_id, order, video_url, segments[] | 课程章节（含互动分段） |
| Segment | id, lesson_id, start, end, target_notes[], scoring_points | 互动教学分段+评分点 |
| Song | id, title, artist, difficulty, key, bpm, sections[] | 曲谱曲目 |
| Section | id, song_id, lyrics, chords[], rhythm_pattern | 曲谱段落 |
| PracticeLog | id, user_id, type, target_id, score, duration, created_at | 练习记录 |
| Achievement | id, user_id, type, unlocked_at | 成就 |

### 4.2 商业化域实体（会员/订阅/订单）⭐预留

> 对应 `docs/MONETIZATION.md`。即使 MVP 不售卖，这些表与字段也提前建好，业务代码统一走权益校验中间件（见 §9），避免后期重构。

| 实体 | 关键字段 | 说明 |
|------|---------|------|
| **Entitlement（权益）** | id, user_id, **tier**(枚举:FREE/TRIAL/LIFETIME/VIP_ALL), source(注册赠送/购买/退款回收), order_id, granted_at, expires_at(可空,永久=null), status(active/revoked), revoked_at | 用户当前持有的权益；一个用户可有多条（取最高档生效，见 §9.2） |
| **SKU（商品）** | id, code(如 `ukulele_lifetime`), tier_granted(购买后授予的档位), name, price_cents, currency, channel[], active, display_order | 可售卖商品；`channel[]` 标记支持的支付渠道 |
| **Order（订单）** | id, user_id, sku_id, channel(wechat/alipay/huawei/xiaomi...), channel_order_id, amount_cents, **status**(CREATED/PENDING/PAID/FULFILLED/FAILED/CANCELLED/REFUNDING/REFUNDED), created_at, paid_at, fulfilled_at, refunded_at | 订单全生命周期；状态机见 MONETIZATION §4.3 |
| **TrialGrant（试用发放记录）** | id, user_id, device_fingerprint, phone, granted_at, expires_at | 防重复领取试用（设备+手机号唯一） |
| **UsageQuota（用量配额）** | id, user_id, feature_key(如 `follow_score`), period(如 `2026-06-26`), used, limit | 免费用户限额功能（如每日评分 3 次）的计数 |
| **PaywallEvent（付费墙事件）** | id, user_id, feature, trigger_feature, action(shown/dismissed), created_at | 商业化埋点，用于转化分析 |

**关键枚举固化**：
- `Tier`：`FREE | TRIAL | LIFETIME | VIP_ALL`（只追加不删改）
- `OrderStatus`：见上表，状态机驱动
- `PaymentChannel`：`WECHAT | ALIPAY | HUAWEI | XIAOMI | OPPO | VIVO | TENCENT | APPLE_IAP`

---

---

## 5. 平台与兼容性

| 项 | 要求 |
|----|------|
| iOS | 13.0+ |
| Android | 8.0 (API 26)+ |
| 最小屏幕 | 360×640（小屏适配） |
| 权限 | 麦克风(RECORD_AUDIO)、通知、存储(可选) |
| 网络 | 核心练习功能离线可用；内容/同步需联网 |

---

## 6. 安全与合规

- **麦克风权限**：明确告知用途（乐音识别），仅在前台使用，不录音上传（除非用户主动评测上传）；
- **数据加密**：HTTPS 传输、敏感字段加密存储；
- **隐私合规**：遵循《个人信息保护法》，提供隐私政策与数据导出/删除入口；
- **内容版权**：曲谱/歌词优先公有领域或获授权；UGC 上传须版权审核。

---

## 6.5 商业化架构（会员 / Feature Gate / 付费墙）⭐

> 本节为后期会员商用功能的**架构预留**。完整业务设计见 `docs/MONETIZATION.md`，决策依据见 `docs/DECISIONS/ADR-002`。
> **核心目标**：Phase 1（MVP）即把权益模型与权限控制架构搭好（成本极低、功能暂全免费），Phase 3 接支付渠道时无需重构业务代码。

### 6.5.1 架构分层

```
┌─────────────────────────────────────────────────────────┐
│  各功能页面 (曲谱/课程/评分/工具...)                      │
│  调用统一的 FeatureGate.check(featureKey) 判断权限        │
├─────────────────────────────────────────────────────────┤
│  FeatureGate 权限控制层（客户端 SDK + 后端校验）          │
│   · 查本地权益缓存(EntitlementCache, TTL 1h)             │
│   · 按权益矩阵(MONETIZATION §2)判定: 放行/限额/弹付费墙   │
│   · 命中付费墙 → 弹 PaywallSheet(统一组件)               │
├─────────────────────────────────────────────────────────┤
│  EntitlementService 权益服务                              │
│   · 客户端: 缓存 + 过期回源 /entitlements/check           │
│   · 后端:   取用户最高档权益(就高原则) + 限额计数         │
├─────────────────────────────────────────────────────────┤
│  数据层: Entitlement / Order / SKU / UsageQuota (§4.2)   │
└─────────────────────────────────────────────────────────┘
```

### 6.5.2 FeatureGate 统一接入点（关键约定）

**所有受权益控制的功能，禁止在页面里硬编码 `if(isMember)`，必须走统一的 `FeatureGate` 接口**。这样付费墙规则集中管理，调整档位/限额时只改一处配置。

```dart
// 统一权限检查接口（伪代码）
final result = await FeatureGate.check(FeatureKey.followScore);
// result = AccessResult
//   · Granted            → 放行
//   · GrantedWithQuota(used, limit) → 限额内放行（免费每日N次）
//   · Locked(paywallReason) → 弹付费墙

sealed class AccessResult {}
class Granted extends AccessResult {}
class GrantedWithQuota extends AccessResult { final int used; final int limit; }
class Locked extends AccessResult { final PaywallReason reason; }
```

**FeatureKey 枚举**（与 MONETIZATION §2 权益矩阵一一对应）：
`tuner_basic` / `metronome_basic` / `chord_library_basic` / `chord_library_advanced` / `song_beginner` / `song_advanced` / `follow_score` / `course_basic` / `course_full` / `leaderboard` / `cloud_sync` ...

### 6.5.3 权益就高原则与生效档位
用户可同时持有多个权益（如 TRIAL + LIFETIME）。后端 `/entitlements/check` 返回**生效档位 = 所有有效权益中优先级最高者**：
```
LIFETIME > VIP_ALL > TRIAL > FREE
```
客户端只消费「生效档位」+「限额计数」，不关心权益来源。

### 6.5.4 付费墙（PaywallSheet）统一组件
- **单一组件**：全 App 只有一个付费墙组件，由 `Locked.reason` 驱动展示文案与 CTA；
- **接入点**：任何 `FeatureGate.check` 返回 `Locked` 时弹出；
- **CTA**：「开通永久会员 ¥XX」（安卓：商店内购 + 微信/支付宝两个入口）；
- **恢复购买**：付费墙内固定入口（防掉单）。

### 6.5.5 权益开通与校验流程（详见 MONETIZATION §5）
- **开通**：渠道回调 → 后端校验订单真实性 → 写入 Entitlement(tier=LIFETIME) → 订单 FULFILLED → 推送刷新；
- **校验**：本地缓存优先 → 过期回源 → 就高档生效 → 按矩阵判定；
- **限额**（如评分每日3次）：计数在后端 `UsageQuota`，客户端展示余额；
- **防掉单**：定时对账未 FULFILLED 订单 + 「恢复购买」入口。

### 6.5.6 分阶段实施
| 阶段 | 动作 |
|------|------|
| **Phase 1 MVP** | 建 §4.2 全部表；实现 `FeatureGate` 接口与权益缓存；**功能暂全放行**（配置为免费可用），埋点 `paywall_shown` |
| **Phase 2 V1** | 试用期上线（注册赠 7 天）；免费限额生效（如评分每日3次）；付费墙 UI 接入 |
| **Phase 3 V2** | 接安卓商店内购 + 微信/支付宝直连；订单系统；永久会员售卖；恢复购买 |
| **Phase 4 远期** | iOS + IAP；全品类 VIP；单内容付费 |

> **关键设计保证**：因 Phase 1 已统一走 `FeatureGate`，Phase 3 只需把原本"全放行"的配置改为"按权益矩阵判定 + 接支付"，业务页面代码零改动。

---

## 7. 性能与质量目标

| 指标 | 目标 |
|------|------|
| 冷启动 | < 3s |
| UI 帧率 | 60fps（曲谱滚动） |
| 音频端到端延迟 | < 100ms（目标）/ < 150ms（MVP 可接受） |
| 崩溃率 | < 0.1% |
| 音高识别准确率 | > 90%（标准环境单音） |

---

## 8. 变更记录

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-26 | 初版；确定 Flutter + YIN 架构与三层音频引擎 |
| v2.0 | 2026-07-01 | **音频引擎重写**：YIN→NCCF+预处理流水线；record→AudioWorklet 直采（Web）；新增 §3.7 整曲节奏模式（流水滚动跟弹）；更新 §3.3-3.6 架构与参数 |

---

## 附：参考资料

- YIN 原始论文：de Cheveigné & Kawahara (2002), "YIN, a fundamental frequency estimator for speech and music"
- CREPE：[Kim et al., ICASSP 2018](https://www.justinsalamon.com/uploads/4/3/9/4/4394963/kim_crepe_icassp_2018.pdf)
- 算法基准：[lars76/pitch-benchmark](https://github.com/lars76/pitch-benchmark)
- sevagh/pitch-detection (MPM/YIN 事实标准参考)：[GitHub](https://github.com/sevagh/pitch-detection)
- cwilso/PitchDetect (Web ACF2+)：[GitHub](https://github.com/cwilso/PitchDetect)
- 音高检测信号预处理（Rabiner 经典讲义）：[UCSB](https://web.ece.ucsb.edu/Faculty/Rabiner/ece259/)
- 节奏游戏 Note Highway 设计：[Giant Bomb](https://giantbomb.com/wiki/Concepts/Note_Highway)
- Yousician 虚拟指板视图：[yousician.com](https://yousician.com/blog/guitar-fretboard-learning-guide)
- 尤克里里 TAB 谱读法：[liveukulele.com](https://liveukulele.com/tabs/how-to-read-tab/)
- 低延迟讨论：[JUCE Forum](https://forum.juce.com/t/lowest-latency-real-time-pitch-detection/51741)
- 原型 JS 库：[pitchfinder (Peter Johnson)](https://github.com/peterkwagner/pitchfinder)
