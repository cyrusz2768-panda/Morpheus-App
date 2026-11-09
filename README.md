# 夜行者 / Morpheus

> 醒来，记下梦。

夜行者 / Morpheus 是一款面向 iOS 与 Android 的梦境记录应用。  
当前可按用户设定的时间发送本地提醒，记录梦境并通过月历回顾。应用坚持本地优先、隐私优先；智能手表睡眠数据、AI 梦境画报、周期报告与内容推荐属于后续规划。

App 名称待定，当前暂用“夜行者 / Morpheus”。

---

## 功能简介

### Version 0.1 核心功能

- **醒来提醒**
  - 已实现：设置每日定时提醒，无通知权限仍可记录梦境。
  - 已实现：首次使用通过带菜单图标的一次性引导介绍入口；首次进入通知设置时单独说明系统通知授权。
  - 规划中：有智能手表且授权时读取睡眠数据，验证醒来提醒是否可行。

- **梦境记录**
  - 快速进入当日记录窗口。
  - 支持自由文本输入、编辑、自动保存。
  - 后续可扩展字体大小、文本背景、样式等编辑能力。

- **日历回顾**
  - 通过日历选择日期。
  - 查看某天记录的梦境。
  - 支持补充记录、编辑已有记录。
  - 有记录的日期应有视觉标记。

### 规划中的进阶功能

- AI 梦境画报：根据梦境文本生成图像。
- 周期梦境回忆报告：按周 / 月分析情绪、意象、重复主题。
- 智能推荐：根据梦境情节、氛围、意象推荐电影、音乐、文学作品。
- 云同步与多设备。
- 更丰富的编辑器、标签、心情、插图与导出能力。

---

## 技术栈

| 层级 | 推荐选型 |
|---|---|
| 客户端 | Flutter + Dart |
| 状态管理 | Riverpod / Bloc |
| 路由 | go_router |
| 本地数据库 | Drift / SQLite |
| 通知 | flutter_local_notifications + timezone |
| 健康数据 | health 插件，封装 HealthKit / Health Connect |
| 日历 UI | Flutter 月历网格与内置日期选择器 |
| 安全存储 | flutter_secure_storage |
| 导出分享 | share_plus / pdf |
| 后端 | 进阶阶段：FastAPI + PostgreSQL + Redis |
| AI | LLM + 图像生成 API |
| 推荐 API | TMDB、Spotify、Open Library 等 |
| 版本控制 | Git + GitHub / GitLab |
| CI/CD | GitHub Actions + Fastlane |

技术原则：

- 本地优先，离线可用。
- 外部服务可插拔，AI 功能后置。
- 健康数据优先使用系统统一接口。
- 通知优先本地通知，后台限制严格时再考虑服务端推送。

---

## 整体架构

```text
UI / 界面层
  显示界面、接收输入、展示状态

核心逻辑层
  健康数据同步、醒来时间判断、通知调度、
  梦境记录 CRUD、日历聚合、AI 调用

数据层
  本地数据库、文件存储、安全存储、远程 API

外部服务 / API
  HealthKit / Health Connect、APNs / FCM、
  LLM、图像生成、推荐服务
```

---

## 当前状态

项目处于 **Version 0.1 开发阶段**。M1 基础功能与双平台模拟器基础验收已完成，干净克隆的双端完整复现记录仍待补齐；M2 历史/月历和 M3 本地提醒已实现，整个 Version 0.1 尚未完成。

新开发对话先读 [项目状态与交接](docs/PROJECT_STATUS.md) 和 [AGENTS.md](AGENTS.md)，历史过程见 [开发日志](docs/Log.md)。以这些文件与实际 Git 状态核对当前任务，不把旧日志中的 PR 流程当作现行规则。

### 当前已接入

- Flutter Android / iOS 工程骨架，Riverpod 状态管理与 go_router 路由。
- 按日期查看、补记和编辑梦境，800ms 防抖自动保存、清空后删除。
- 中文日期选择器、按梦境日期倒序的历史列表，以及一键回到今天。
- 首页 🔍 打开梦境搜索并自动聚焦键盘，支持本地正文关键词搜索、日期倒序结果与选日查看。
- 带记录圆点的梦境月历、月份切换、回到今天，以及日期点击查看/补记。
- Drift / SQLite 文件持久化、同日唯一、保存失败保留草稿并重试。
- 每日提醒设置、首次通知说明、权限查询与申请、测试通知、点击通知打开当天记录。
- 左上角菜单打开侧边抽屉，在“通知设置”中调整提醒；首次使用提供一次性入口引导。
- 自动化测试覆盖真实文件关闭重开、默认后台连接、切日草稿保护、历史页面、提醒配置与通知导航。

