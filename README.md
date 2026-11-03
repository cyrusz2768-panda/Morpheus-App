# 夜行者 / Morpheus

> 醒来，记下梦。

夜行者 / Morpheus 是一款面向 iOS 与 Android 的梦境记录应用。  
它通过智能手表睡眠数据或用户设定的起床时间，在醒来时推送通知，帮助用户第一时间记录梦境。应用坚持本地优先、隐私优先，并计划逐步加入 AI 梦境画报、周期梦境报告与内容推荐。

App 名称待定，当前暂用“夜行者 / Morpheus”。

---

## 功能简介

### Version 0.1 核心功能

- **醒来提醒**
  - 有智能手表且授权：读取睡眠数据，在用户醒来时推送记录梦境通知。
  - 无智能手表或未授权：引导用户设置每日定时推送时间。
  - 每次打开 App 时，若尚未设置定时提醒，则提醒用户设置。

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
| 日历 UI | table_calendar |
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

项目处于 **Version 0.1 规划与开发阶段**。

### 当前 M1 已接入

- Flutter Android / iOS 工程骨架，Riverpod 状态管理与 go_router 路由。
- 当天梦境的编辑、800ms 防抖自动保存、清空后删除。
- Drift / SQLite 文件持久化、同日唯一、保存失败保留草稿并重试。
- 28 项自动化测试，覆盖真实文件关闭重开、默认后台连接和页面交互。

**验证边界：** 自动测试已通过，但 Android / iOS 设备上的完整重启验收尚未完成。当前 Android 首次构建还需补齐指定 SDK/NDK 并处理下载失败；本次不能标记整个 M1 或 Version 0.1 完成。数据库目前未加密，提醒、日历、健康数据和 AI 尚未实现。

学习说明与操作步骤见 [M1 数据库接入说明](docs/M1_SQLITE_GUIDE.md)，目录职责见 [Flutter 工程说明](docs/FLUTTER_PROJECT_SKELETON.md)。原有需求、计划、许可证及开发日志继续保留。

Version 0.1 目标：

> 完成一个能够正常运行的版本，实现最核心的功能：  
> 醒来提醒 → 记录梦境 → 本地保存 → 日历查看 / 补记。

Version 0.1 暂不包含：

- 账号体系、云同步、社交功能。
- AI 画报、周期报告、推荐系统。
- 复杂编辑器、多端同步、付费系统。

---

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
dart run build_runner build
flutter analyze
flutter test
flutter run
```

打开 VS Code 时选择整个 `Morpheus-App` 文件夹，即包含 `pubspec.yaml` 的工程根目录。Drift 的 `.g.dart` 按本仓库规范不提交，首次克隆、拉取数据库结构变更后必须先运行上面的代码生成命令；不要手改生成文件或手工建立数据库。

若 Flutter 卡在 GitHub 更新检查，可把 Flutter 命令改为 `flutter --no-version-check pub get`、`flutter --no-version-check test` 或 `flutter --no-version-check run`。这只跳过查新，不绕过依赖下载、许可证或构建错误。新增原生依赖后应停止旧 App 完整重建，不能只用 Hot Reload。

验收持久化：输入文字，等“已保存”后完整退出，在同一天、同一设备重开，正文应恢复。不要卸载、清除应用数据或使用模拟器 Wipe Data。详细步骤和故障边界见 [接入说明](docs/M1_SQLITE_GUIDE.md)。

### 权限配置

以下为后续提醒与健康数据功能的配置规划，当前本地梦境编辑功能不需要预先添加这些权限。

iOS：

- 在 `Info.plist` 中添加通知权限、健康数据读取权限说明。
- 使用 HealthKit 时，需要开启对应 Capability。

Android：

- 在 `AndroidManifest.xml` 中声明通知、健康数据相关权限。
- Android 13+ 需要动态申请通知权限。
- 使用 Health Connect 时，需要按官方要求配置权限与隐私说明。

---

## 目录结构建议

```text
morpheus/
├── lib/
│   ├── main.dart
│   ├── app/
│   ├── core/
│   │   ├── db/
│   │   ├── models/
│   │   ├── services/
│   │   ├── theme/
│   │   └── router/
│   ├── features/
│   │   ├── onboarding/
│   │   ├── home/
│   │   ├── dream_editor/
│   │   ├── calendar/
│   │   ├── settings/
│   │   ├── notifications/
│   │   ├── health/
│   │   ├── report/
│   │   └── recommendation/
│   └── services/
├── test/
├── assets/
├── android/
├── ios/
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
- 用户可删除、导出自己的数据。
- 不收集与功能无关的个人信息。
- 不提供医疗建议，不用于医疗诊断。

---

## 贡献指南

欢迎提交 Issue 与 Pull Request。

基本流程：

1. Fork 本仓库。
2. 创建功能分支：`feature/your-feature`。
3. 完成开发与自测。
4. 提交 PR，说明改动内容与测试情况。
5. 等待 Code Review 与合并。

要求：

- 保持代码风格一致。
- 核心逻辑尽量补充测试。
- 不提交密钥、token、个人健康数据或梦境内容。
- 涉及隐私、权限、健康数据的改动需在 PR 中明确说明。

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
