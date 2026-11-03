# M1：Drift / SQLite 本地持久化接入说明

更新日期：2026-11-03。适用工程：夜行者 / Morpheus，Android 与 iOS 原生 Flutter 应用。

## 1. 本次完成了什么

本次把正式 App 的存储从内存 Map 改为 SQLite 文件，目标链路是：

```text
输入梦境 → 停止输入约 800 毫秒 → 写入 SQLite → 显示“已保存”
                                              ↓
完全关闭 App → 在同一设备、同一天重新打开 → 从同一文件读取正文
```

已实现每天一条记录的创建、查询、更新和删除；更新不重复创建记录，首次创建时间保持不变。清空正文并保存会删除当天记录。数据库版本为 1，首次打开时自动建表。

另外修复了数据安全相关的重试流程：读取失败时禁止编辑，避免用空白覆盖尚未读出的数据；保存失败时保留当前文字，“重试”继续保存，而不是用数据库中的旧文字覆盖编辑器。

这只是 M1 的持久化子任务，不是日历、提醒、AI 功能，也不等于两个移动平台都已完成真机验收。

## 2. 用了什么语言、工具和文件

| 项目 | 作用 | 与 C++ 学习经验的联系 |
|---|---|---|
| Dart | 页面、状态管理、Repository、数据库定义和测试 | 是应用代码的主要语言，入口 `main()` 类似 C++ 程序入口 |
| Flutter | 把 Dart 的 Widget 渲染为页面，并连接手机平台 | 是框架，不是一门替代 Dart 的语言 |
| SQL / SQLite | 用表、主键、事务把记录保存到文件 | 相当于一个嵌入 App 的数据库，不是远程数据库服务器 |
| Drift | 用类型安全的 Dart API 表达 SQL，生成访问代码 | 省去手工拼接 SQL；它本身不取代 SQLite 引擎 |
| Riverpod | 提供数据库与 Repository，管理编辑器状态 | 类似集中提供对象和依赖，避免页面到处创建连接 |
| YAML | `pubspec.yaml` 声明依赖；CI 配置自动检查 | 是配置格式，不负责运行梦境保存逻辑 |
| Markdown | 当前说明文档与 README | 供人阅读，不参与 App 编译 |

本次不需要编写 C++、Kotlin 或 Swift 业务代码，也不需要在电脑上单独安装 SQLite 服务器。SQLite 原生库由依赖构建工具集成，Android / iOS 仍需具备各自的构建环境。

直接加入的运行依赖是 `drift`、`drift_flutter`、`path_provider`；开发依赖是 `drift_dev`、`build_runner`，以及仅用于测试系统目录接口的 `path_provider_platform_interface`。实际解析版本记录在 `pubspec.lock`，请与依赖清单一起保留。没有在本次接入中升级 Flutter SDK。

## 3. 代码在哪里，推荐按什么顺序看

下表路径均相对于工程根目录，即包含 `pubspec.yaml` 的目录。

| 文件 | 主要职责 |
|---|---|
| `lib/core/db/tables/dream_records.dart` | 声明梦境表、正文、日期主键、UTC 时间戳 |
| `lib/core/db/app_database.dart` | 声明数据库、版本、首次建表和原生连接位置 |
| `lib/core/db/app_database.g.dart` | Drift 自动生成的访问代码，**不要手工修改** |
| `lib/features/dream_editor/data/drift_dream_repository.dart` | 把读取、保存、删除转换为 SQL 操作 |
| `lib/features/dream_editor/data/dream_providers.dart` | 为正式 App 绑定一份数据库与 Drift Repository |
| `lib/features/dream_editor/data/dream_repository.dart` | 页面/Controller 依赖的存储接口，保持实现可替换 |
| `lib/features/dream_editor/application/dream_editor_controller.dart` | 首次加载、800ms 防抖、串行保存、按故障类型重试 |
| `lib/features/dream_editor/application/dream_editor_state.dart` | 加载状态、正文、保存状态、故障类型 |
| `lib/features/dream_editor/presentation/dream_editor_page.dart` | 文本输入、状态反馈、后台提交和读取失败时的保护 |
| `test/features/dream_editor/data/drift_dream_repository_test.dart` | SQL 契约与真实文件关闭/重开测试 |
| `test/features/dream_editor/data/dream_providers_test.dart` | 检查正式绑定与新容器启动后的自动恢复 |
| `test/core/db/app_database_test.dart` | 使用默认连接与后台 isolate，模拟系统目录后验证文件位置和重开 |
| `test/features/dream_editor/application/dream_editor_controller_test.dart` | 保存失败、读取失败、排队写入等行为测试 |
| `test/features/dream_editor/presentation/dream_editor_page_test.dart` | 编辑、重试和生命周期等界面测试 |

