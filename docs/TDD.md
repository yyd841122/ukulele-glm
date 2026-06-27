# TDD · 尤克里里 AI 学园 — 技术方案设计文档

> **文档版本**：v1.0  ｜  **创建**：2026-06-26
> **配套**：`PRD.md` §4 技术需求  ｜  **重点章节**：§3 乐音识别技术选型
> **状态**：方案已定，待 MVP 验证

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

### 3.3 决策结论：**YIN**

**为什么选 YIN？**
1. **延迟可控且可计算**：YIN 在时域做自相关，理论延迟 ≈ 2 × 最低检测频率的周期。对尤克里里最低 Low-G（G3≈196Hz，周期≈5.1ms），缓冲窗 1024~2048 samples（@44.1k 即 23~46ms）即可覆盖，**端到端 < 100ms 完全可达**。
2. **单乐器单声道场景精度足够**：尤克里里旋律/和弦根音识别是单音（monophonic）场景，YIN 表现优秀；调音时更是纯正单音，精度可达 ±1 cent 级。
3. **实现成熟、可移植**：YIN 有 TarsosDSP（Java）、pitch-detection（Rust）、pitch_detector_dart（Dart）、pitchfinder（JS，原型用）等多语言实现，移植/自研风险低。
4. **CPU 占用低**：时域算法，移动端实时跑无压力，省电。
5. **与节奏识别天然协同**：onset 检测也基于同一时域能量流，零额外采集成本。

**为什么不选 CREPE 做实时主算法？**
- CREPE 精度最高，但它是 6 层 CNN 在原始音频上推理，**移动端实时推理延迟通常 > 100ms 且耗电高**，违反延迟指标；
- 它更适合**离线/云端**对复杂弹唱（多音、和弦）做高精度评测兜底，作为 V2+ 能力。

**为什么不选纯 FFT 峰值法？**
- 尤克里里音色泛音丰富，FFT 峰值法极易把**泛音误判为基音**（八度错判），不可靠。

### 3.4 架构设计：三层音频引擎

```
┌─────────────────────────────────────────────────────────┐
│ L3  UI 反馈层  (Flutter/Dart)                            │
│     接收评分事件 → 渲染 ✓/✗/仪表盘/滚动谱               │
├─────────────────────────────────────────────────────────┤
│ L2  评分编排层  (Dart, 平台无关)                          │
│     ① 音高序列 → 与曲谱应弹音符对齐(时间窗) → 音准分     │
│     ② onset 时间戳 → 与节拍网格对齐 → 节奏分            │
│     ③ 平滑/去抖 → 输出事件流                            │
├─────────────────────────────────────────────────────────┤
│ L1  原生音频层  (iOS Swift / Android Kotlin) ← 关键      │
│     低延迟 PCM 采集 + YIN 实现 + Onset 检测              │
│     通过 Platform Channel / FFI 把事件回调给 Dart        │
└─────────────────────────────────────────────────────────┘
```

**为什么 L1 用原生而非纯 Dart？**
- `pitch_detector_dart` 等纯 Dart 包可用，但 Dart 层做音频缓冲易受 GC/事件循环抖动影响，**延迟与稳定性不如原生**；
- 我们的延迟指标严苛（<100ms），原生（Swift `AVAudioEngine` / Kotlin `AudioRecord`）可控性最高；
- **渐进策略**：先用 `flutter_pitch_detection`/`pitch_detector_plus` 快速跑通 MVP 原型，**性能不达标再下沉原生**。

### 3.5 关键参数（L1 原生层）

| 参数 | 取值 | 说明 |
|------|------|------|
| 采样率 | **44100 Hz**（或 48000） | 标准音频采样率 |
| 缓冲帧数 | **2048 samples（≈46ms@44.1k）** | 延迟与精度平衡点；可调 |
| 重叠 | 50% | 提升时间分辨率，平滑识别 |
| YIN 阈值 | 0.10 – 0.15 | 越低越严格，调音场景用低值 |
| 最小频率 | 70 Hz | 覆盖 Low-G 及降调余量 |
| 最大频率 | 1200 Hz | 覆盖到 C6 |
| Onset 算法 | 基于光谱通量(spectral flux) | 检测弹奏起音 |

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

### 3.7 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 实时延迟超标 | L1 原生实现；缓冲参数可调；先 Dart 验证再下沉 |
| 环境噪声干扰 | 首次使用做"输入校准"；加噪声门限(noise gate) |
| 和弦(多音)识别不准 | MVP 仅评单音旋律/和弦根音；多音评测走云端 CREPE（后期） |
| iOS/Android 原生实现差异大 | 定义统一 Platform Channel 接口，两端各自实现 |
| 低频(Low-G)延迟偏大 | 缓冲窗按最低频率设定；提示用户 High-G 配置体验更佳 |

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

---

## 附：参考资料

- YIN 原始论文：de Cheveigné & Kawahara (2002), "YIN, a fundamental frequency estimator for speech and music"
- CREPE：[Kim et al., ICASSP 2018](https://www.justinsalamon.com/uploads/4/3/9/4/4394963/kim_crepe_icassp_2018.pdf)
- 算法基准：[lars76/pitch-benchmark](https://github.com/lars76/pitch-benchmark)
- Flutter 插件：[flutter_pitch_detection](https://pub.dev/packages/flutter_pitch_detection)、[pitch_detector_plus](https://pub.dev/packages/pitch_detector_plus)
- 低延迟讨论：[JUCE Forum](https://forum.juce.com/t/lowest-latency-real-time-pitch-detection/51741)
- 原型 JS 库：[pitchfinder (Peter Johnson)](https://github.com/peterkwagner/pitchfinder)