**验证边界：** Android 和 iOS 的基础记录、保存重开、日期选择和历史查看均已由开发者在模拟器中验收通过，用户也已确认每日提醒功能验收通过。2026-11-09 搜索更新通过 147 项测试、静态分析与格式检查；平台构建、iOS 启动及用户验收以 [项目状态](docs/PROJECT_STATUS.md) 的实际记录为准。CI 不执行原生双端构建。干净克隆双端逐项复现、真机锁屏/后台/重启等证据仍需补齐。数据库目前未加密，健康数据和 AI 尚未实现。

学习说明与操作步骤见 [M1 数据库接入说明](docs/M1_SQLITE_GUIDE.md)，目录职责见 [Flutter 工程说明](docs/FLUTTER_PROJECT_SKELETON.md)。原有需求、计划、许可证及开发日志继续保留。

日期选择、历史查询与本轮验收步骤见 [日期与历史功能说明](docs/DATE_HISTORY_GUIDE.md)。日期选择器通过 Flutter SDK 自带的 `flutter_localizations` 显示中文，无需额外日历插件。

🔍 搜索入口、匹配规则、数据流和验收步骤见 [梦境搜索说明](docs/SEARCH_GUIDE.md)。搜索在本地进行，沿用既有数据库，不保存搜索历史或上传正文。

右上角日历按钮现在打开带记录圆点的月历。实现逻辑和验收步骤见 [梦境月历说明](docs/CALENDAR_GUIDE.md)；沿用原数据库和编辑器，没有新增依赖。

每日提醒的语言、依赖、数据流和两端验收步骤见 [每日提醒说明](docs/REMINDERS_GUIDE.md)。提醒使用 `flutter_local_notifications`、`flutter_timezone` 和 `timezone`；设置保存于本地私有 JSON。Android 采用普通通知调度，节电时可能延迟。

Version 0.1 目标：

> 完成一个能够正常运行的版本，实现最核心的功能：  
> 醒来提醒 → 记录梦境 → 本地保存 → 日历查看 / 补记。

Version 0.1 暂不包含：

- 账号体系、云同步、社交功能。
- AI 画报、周期报告、推荐系统。
- 复杂编辑器、多端同步、付费系统。

---

当前界面文案、日期句式、读屏提示与通知文字已集中到 `lib/l10n/app_zh.arb`，Android / iOS 共用。现在仍仅交付中文，完整翻译与语言切换后续实施；新增功能须同时维护资源，生成和维护步骤见 [界面文案指南](docs/LOCALIZATION_GUIDE.md)。

## 快速开始

### 环境要求

- Flutter 3.44 或更新的兼容稳定版；本次验证使用 Flutter 3.47.7。
- Dart >=3.12 且 <4.0，由 Flutter SDK 自带。
- 安卓运行环境：Android Studio、Android SDK Platform 36、Build-Tools 36.0.0、NDK 28.2.13676358，以及安卓模拟器或设备。
- iOS 运行环境：仅在开发 iOS 时安装并配置完整 Xcode 及相应依赖；不要求先配好 iOS 才能开发安卓。
- 后续 HealthKit / Health Connect 与通知验证需要相应真机，不是当前自动化测试的前置条件。

### 克隆与运行

```bash
git clone https://github.com/cyrusz2768-panda/Morpheus-App.git
cd Morpheus-App
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter analyze
flutter test
flutter run
```

打开 VS Code 时选择整个 `Morpheus-App` 文件夹，即包含 `pubspec.yaml` 的工程根目录。Drift 的 `.g.dart` 按本仓库规范不提交，首次克隆、拉取数据库结构变更后必须先运行上面的代码生成命令；不要手改生成文件或手工建立数据库。