建议先读表定义与 Repository，再读 Provider 和 Controller，最后结合测试理解流程。不需要逐行研究整个 `.g.dart`。手写新增逻辑带有中文教学注释；旧骨架中仍有部分英文注释。

`InMemoryDreamRepository` 没有被删除，但只用于快速测试和学习对比；正式 `dreamRepositoryProvider` 返回 `DriftDreamRepository`，不是内存仓库。

## 4. 数据是怎样保存的

### 4.1 保存位置

`path_provider` 请求系统的“应用支持目录”（Application Support），`drift_flutter` 在其中打开 `nightwalker.sqlite`。

这个位置在手机 App 的私有沙盒里，不是你 Mac 上的源码目录、Downloads，也不是 GitHub 仓库。不同设备与应用安装有各自的数据文件，数据库路径由系统提供，不硬编码某台电脑的绝对路径。

普通退出和重新打开不会删除这个文件。**卸载应用、清除应用数据、模拟器 Wipe Data、换一个模拟器或改变 App 身份**，不能当作“同一份数据的普通重启”来验收。旧版内存中已经丢失的记录无法恢复。

### 4.2 表结构与时间

SQLite 表名为 `dream_records`：

| SQLite 列 | 类型 | 含义 |
|---|---|---|
| `dream_date` | TEXT，主键 | 如 `2026-11-03`，同一天最多一条 |
| `content` | TEXT | 原样保存正文，保留换行和首尾空格 |
| `created_at_millis` | INTEGER | 首次创建的 UTC Unix 毫秒时间戳 |
| `updated_at_millis` | INTEGER | 最近一次更新的 UTC Unix 毫秒时间戳 |

“梦境所属日期”和“某个时间点”不是同一概念。日期使用本地日历的年、月、日，不先转为 UTC，以免跨时区时日期偏移；创建/更新时间则使用 UTC，以便以后排序、导出和同步。领域对象中的 `id` 直接使用日期键，不另设一列 ID。

### 4.3 写入、更新与删除

1. 文本变化时，Controller 更新内存中的编辑状态并重置 800ms 定时器。
2. 定时器触发，Controller 把当前日期和正文交给 Repository。
3. 非空正文通过 `INSERT ... ON CONFLICT DO UPDATE` 写入。同一天已存在时更新正文和更新时间，不覆盖创建时间。
4. 写入和回读处于事务中：失败时回滚，成功后 `Future` 才返回。
5. Controller 收到成功结果，才把页面状态改成“已保存”。不是先显示成功，再偷偷等待磁盘写入。
6. 如果保存期间又输入了新文字，Controller 排队继续保存最新版本，不允许较早的结果把新文字标成已保存。

`trim()` 只用于判断是不是纯空白，不用它修改用户正文。用户清空正文时，Controller 调用 `deleteByDate()`；直接向 Repository 的 `save()` 传纯空白会报参数错误，避免误存空记录。

### 4.4 重开与连接生命周期

重开应用时，创建新的 Provider 容器、Controller 和数据库连接，但文件路径没有改变。Controller 的首次加载从 SQLite 查询当天记录，再交给输入框显示。

同一容器共用一份数据库，不是每次敲键盘都创建连接。数据库 SQL 在后台 isolate 执行，容器释放时关闭连接。**保存完成不依赖关闭连接；系统也不会保证在进程被终止前等待 Dart 的异步回调。**

