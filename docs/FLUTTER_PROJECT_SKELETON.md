# Flutter 工程骨架说明

更新日期：2026-11-08。本文解释现有工程的职责划分；开始新任务时先阅读 [项目规则](../AGENTS.md) 和 [项目状态](PROJECT_STATUS.md)，再核对实际代码与 Git 状态。

## 1. 在 GitHub 仓库中的放置方式

本项目的 GitHub 仓库应当直接作为 Flutter 项目根目录，不需要在仓库内部再创建一个名为 `morpheus` 或 `app` 的外层文件夹。

正确结构：

```text
仓库根目录/
├── android/
├── ios/
├── lib/
├── test/
├── docs/
├── .github/
├── pubspec.yaml
├── README.md
└── LICENSE
```

不推荐的结构：

```text
仓库根目录/
├── README.md
├── LICENSE
└── morpheus/
    ├── android/
    ├── ios/
    ├── lib/
    └── pubspec.yaml
```

当前仓库只承载一个应用，因此多套一层目录只会让运行命令、CI 路径和文档链接更加复杂。只有当一个仓库同时包含多个独立项目，例如移动端、后端和管理后台时，才适合采用 `apps/mobile`、`services/api` 这样的多项目结构。

GitHub 网页中的“文件夹”不需要提前手工建立。Git 会根据本地文件路径自动显示 `lib/`、`docs/` 等目录。正确流程是先在本地项目根目录中生成或编辑文件，再提交并推送到 GitHub。本仓库原来使用 `docs/`，因此沿用它而不另建 `doc/`。

## 2. 当前骨架的目标

当前工程已经在原骨架上接入 Drift / SQLite 持久化、日期与历史、月历和本地提醒。编辑记录的主链为：

```text
main.dart
  -> ProviderScope
  -> MorpheusApp
  -> GoRouter
  -> DreamEditorPage
  -> DreamEditorController
  -> DreamRepository
  -> DriftDreamRepository
  -> AppDatabase
  -> SQLite 文件（nightwalker.sqlite）
```

这条链路的价值是明确每一层的职责和连接方式。正式 App 现在把数据保存在私有应用支持目录的 SQLite 文件中，已提交的数据在普通重启后仍可读取。内存实现仅供测试和学习对比。详细接入说明和重启验收步骤见 [M1 数据库说明](M1_SQLITE_GUIDE.md)。

## 3. 目录与文件职责

### 3.1 `lib/`

`lib/` 存放应用的 Dart 源代码，是日常开发最常进入的目录。

```text
lib/
├── main.dart
├── app/
├── core/
└── features/
```

#### `lib/main.dart`

应用进程的入口，类似 C++ 的 `int main()`。它只负责：

- 初始化 Flutter 绑定。
- 创建 Riverpod 的根作用域。
- 启动根 Widget。

数据库建表、页面布局和保存逻辑不应直接写在这里，否则入口文件会快速膨胀且难以测试。

#### `lib/app/app.dart`

定义整个应用的根 Widget，集中装配主题、中文标准组件、路由和应用级配置。它相当于把各功能模块组合成一个可运行程序的“装配点”。当前还协调从系统设置返回后的提醒刷新，以及通知点击时先保存草稿、再打开当天记录。

#### `lib/app/router.dart`

集中声明页面地址和页面之间的导航关系。当前已经注册：

```text
/           梦境编辑
/history    历史记录
/calendar   梦境月历与记录标记
/reminders  每日提醒设置
```

使用统一路由可以避免每个按钮自行创建页面并维护导航细节。首页左上角菜单抽屉中的“通知设置”打开 `/reminders`；日历和历史按钮分别打开对应页面。

#### `lib/app/theme.dart`

集中定义颜色、输入框风格和 Material 主题。后续修改视觉设计时，应优先修改主题，而不是逐页替换颜色。

### 3.2 `lib/features/`

按用户能够理解的功能组织代码。当前有 `dream_editor`、`dream_history`、`dream_calendar` 和 `reminders`，分别负责记录编辑、历史查询、月历和提醒。健康数据与 AI 尚未接入。

每个功能内部再按职责划分：

```text
dream_editor/
├── domain/
├── data/
├── application/
└── presentation/
```

#### `domain/`

描述业务概念和业务规则，不依赖界面或数据库。

当前的 `DreamEntry` 表示一条梦境记录，包含日期、正文和时间戳。日历、数据库和未来的导出功能都应复用同一个领域模型，而不是各自重新定义梦境结构。

