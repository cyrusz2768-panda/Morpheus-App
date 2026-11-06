# 日期选择与历史梦境查看

## 1. 本次功能

保留现有编辑器和主题，增加按日期回顾与补记的入口：

- 右上角日历按钮打开中文日期选择器，可选择 1900 年至今天之间的日期。
- 有记录时读取原文；无记录时显示空编辑器，可以补记。每个日期仍只有一条梦境。
- 查看过去日期时显示“回到今天”，点击即可返回当天记录。
- 右上角历史按钮打开列表，按梦境所属日期从新到旧排列，显示日期与正文预览。点击后回到编辑器查看完整原文，也能继续修改或清空删除。
- 没有记录时显示空态，读取失败时显示重试入口；每次打开历史或手动刷新都重新查询数据库。

本次使用标准日期选择器和列表。月历中的记录圆点、搜索和分页尚未实现。

## 2. 语言、依赖和文件

主要开发语言仍是 **Dart**。Flutter 负责页面与日期选择器，Riverpod 管理异步结果和编辑器状态，go_router 管理历史页的进入与返回，Drift 把查询转换成 SQLite 操作。`pubspec.yaml` 和依赖锁文件使用 YAML。

唯一新增的直接依赖是 Flutter SDK 自带的 `flutter_localizations`，用于标准组件的中文年月、星期与按钮翻译。没有新增第三方日历库。

| 文件 | 作用 |
|---|---|
| `lib/features/dream_editor/data/dream_repository.dart` | 新增 `getAll()` 查询契约，页面不直接操作 SQLite |
| `lib/features/dream_editor/data/drift_dream_repository.dart` | 用 SQL 按梦境日期降序查询，并转换成领域对象 |
| `lib/features/dream_editor/data/in_memory_dream_repository.dart` | 为测试提供相同的查询、排序和空白过滤行为 |
| `lib/features/dream_editor/application/dream_editor_controller.dart` | `flushPendingSave()` 等待草稿提交；`selectDate()` 安全切换日期 |
| `lib/features/dream_editor/presentation/dream_editor_page.dart` | 日期选择、回到今天、打开历史及失败提示 |
| `lib/features/dream_history/application/dream_history_provider.dart` | 把历史查询转换成加载、成功、失败状态 |
| `lib/features/dream_history/presentation/dream_history_page.dart` | 历史列表、空态、错误重试与选择记录 |
| `lib/app/router.dart` | 注册 `/history` 路由；历史页返回所选日期 |
| `lib/app/app.dart` | 配置中文标准组件本地化 |

## 3. 主要逻辑

### 日期切换为什么要等待保存

编辑器原有 800ms 防抖：停止输入一小段时间后才自动写入。若刚输入就切到昨天，直接清空旧状态会丢掉今天的草稿。

因此切换步骤是：选择目标日期 → 等待当前日期所有待保存内容完成 → 保存失败则保留原日期和草稿 → 保存成功才读取目标日期。正在进行的旧写入和期间输入的新版本会按顺序处理；正文不会被归到另一日期。选择同一天或取消日期选择器不会重新读取并覆盖草稿。

读取目标日期失败时，该日期的输入框保持禁用，并提供“重试”，避免把读取失败显示出的空白当成删除操作。

### 历史列表怎样获得数据

进入历史前也先等待保存。随后历史 Provider 调用 Repository 的 `getAll()`，SQLite 按 `dream_date` 降序查询，而不是按修改时间排序。空白记录不会出现在列表中；没有记录的日期仍可通过日期选择器补记。

点某条记录时，历史页只返回日期，编辑器按日期读取完整正文。显示预览时压缩换行与多余空格，不会改写数据库中的原文。新增、编辑、清空删除后再次打开列表，会读取最新结果。

本次沿用 `nightwalker.sqlite`、原有日期主键和表结构，**数据库版本仍为 1，无需删除数据库或迁移旧记录**。历史中包含已有数据。

## 4. 运行与验收

在包含 `pubspec.yaml` 的项目根目录中打开终端；更新依赖后运行：

```bash
flutter --no-version-check pub get
dart run build_runner build
flutter --no-version-check run
```

建议按以下顺序在同一模拟器中确认：

1. 查看今天已有的文字，确认升级安装后记录仍在。
2. 点击日历按钮选择昨天，输入一段测试文字，等到“已保存”。
3. 点击“回到今天”，确认今天与昨天的文字互不混淆。
4. 点击历史按钮，确认按日期倒序排列；点击昨天的记录，应显示昨天的日期及完整正文。
5. 修改昨天的文字后立即回到今天，再通过历史返回昨天，确认最新版本已保存。
6. 关闭 App 后重新打开，再通过日期/历史找到昨天，确认仍能读取。
7. 清空一条专门用于测试的记录，等待保存，再查看历史，确认只移除了对应日期。

自动测试使用独立内存仓库或临时 SQLite 文件，不读写开发者在模拟器中的真实梦境。本轮已完成本地检查与开发者模拟器验收，开发者已授权合并；发布采用功能分支、PR 和 CI 检查流程。

## 5. 验证边界与参考

Android 的 M1 基础持久化、日期选择和历史查看已由开发者验收通过；上面的步骤可供后续版本回归。iOS 的设备测试仍待完成，本次不标记整个 Version 0.1 完成。

本轮本地验证：格式化与静态分析通过，57 项自动测试全部通过，其中新增 29 项覆盖历史查询、持久化、路由交互及切日竞态；Android ARM64 调试 APK 构建通过。测试数据均独立于模拟器真实数据。

- [Flutter 日期选择器](https://api.flutter.dev/flutter/material/showDatePicker.html)
- [Flutter 标准组件本地化](https://docs.flutter.dev/ui/internationalization)