### 4.5 自动保存的边界

进入后台时，页面会尝试尽快提交待保存内容。不过强制停止、断电、崩溃都可能发生在定时器或 SQL 尚未完成之前，不能保证“刚打完最后一个字立刻强杀”也不丢字。

正确验收标准是：**等待“已保存”后完整退出并重开，刚才的正文仍存在。** 若看到“等待自动保存”“正在保存”或“保存失败”，不要把它当成已经成功落盘。

当前只有“当天编辑器”。如果跨天再打开，显示空白可能只是正在读取新一天；旧日期记录不会因此自动删除，但需要后续历史记录/日历功能才能方便浏览。编辑器保持打开跨午夜时不会自动切换文档日期，这也不在本次实现范围内。

## 5. 你需要对这些文件做什么

### 5.1 如果 VS Code 打开的就是本次工程目录

本次文件已经直接写入当前工程，不需要逐个下载或手工粘贴。打开终端，确认你在含 `pubspec.yaml` 的目录，然后依次运行：

```bash
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```

- `pub get`：安装或恢复依赖，并更新原生插件注册信息。
- `build_runner build`：根据表定义生成数据库访问代码。按仓库现有规则，`.g.dart` 不提交；首次拉取和数据库定义变更后必须运行，不能省略。
- `analyze`：检查类型和代码规范。
- `test`：运行已有测试及新增持久化、故障处理测试，不需要启动模拟器。

不需要执行 `flutter create`，也不需要重新运行 `tool/bootstrap_platforms.sh`。现有 Android / iOS 平台目录要保留，不要用空白工程覆盖。

### 5.2 如果你的 GitHub 仓库在另一个本地文件夹

先备份或提交那个仓库中尚未提交的改动，再按本说明第 3 节列出的相对路径合并新增/修改的代码与测试。还需要合并 `pubspec.yaml`、`pubspec.lock`、`.gitignore`、`.github/workflows/flutter_checks.yml` 与本次文档/README 更新。

不要整文件覆盖你自己后续修改过的页面或依赖清单，也不要覆盖已有 LICENSE、开发日志或其他功能。新增数据库与 Provider 文件可以按相同目录新增；已存在的文件需要先对比再合并。

本次仓库副本已从 `cyrusz2768-panda/Morpheus-App` 克隆，工程就是包含 `pubspec.yaml` 的本地 `Morpheus-App` 文件夹。文档沿用远端已有的 `docs/` 目录，不另建 `doc/`；此前未关联 Git 的工程副本仍可保留作为备份。

当前准备分支是 `feature/m1-sqlite`，是否已经上传请以 Git 状态和 GitHub 页面为准。公开可读取仓库不等于本机已获得推送权限；需要通过 GitHub 登录授权后才能提交推送。不要发送密码或访问 Token 到聊天中。

### 5.3 启动 App：需要完整重新构建

本次新增了原生插件/SQLite 构建依赖，**仅 Hot Reload 不够**：先停止旧 App，再启动同一个安卓模拟器或连接同一个安卓设备。

```bash
flutter devices
```

从输出中选择平台为 Android 的设备，在 VS Code 的设备选择器中选中它，再运行；也可以使用下面的命令，其中设备 ID 必须替换成实际值：

```bash
flutter run -d emulator-5554
```

`emulator-5554` 只是示例，不是每台电脑都相同。第一次构建可能下载 Gradle、Android 组件和 SQLite 原生构建资产，需要网络和磁盘空间。当前没有新增 Web 平台或浏览器数据库配置，请不要选 Chrome 来验收这次改动。

本机 Flutter 在检查 GitHub 更新时若出现网络超时，可用下面的形式跳过“SDK 更新检查”：

```bash
flutter --no-version-check run -d emulator-5554
```

这不绕过包下载、Android 依赖下载、许可证或实际编译错误，也不能修复网络本身。

## 6. 手动验收步骤

