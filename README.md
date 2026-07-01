# 🎸 尤克里里 AI 学园 — 智能规划 Agent 平台

> **本仓库是一个「智能规划中枢」，由 AI Agent 驱动，负责把一份 PRD 逐步落地为一款可上线的 App。**
>
> 它不是普通的代码仓库，而是一套**「阶段 → 任务 → 产出」的可执行开发治理体系**：所有开发动作都从这里被规划、追踪、归档。

---

## 🎯 平台使命

把 `PRD.md` 中描述的「尤克里里 AI 互动学习 App」，通过**分阶段、可追踪、AI 辅助**的方式，从 0 到 1 实现并上线。

对标产品：**AI 音乐学园**（iMMmusician）。我们的差异化：**垂直尤克里里深度 + 低门槛 + 更优的实时反馈体验**。

---

## 📐 平台核心理念

```
┌──────────────────────────────────────────────────────────┐
│   PRD（做什么）                                          │
│     ↓ 拆解                                               │
│   智能规划平台（本仓库，怎么管 / 做到哪）               │
│     ↓ 驱动                                               │
│   技术方案 TDD（怎么实现）→ 原型（长什么样）→ 代码       │
└──────────────────────────────────────────────────────────┘
```

平台坚持三原则：
1. **文档先行**——任何代码前，先有方案、有原型、有验收标准；
2. **小步快跑**——按 MVP → V1 → V2 交付，每个阶段都可独立验收；
3. **决策可回溯**——所有技术选型、设计取舍都记录在档，附理由与备选。

---

## 🗂️ 仓库结构（开发地图）

```
ukulele/
├── README.md                  ← 你在这里：平台总控 & 导航
├── PRD.md                     ← 产品需求总纲（已产出）
├── docs/                      ← 所有规划与技术文档
│   ├── TDD.md                 ← 技术方案设计（v2.0：NCCF+AudioWorklet + §3.7 整曲节奏模式）
│   ├── ROADMAP.md             ← 开发路线图（Phase 2 进行中）
│   ├── TASKBOARD.md           ← 任务看板（可追踪进度）
│   ├── DESIGN-SPEC.md         ← UI/UX 设计规范
│   ├── MONETIZATION.md        ← 💰 商业化与会员体系设计（档位/权益/支付/订单）
│   ├── DATA-SCHEMA.md         ← 曲谱/课程数据结构规范（待补）
│   └── DECISIONS/             ← 关键技术决策记录（ADR）
│       ├── ADR-001-pitch-detection.md    ← 乐音识别选 YIN（已被 ADR-003 取代）
│       └── ADR-002-monetization.md       ← 商业化 Feature Gate 架构预留
├── prototype/                 ← 高保真可交互原型（HTML）
│   └── index.html
├── .agent/                    ← Agent 协作配置（任务模板等）
└── src/                       ← App 源码（Flutter）
```

---

## 📍 当前进度（截至 2026-07-01）

| 里程碑 | 状态 | 产出 |
|--------|------|------|
| ✅ PRD 产品需求 | **完成** | `PRD.md`（v1.1 含整曲弹唱需求） |
| ✅ 规划平台搭建 | **完成** | 本 README、TDD、ROADMAP、TASKBOARD |
| ✅ 技术方案设计 | **完成** | `docs/TDD.md` v2.0（NCCF + AudioWorklet + 整曲节奏模式） |
| ✅ 高保真原型 | **完成** | `prototype/index.html`（6 屏可交互） |
| ✅ **Phase 1 MVP** | **完成** | 调音器/节拍器/和弦库/曲谱/跟弹评分/会员接口 |
| ✅ **音频引擎 v2.0** | **完成** | NCCF + AudioWorklet 直采 + 预处理流水线（替换 YIN/record） |
| ✅ Android APK | **完成** | 真机验证：调音器/跟弹/和弦识别正常 |
| 🔨 **Phase 2** | **进行中** | 游戏化✅ 节奏✅ 和弦转换✅ 互动课程✅ 整曲节奏模式（流水滚动 UI 开发中） |

> 已实现：调音器（NCCF 实时识别）、节拍器、和弦库（自绘指法图）、曲谱库、
> 跟弹评分（单音+和弦+冷却期防误触）、Chroma 和弦识别、游戏化（EXP/等级/成就）、
> 整曲节奏模式（基础版：按节奏推进+配乐+双模式）、FeatureGate 会员接口+付费墙。

---