#### `data/`

负责数据来自哪里、存到哪里。

- `DreamRepository` 是上层代码使用的接口。
- `InMemoryDreamRepository` 是供测试和学习对比使用的内存实现。
- `DriftDreamRepository` 是当前正式使用的本地持久化实现。
- `dream_providers.dart` 负责装配数据库连接和 Repository，测试可以替换依赖。

Repository 接口隔离了业务层和数据库。编辑页面只要求“读取、保存、删除梦境”，不需要知道 SQLite 表名和 SQL 语句。

#### `application/`

负责一次用户操作如何完成，例如：

- 首次进入页面时读取当天梦境。
- 文本变化后等待 800 毫秒。
- 保存过程中避免旧内容覆盖新内容。
- 将保存状态转换为 UI 可以显示的状态。

这一层通常称为应用逻辑或状态管理层。本项目使用 Riverpod 的 `Notifier` 暴露状态。

#### `presentation/`

包含用户实际看到和操作的 Widget。页面负责布局和反馈，不直接编写数据库代码。

这种边界可以让页面测试专注于“输入后是否显示已保存”，数据测试专注于“同一天是否重复创建”。

### 3.3 `test/`

测试目录与 `lib/` 的功能结构相对应：

```text
test/features/dream_editor/
├── domain/
├── data/
└── presentation/
```

当前测试分别验证：

- 日期归一化和日期键。
- 内存 Repository 的增删改查。
- 页面输入后的自动保存行为。
- 真实 SQLite 文件关闭、重新打开后，记录及更新时间仍然存在。
- 正式 Provider 绑定与 Controller 在容器重建后的自动恢复。
- 日期切换、历史和月历导航前的草稿保护，以及月历记录标记的实时更新。
- 提醒设置持久化、权限和通知点击流程、菜单与首次引导。

这些契约测试帮助判断改造是否破坏既有功能；平台构建和设备人工回归另行记录，不能用测试数量代替。最近一次检查结果与尚未验证的场景见 [项目状态](PROJECT_STATUS.md)。

### 3.4 `docs/`

保存设计、里程碑、开发说明和技术决策。它不参与 App 编译，但能记录“为什么这样设计”。

适合放入：

- M1 至 M5 里程碑计划。
- 数据库设计。
- 权限和隐私说明。
- HealthKit 与 Health Connect 调研结果。
- 重要技术决策记录。

### 3.5 `.github/workflows/`

存放 GitHub Actions 配置。现有工作流监听 `main` 和 `feature/**` 的推送，也保留 PR 触发支持。直接推送 `main` 后，GitHub 会在干净环境中运行：

```text
flutter pub get
dart run build_runner build
dart format 检查
flutter analyze
flutter test
```

这能发现遗漏文件、依赖未声明或格式不一致等问题。CI 当前不构建 Android APK 或 iOS App，也不替代设备验收；无需创建 PR 才能触发检查。

### 3.6 `pubspec.yaml`

Flutter 项目的核心清单文件，主要定义：

- 项目名称与版本。
- Dart SDK 版本范围。
- 运行依赖和开发依赖。
- 图片、字体等资源。

新增第三方包时应通过 `flutter pub add 包名` 修改它，而不是把依赖源码复制进项目。

### 3.7 `analysis_options.yaml`

配置静态分析与代码规范。`flutter analyze` 会依据该文件检查潜在错误和不一致写法。

### 3.8 `.gitignore`

告诉 Git 哪些文件不应进入仓库，例如构建产物、编辑器配置、本地缓存和密钥。源代码、测试、文档和依赖清单应提交；能够自动生成或包含本机信息的文件通常不提交。

## 4. 常见文件类型

| 类型 | 主要位置 | 作用 |
|---|---|---|
| `.dart` | `lib/`、`test/` | Flutter 页面、业务逻辑、模型和测试 |
| `.yaml` | 根目录、`.github/` | 依赖、分析规则和 CI 配置 |
| `.md` | 根目录、`docs/` | README、计划和技术说明 |
| `.kt` | `android/` | Android 原生 Kotlin 代码 |
| `.kts` | `android/` | Android Gradle 构建脚本 |
| `.xml` | `android/` | Android 权限、资源和清单 |
| `.swift` | `ios/` | iOS 原生 Swift 代码 |
| `.plist` | `ios/` | iOS 权限文案和应用配置 |
| `.xcconfig` | `ios/` | Xcode 构建配置 |
| `.g.dart` | 通常与 Dart 源码相邻 | 代码生成器产生的文件 |