1. 启动 App，确认能进入“夜行者”梦境编辑页。
2. 输入一段容易辨认的多行中文，例如“持久化验收：我梦见一座蓝色图书馆。”
3. 停止输入，等页面明确显示“已保存”。
4. 将 App 切到后台，再完整退出/停止进程；不要卸载、清除数据或 Wipe Data。
5. 在同一设备、同一天重新打开同一个 App。正文应完整恢复。
6. 修改正文，等“已保存”，再次退出/重开。应恢复修改后的版本，而非旧版本。
7. 清空正文，等“已保存”，退出/重开。当天应为空，旧文字不应复活。

Hot Reload 不会销毁整个进程；Hot Restart 也不等于操作系统层面的完整重开。它们可以辅助开发，但不能代替上述设备验收。

## 7. 自动测试与当前验证范围

新增测试会建立自己的临时 SQLite 文件，保存后关闭所有连接，再新建数据库/Repository 或 ProviderContainer 去读取同一文件。这样可以排除“只从内存里取回数据”的假持久化。

测试也覆盖同日唯一、创建时间保留、UTC 毫秒精度、并发写入、删除后重开、纯空白拒绝、保存失败重试保留文字等。测试只清理自己创建的随机临时目录，不接触用户的正式梦境数据库。

2026-11-03 在本机执行的结果如下：

| 检查 | 结果 |
|---|---|
| `flutter pub get` | 成功，依赖与锁文件已更新 |
| `dart run build_runner build` | 成功；重复生成也通过 |
| `dart format --output=none --set-exit-if-changed lib test` | 通过，无格式差异 |
| `flutter analyze` | 通过，No issues found |
| `flutter test` | 28 项全部通过（原有 6 项 + 本次新增 22 项） |
| Android / iOS 设备完整退出重启 | 尚未执行，需按第 6 节人工验收 |

其中默认 `AppDatabase()` 的测试也已通过：只替换系统目录接口，真实执行后台连接、文件创建、关闭和重新读取。没有在这个测试中改用内存数据库，也没有访问真实用户沙盒。

即使本机静态检查和这些测试通过，也不应声称已经完成 Android / iOS 的人工真机验收。

## 8. GitHub 中应该保留什么

- 提交手写源码、测试、文档、依赖清单与 `pubspec.lock`。
- 沿用仓库“不提交生成物”的规则，`.g.dart` 不提交，但也不要手动编辑。首次克隆及数据库定义变更后执行 `dart run build_runner build`；GitHub Actions 同样先生成再检查。
- 不提交 `.dart_tool/`、`build/`、Flutter SDK、`.pub-cache/`、`work/` 或本机 `android/local.properties`。
- 不提交任何真实 `.sqlite` / `.db` 文件及其 journal、WAL、SHM 文件，它们可能包含私人梦境。.gitignore 已加入对应规则。

不要在 GitHub 网页上创建一个空的 `nightwalker.sqlite`。数据库由 App 第一次运行时在手机私有目录中自动建立。

## 9. 隐私和后续维护

当前 SQLite 文件没有加密，也没有本次新增的联网同步逻辑；“本地保存”不等于“已加密”或“操作系统不会备份”。Android/iOS 的系统备份策略、数据加密、导出和恢复需要在后续隐私设计中单独确认。磁盘满或文件不可写时应显示失败，而不是删除数据库后重试。

以后增加标签、心情等字段，既要修改表和重新生成代码，也要增加 `schemaVersion`、编写并测试迁移。不应通过卸载 App 或删除 SQLite 文件解决正式用户的结构升级问题。

后续建议先完成设备重启验收、真实错误场景验证与数据库迁移策略，再进入日历/历史记录；暂不把 AI 或健康数据接入混入本次存储任务。

参考资料：[Drift 安装与代码生成](https://drift.simonbinder.eu/setup/)、[Drift 原生数据库平台](https://drift.simonbinder.eu/platforms/vm/)、[Drift 测试](https://drift.simonbinder.eu/testing/)。本文中的工程路径和业务规则以本项目源码为准。