## 🚀 如何使用本平台

### 给「规划 Agent」（即我）的指令范式
当你说出以下任意一类需求时，我会按平台流程处理：

| 你的指令 | 我的动作 |
|---------|---------|
| "开始 MVP 开发" | 在 TASKBOARD 拉起 Phase 1 任务，逐个实现并更新状态 |
| "评估一下 XX 技术" | 调研 → 写 ADR 决策记录 → 更新 TDD |
| "加一个新功能/页面" | 评估优先级 → 更新 PRD/TASKBOARD → 出原型/方案 |
| "看看现在进度" | 读取 TASKBOARD 汇报 |

### 启动 MVP 的标准入口
```
打开 docs/TDD.md          → 确认技术栈与架构
打开 docs/ROADMAP.md      → 确认当前阶段目标
打开 docs/TASKBOARD.md    → 领取第一个「进行中」任务
```

---

## 🧭 关键技术决策速览（详见 TDD）

| 决策点 | 选定方案 | 一句话理由 |
|--------|---------|-----------|
| **移动端框架** | Flutter | 一套代码 iOS+Android，UI 与音频生态成熟 |
| **乐音识别（实时层）** | **NCCF + 信号预处理流水线**（v2.0） | YIN 实测八度误差不可消除；NCCF+预处理（DC去/高通/削波）+状态机对真实信号稳定 |
| **音频采集（Web）** | **AudioWorklet 直采**（v2.0） | record 包是采样率黑盒；AudioWorklet 直采采样率 100% 确定 |
| **音频采集（移动）** | record 包（条件导入） | 移动端 record 尊重请求采样率，无黑盒问题 |
| **和弦识别** | Chroma（FFT + 色度向量 + 模板匹配） | 扫弦多音场景，根音加权提高准确率 |
| **整曲节奏模式** | 配乐流水滚动 + 判定线（横屏） | 对标 AI 音乐学园；和弦版+单音版双范式 |
| **后端** | Node.js + Fastify / Python FastAPI | 内容服务 + 用户/进度同步 |
| **数据** | MySQL + Redis | 业务数据 + 排行榜/缓存 |
| **💰 商业化模式** | **永久会员 + 免费试用期**，安卓优先 | 工具型品类契合永久会员；试用拉转化 |
| **💰 权限架构** | **统一 FeatureGate 层 + MVP 预留会员模型** | MVP 即搭好权限中间件 |

> 详见 `docs/TDD.md` §3「乐音识别选型」、§3.7「整曲节奏模式」、§6.5「商业化架构」。

---

## 🛠️ 本地运行与构建（MVP App 源码在 `src/`）

```bash
cd src

# 1. 安装依赖
flutter pub get

# 2a. Web 端开发调试（推荐，麦克风可用、热重载快）
flutter run -d chrome
#   或构建后用本地服务跑（麦克风需 http/localhost 环境，file:// 不行）
flutter build web
cd build/web && python -m http.server 8080   # 访问 http://localhost:8080

# 2b. Android 真机/模拟器调试
flutter run -d <device-id>          # flutter devices 查看设备

# 3. 构建 Release APK（装手机）
flutter build apk --release
#   产物：build/app/outputs/flutter-apk/app-release.apk
```

### ⚠️ Android 构建环境注意事项（已踩过的坑）
- **Gradle 下载依赖 TLS 失败**：国内网络需在 `src/android/gradle.properties` 配 JVM 代理
  （`systemProp.https.proxyHost/Port`）+ `settings.gradle.kts`/`build.gradle.kts` 加阿里云镜像。
- **Kotlin 增量缓存 bug**：Kotlin 2.x BuildTools 写 `.tab` 缓存失败，已在 `gradle.properties`
  设 `kotlin.incremental=false` 规避。
- **`web` 包跨平台**：`tick_player` 用条件导入隔离 `dart:js_interop`/`web` 包，
  确保 Android 编译不引入 Web 专属库（改动 `tick_player*.dart` 时注意保持条件导入结构）。

---

## 📞 协作约定

- 文档变更须更新版本号与「变更记录」；
- 重大技术决策走 ADR（Architecture Decision Record）流程；
- 任务状态流转：`待办 → 进行中 → 已完成`（阻塞/取消单独标记）；
- 所有「已完成」任务须有可验收的产出（代码/文档/原型）。

---

*本平台由 AI 规划 Agent 维护，随开发推进持续演进。最近更新：2026-07-01。*
