# Flutter 工程骨架说明

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

当前工程已经在原骨架上接入 Drift / SQLite 持久化，功能链为：

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
└── features/
```

#### `lib/main.dart`

应用进程的入口，类似 C++ 的 `int main()`。它只负责：

- 初始化 Flutter 绑定。
- 创建 Riverpod 的根作用域。
- 启动根 Widget。

数据库建表、页面布局和保存逻辑不应直接写在这里，否则入口文件会快速膨胀且难以测试。

#### `lib/app/app.dart`

定义整个应用的根 Widget，集中装配主题、路由和应用级配置。它相当于把各功能模块组合成一个可运行程序的“装配点”。

#### `lib/app/router.dart`

集中声明页面地址和页面之间的导航关系。当前有梦境编辑页 `/` 与历史页 `/history`。后续里程碑可以添加：

```text
/calendar   日历回顾
/settings   提醒与隐私设置
/history    历史记录
```

使用统一路由可以避免每个按钮自行创建页面并维护导航细节。

#### `lib/app/theme.dart`

集中定义颜色、输入框风格和 Material 主题。后续修改视觉设计时，应优先修改主题，而不是逐页替换颜色。

### 3.2 `lib/features/`

按用户能够理解的功能组织代码。当前有 `dream_editor` 与 `dream_history`，未来可以逐步增加 `calendar`、`notifications`、`health` 和 `settings`。

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
- `InMemoryDreamRepository` 是当前练习实现。
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

测试不是最后发布前才补写的附加物。这些契约测试帮助判断数据库改造是否破坏了既有功能；实际移动设备的完整退出/重启仍需要另做验收。

### 3.4 `docs/`

保存设计、里程碑、开发说明和技术决策。它不参与 App 编译，但能记录“为什么这样设计”。

适合放入：

- M1 至 M5 里程碑计划。
- 数据库设计。
- 权限和隐私说明。
- HealthKit 与 Health Connect 调研结果。
- 重要技术决策记录。

### 3.5 `.github/workflows/`

存放 GitHub Actions 配置。每次推送或提交 Pull Request 后，GitHub 会在干净环境中运行：

```text
flutter pub get
dart format 检查
flutter analyze
flutter test
```

这能发现“只在本机正常”的问题，例如遗漏文件、依赖未声明或格式不一致。

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

当前已通过 Repository 的 `getAll()` 接入倒序历史查询，并在路由中新增 `/history`；编辑器通过标准日期选择器选择日期，通过 `selectDate()` 先保存草稿再读取。后续月历记录标记可以复用 `DreamEntry`，记录较多时再加入按月范围查询。详见 [日期与历史说明](DATE_HISTORY_GUIDE.md)。

### 6.3 本地通知

通知设置应作为独立功能模块，不直接写进编辑页面。通知被点击后，通过路由打开当天的 `DreamEditorPage`。因此通知功能依赖当前已有的稳定路由和编辑入口。

### 6.4 HealthKit 与 Health Connect

健康数据模块负责产生“可能已经醒来”的事件，而不负责编辑和保存梦境。事件触发本地通知，用户点击后仍然进入当前编辑链路。这样的分层可以保证健康权限失败时，梦境日记本身仍能正常使用。

### 6.5 AI 功能

AI 功能应读取用户明确选择并授权的 `DreamEntry`，通过独立服务接口发送请求。它不应直接访问编辑器的 TextEditingController，也不应把 API Key 写入移动端源码。

## 7. 推荐的后续实施顺序

1. 安装 Flutter 并运行 `tool/bootstrap_platforms.sh`。
2. 修复本机环境问题，确保 `flutter doctor` 无关键错误。
3. 执行 `flutter analyze` 和 `flutter test`。
4. 启动模拟器，理解从 `main.dart` 到编辑页面的调用链。
5. 验证已接入的 Drift 持久化：同一天、同一设备完整退出再打开仍能读取正文。
6. 增加历史记录与日历页面。
7. 增加用户设定时间的本地通知。
8. 最后验证 HealthKit 与 Health Connect。

每一步都应保持现有测试通过，并在开发日志中记录已完成内容、遇到的问题和下一步计划。