若 Flutter 卡在 GitHub 更新检查，可把 Flutter 命令改为 `flutter --no-version-check pub get`、`flutter --no-version-check test` 或 `flutter --no-version-check run`。这只跳过查新，不绕过依赖下载、许可证或构建错误。新增原生依赖后应停止旧 App 完整重建，不能只用 Hot Reload。

验收持久化：输入文字，等“已保存”后完整退出，在同一天、同一设备重开，正文应恢复。不要卸载、清除应用数据或使用模拟器 Wipe Data。详细步骤和故障边界见 [接入说明](docs/M1_SQLITE_GUIDE.md)。

### 权限配置

本地提醒权限已接入，健康数据权限为后续规划。拒绝通知权限时，仍可记录和查看梦境。

iOS：

- 本地通知通过运行时提示申请授权，`AppDelegate.swift` 配置通知代理。
- 后续使用 HealthKit 时，再添加健康数据权限说明并开启对应 Capability。

Android：

- `AndroidManifest.xml` 已声明通知权限和提醒重启恢复接收器；Android 13+ 在用户同意说明后动态申请。
- 后续使用 Health Connect 时，再按官方要求配置权限与隐私说明。

---

## 当前目录结构

```text
Morpheus-App/
├── AGENTS.md
├── lib/
│   ├── main.dart
│   ├── app/
│   ├── core/db/
│   └── features/
│       ├── dream_editor/
│       ├── dream_history/
│       ├── dream_calendar/
│       ├── dream_search/
│       └── reminders/
├── test/
├── android/
├── ios/
├── docs/
│   ├── PROJECT_STATUS.md
│   └── Log.md
├── tool/
├── .github/workflows/
├── pubspec.yaml
├── pubspec.lock
├── README.md
└── LICENSE
```

---

## 开发计划

| 阶段 | 目标 | 主要产出 |
|---|---|---|
| Phase 0 | 技术验证 | 健康数据读取、通知触发、后台限制测试 |
| Phase 1 | 项目骨架 | 工程初始化、路由、主题、状态管理、数据库 |
| Phase 2 | 核心 A | 权限引导、健康数据、通知调度 |
| Phase 3 | 核心 B | 梦境编辑器、自动保存、本地存储 |
| Phase 4 | 核心 C | 日历视图、日期选择、查看 / 补记 |
| Phase 5 | 测试发布 | 单元测试、集成测试、真机测试、内测 |
| Phase 6 | 进阶功能 | AI 报告、画报、推荐、云同步 |

---

## 数据与隐私

梦境与睡眠数据高度敏感。本项目遵循以下原则：

- 默认本地保存，不默认上传。
- 健康数据仅用于判断醒来时间与生成提醒。
- 上传、云同步、AI 分析必须经过用户明确授权。
- 用户可通过清空并保存删除记录；导出、恢复与系统备份策略仍需后续实现和确认。
- 不收集与功能无关的个人信息。
- 不提供医疗建议，不用于医疗诊断。

---

## 开发与交付

自 2026-11-08 起，项目所有者确定使用直接推送流程：

1. 阅读 `AGENTS.md`、项目状态与最近日志，检查工作区和远程更新。
2. 完成一个明确目标；需要隔离时使用短期功能分支或 worktree。
3. 完成相应测试/构建，更新状态、开发日志与变更日志。
4. 保留远程其他人的改动，本地整合到 `main`。
5. 执行 `git push origin main` 并核实结果，不默认创建 PR 或等待审核。

同一 checkout 一次只由一个开发对话写入或推送。GitHub Actions 已监听 `main` 的 push，自动检查无需 PR 也会执行。历史 PR 保留作为交付记录。

要求：

- 保持代码风格一致。
- 核心逻辑尽量补充测试。
- 不提交密钥、token、个人健康数据或梦境内容。
- 涉及隐私、权限、健康数据的改动需在对应文档和交付说明中明确说明。

---

## 许可证

本项目采用 **Apache License 2.0** 许可。

```text
Copyright (c) 2026 夜行者 / Morpheus 项目
```

详见 [LICENSE](LICENSE) 文件。

---

## 免责声明

本应用不是医疗设备，不能用于诊断、治疗或预防任何疾病。  
睡眠与梦境数据仅供个人记录、回顾与娱乐参考。如有睡眠或健康问题，请咨询专业医生。

---

## 致谢

- Flutter 社区
- HealthKit / Health Connect
- 所有贡献者与测试者