Android 与 iOS 平台文件大部分由 Flutter 官方工具生成。不要为了“注释完整”而随意修改生成的构建配置；真正需要教学和维护的手写 Dart 代码已经在本骨架中加入详细注释。

## 5. Android 与 iOS 平台目录

本骨架已经使用 Flutter 官方生成器创建 `android/` 和 `ios/`。仓库同时保留了 `tool/bootstrap_platforms.sh`，用于平台目录丢失或需要按当前 Flutter 版本重新生成时恢复工程。在本机安装 Flutter 后，可以于仓库根目录执行：

```bash
chmod +x tool/bootstrap_platforms.sh
./tool/bootstrap_platforms.sh
```

脚本会调用 Flutter 官方生成器，在当前仓库根目录中补齐 `android/` 和 `ios/`，随后安装依赖、格式化代码、静态分析并运行测试。

执行前应先提交或备份当前修改，以便通过 Git 清楚地检查生成器添加了哪些文件。练习阶段脚本使用 `com.example`；在准备发布前必须改为自己控制的永久包名。

## 6. 骨架与后续步骤的关系

### 6.1 已接入：Drift 本地数据库

最初教学骨架的依赖关系为：

```text
DreamEditorController -> DreamRepository -> InMemoryDreamRepository
```

当前默认绑定已经变为：

```text
DreamEditorController -> DreamRepository -> DriftDreamRepository -> SQLite
```

Controller 和页面不需要理解 SQL。本次已经在 `dreamRepositoryProvider` 中更换实现并补充数据库测试。表定义在 `lib/core/db/tables/`，修改表后通过 `dart run build_runner build` 重新生成 `.g.dart`；已有用户数据的结构升级还必须设计迁移。

### 6.2 日历与历史记录

当前已通过 Repository 的 `getAll()` 接入倒序历史查询，并注册 `/history`。首页日历按钮打开 `/calendar`，月历内保留标准中文快速日期选择器；选择日期后由编辑器安全保存草稿，再读取对应记录。

月历通过 `ICalendarRepository` 按月监听同一份 SQLite 数据，直接从非空记录派生圆点，不创建标记副本或新表。详见 [日期与历史说明](DATE_HISTORY_GUIDE.md) 和 [梦境月历说明](CALENDAR_GUIDE.md)。历史搜索和分页尚未实现。

### 6.3 本地通知

本地通知已经接入独立的 `reminders` 模块，包含提醒时间、开关、授权说明、系统设置入口和测试通知。设置通过私有 JSON 保存，原生通知调用通过接口隔离 Android 与 iOS 差异。

首页菜单提供通知设置入口，首次入口引导和系统通知授权说明分别记住已读状态。通知被点击后，App 层先等待最新草稿保存，再打开当天记录；权限被拒绝时仍能记录梦境。详见 [每日提醒说明](REMINDERS_GUIDE.md)。

### 6.4 HealthKit 与 Health Connect

这是后续规划，当前没有健康数据模块。未来该模块可以产生“可能已经醒来”的事件，而不负责编辑和保存梦境。事件触发提醒后仍复用当前编辑链路，健康权限失败时保留手动记录与固定时间提醒。

### 6.5 AI 功能

AI 尚未实现。未来应只读取用户明确选择并授权的 `DreamEntry`，通过独立服务接口发送请求，不直接访问编辑器的 TextEditingController，也不把 API Key 写入移动端源码。

## 7. 新对话接手与后续开发

1. 阅读 `AGENTS.md`、[项目状态](PROJECT_STATUS.md) 与最近开发日志，核对当前工作区、分支及远程更新；一个开发对话聚焦一个可验收目标。
2. 首次克隆或依赖变化时恢复依赖并生成 Drift 代码；平台目录已经存在，不为开始新对话重新生成整个工程。
3. 沿用既有分层实现当前目标，保持 Android 与 iOS 共用逻辑及用户数据兼容；日历、历史与提醒已实现，不重复另建模块。
4. 根据改动完成格式、分析、测试及必要的平台构建或人工回归，明确哪些检查实际执行、哪些仍待验证。
5. 更新项目状态、开发日志与相应功能说明，提交有说明的版本。按 2026-11-08 用户决定，本地整合到 `main` 后直接 `git push`，不再要求新建 PR 或等待 partner 审核。

下一项功能以 [项目状态](PROJECT_STATUS.md) 和用户当前目标为准；健康数据、AI 等后续规划不自动进入本轮开发范围。
