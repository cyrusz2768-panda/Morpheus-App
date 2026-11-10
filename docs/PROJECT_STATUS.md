# 项目状态与新对话交接

更新日期：2026-11-10。项目：夜行者 / Morpheus。本文记录当前状态；历史过程见 [开发日志](Log.md)，长期执行规则见 [AGENTS.md](../AGENTS.md)。后续任务结束时更新本文，不依赖旧聊天才能继续开发。

## 1. 当前结论

**M1 的基础功能开发与双平台模拟器基础验收已完成；严格的验收归档还有“全新克隆后双端完整手工复现清单”待补。统一状态：核心完成，验收归档待补。** 不把未单独留档的检查标成已经逐项执行。

项目实际已推进到 M2 的历史/月历与 M3 的本地提醒。整个 Version 0.1 尚未完成：健康数据、真机回归、隐私与导出、发行准备仍有工作。阶段定义沿用 [M1 原计划](<M1 基础工程与本地梦境记录>)，不能把 README 的 Phase 编号直接当作 M1–M5。

| 阶段 | 范围 | 当前情况 |
|---|---|---|
| M1 | 工程、当天编辑、自动保存、SQLite 持久化、基础测试与双端运行 | 核心完成；Android 11-04、iOS 11-06 的基础验收已有用户确认；干净克隆双端完整手工复现记录待补 |
| M2 | 日期选择、历史列表、月历回顾、正文搜索、基础周期统计 | 已实现并有自动测试；2026-11-10 用户确认统计与底栏 iOS 模拟器验收通过；搜索及其他平台证据见下文 |
| M3 | 用户设定时间的本地提醒 | 已实现，用户已确认此前双端提醒功能验收通过；真机长期后台等归后续验证 |
| M4 | HealthKit / Health Connect 技术验证及醒来提醒 | 未开始，不承诺实时检测醒来 |
| M5 | 真机回归、隐私完善与首轮内测发布 | 未完成；UI 打磨、正式身份与签名仍待安排 |

## 2. 代码与交付基线

- 2026-11-10 用户确认周／月／年统计与底栏在 iPhone 18 Pro 模拟器验收通过。验收基线为 `a058b54`，功能开发基于 `a234951`；本次收尾在 `a058b54` 上补齐新增文字 ARB，完整 173 项测试通过。Android 人工验收与真机验证不因本次确认而标记完成。
- 统计功能已通过已授权连接器同步主线 `a058b54`，远程父提交及文件树已核验，GitHub Actions [运行 42656692297](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/42656692297) 成功。命令行主线 push 因缺少 GitHub HTTPS 登录失败，本地原提交 `5583ef1` 等保留在 `codex/local-dream-statistics`。验收后文案收尾沿用连接器交付方式，不创建 PR。

- 仓库：[cyrusz2768-panda/Morpheus-App](https://github.com/cyrusz2768-panda/Morpheus-App)。现有本地专案“夜行者/Morpheus”使用此仓库根目录，无需重新创建工程或仓库。
- 2026-11-09 首轮文案交付的命令行 push 遇到 GitHub HTTPS 网络超时，采用已授权连接器同步相同文件树；本地原提交保留在 `codex/local-l10n`。
- 首轮文案集中管理基于主线 `66b6b0d`（包含搜索交付 `a2bb0c1`），当时完整 150 项通过；文案资源仍仅有中文，完整翻译与语言切换未开发。此前搜索的 147 项、月历/菜单的 134 项为各自历史测试数。
- 历史 PR：[#2 工程与 SQLite](https://github.com/cyrusz2768-panda/Morpheus-App/pull/2)、[#3 日期与历史](https://github.com/cyrusz2768-panda/Morpheus-App/pull/3)、[#4 每日提醒](https://github.com/cyrusz2768-panda/Morpheus-App/pull/4) 已合并；[#5 月历与菜单](https://github.com/cyrusz2768-panda/Morpheus-App/pull/5) 创建后检查通过。
- 本次交接整理以已验证的 #5 功能基线及交接文档为内容，直接整合到 `main` 交付。以后先核对实时 Git / GitHub 状态，不依据本文假定 PR 仍开放或提交号永远不变。
- 原始分步提交保存在本地 `backup/*-reviewed-*` 分支，不是另一套工程；保留以便追溯，不必重复开发或重复上传。
- 当前协作约定自 2026-11-08 生效：**完成开发 → 必要检查通过 → 本地整合到 `main` → `git push origin main`**，不默认创建 PR 或等待 partner 审核。

## 3. 已实现内容与代码入口

| 功能 | 实际行为与主要入口 |
|---|---|
| 应用与路由 | Flutter / Dart，Riverpod；`lib/app/router.dart` 包含 `/`、`/history`、`/search`、`/statistics`、`/calendar`、`/calendar-picker`、`/reminders` |
| 梦境编辑 | 每天一条，多行正文，800ms 自动保存；`lib/features/dream_editor/` |
| 草稿保护 | 串行保存、切日/导航前 flush、后台尽力提交；读失败禁用编辑，保存失败保留文字并重试 |
| 本地数据库 | Drift / SQLite，版本 1，私有支持目录 `nightwalker.sqlite`；`lib/core/db/`，`dream_editor/data/` |
| 日期与历史 | 补记过去日期、倒序列表、回到今天；`lib/features/dream_history/` 与编辑器导航 |
| 梦境搜索 | 首页 🔍、自动聚焦键盘、300ms 防抖正文连续匹配、结果选日；`lib/features/dream_search/`，详见 [搜索说明](SEARCH_GUIDE.md) |
| 梦境月历 | 月份切换、记录圆点、快速选日，按月监听数据库；`lib/features/dream_calendar/` |
| 周月年统计 | 记录天数、覆盖率、周末／平日比例、趋势及上期对比，按梦境所属日期实时派生；`lib/features/dream_statistics/`，见 [统计说明](STATISTICS_GUIDE.md) |
| 底部导航 | 实色圆角「记录、统计、日历」；选日回记录，切页先保存，通知撤销旧导航意图；`lib/app/main_bottom_navigation.dart` |
| 侧边菜单 | 左上角菜单，82% 屏宽抽屉，带铃铛的“通知设置”；`dream_editor/presentation/widgets/` |
| 首次引导 | 菜单入口教学 `menuHintSeen` 和通知授权说明 `noticeSeen` 独立，首次教学不请求系统权限 |
| 每日提醒 | 时间/开关、可延后授权、系统设置入口、测试通知、点击回当天；`lib/features/reminders/` |
| 提醒配置 | 私有 JSON 原子保存，保留旧字段；系统权限实时重查，不永久信任旧权限状态 |
| 界面文案 | 116 条中文 ARB，含已验收统计与底栏；页面、日期/读屏标签、Controller 提示与通知共用生成资源；`lib/l10n/`，见 [文案指南](LOCALIZATION_GUIDE.md) |
| 自动检查 | `.github/workflows/flutter_checks.yml`：依赖恢复、代码生成、格式、静态分析、测试 |

存储约定：本地 `yyyy-mm-dd` 日期主键，UTC 创建/更新时间；正文保留原格式，纯空白由编辑流程删除。当前数据库未加密。不要改包名、删除沙盒或重置模拟器来解决普通启动/升级故障。

当前身份为练习占位 `com.example.morpheus`，iOS 工程最低 15.0，Android SDK 基线沿用 Flutter 模板。正式发行身份、支持系统范围、证书和签名需单独确定。

## 4. 最近一次验证及其边界

| 日期 / 基线 | 检查 | 结果 |
|---|---|---|
| 2026-11-10，`a058b54` 上的验收后文案收尾 | `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，173 项；新增资源注入测试验证底栏、统计动态句式及趋势读屏接线。当前仍仅中文。本次无原生配置变更，未重复双端构建或操作模拟器，原生构建证据为下列功能基线 |
| 2026-11-10，`a058b54` | 用户在本对话确认“验收成功，没有问题” | 周／月／年统计与底栏的 iPhone 18 Pro 模拟器验收通过；没有额外逐项操作记录，不扩展为 Android 或真机验收 |
| 2026-11-10，`a234951` 上的统计与底栏 | `dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，172 项（新增 22 项）；覆盖日期口径、真实 SQLite、实时变更、错误重试、窄屏大字号、导航草稿保护及通知竞态 |
| 2026-11-10，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub` | 通过（Gradle 20.5 秒）；本轮未启动 Android 或人工验收 |
| 2026-11-10，同上 | `flutter --no-version-check build ios --simulator --debug --no-pub` | 通过（Xcode 55.5 秒）；模拟器安装启动及用户验收结果分别记录 |
| 2026-11-10，同上 | `flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定当前设备）及模拟器窗口检查 | 原 iPhone 18 Pro / iOS 27.2 保留数据升级启动，实际显示统计页面与三项底栏；随后用户验收确认见上行，不代表真机验证 |
| 2026-11-09，`66b6b0d` 上的文案集中管理 | `flutter pub get`、`flutter gen-l10n`、`dart run build_runner build`、`dart format --output=none --set-exit-if-changed lib test`、`flutter analyze --no-pub`、`flutter test --no-pub --reporter expanded`（Flutter 实际带 `--no-version-check`，SDK 查新超时后使用） | 全部通过，150 项；覆盖英文系统下保持中文及 Controller/通知注入资源 |
| 2026-11-09，同上文案集中管理 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`、`flutter --no-version-check build ios --simulator --debug --no-pub` | 双端构建通过（Gradle 18.6 秒、Xcode 30.2 秒）；本轮未安装启动、人工操作或真机验收 |
| 2026-11-09，`fa51ad5` 上的搜索改动 | `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze --no-pub`、`flutter test --reporter expanded` | 全部通过，147 项；新增 13 项覆盖真实 SQLite、异步结果、输入法确认、焦点与导航草稿保护 |
| 2026-11-09，同上 | `flutter build apk --debug --target-platform android-arm64 --no-pub`、`flutter build ios --simulator --debug --no-pub` | 双端构建通过（Android 27.5 秒、Xcode 99.5 秒）；Android 未启动或人工验收 |
| 2026-11-09，`a2bb0c1` | [GitHub Actions 运行 42565723874](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/42565723874) | `Flutter checks` 成功；不含原生构建或人工验收 |
| 2026-11-09，同上 | iPhone 18 Pro / iOS 27.2 安装、`flutter run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（运行时使用实际设备参数） | Dart VM 连接成功，实际首页与 🔍 入口已显示，留给用户验收。搜索结果/系统键盘尚待用户实际操作确认；原 iPhone 17 数据保留 |
| 2026-11-03，M1 初版 | 依赖恢复、Drift 生成、格式、分析、28 项测试 | 通过，PR #2 CI 通过 |
| 2026-11-04 | Android 基础记录、保存重开；随后日期/历史 57 项测试 | 用户确认基础功能与日期/历史验收通过 |
| 2026-11-06 | iOS 基础记录与日期/历史；每日提醒 90 项测试、双端构建启动 | 用户确认基础功能及本轮提醒验收通过 |
| 2026-11-07，月历与菜单实现 | Dart 格式、静态分析、完整 134 项测试 | 全部通过；覆盖数据库真实文件重开、导航草稿、月历与首次引导 |
| 2026-11-07 | iPhone 模拟器调试构建、保留数据升级安装启动 | 通过，实际画面显示菜单及首次引导 |
| 2026-11-08 | Android ARM64 调试 APK | 构建通过（98.2 秒）；本轮未启动 Android 模拟器人工验收 |
| 2026-11-08，`a7c8c4e` | PR #5 的 GitHub Actions，运行 13 | `Flutter checks` 成功；干净 checkout 恢复依赖、生成并检查 Dart 代码 |

以上证据仅适用于各自日期和代码基线，后续代码变化需按影响范围重新检查。CI 不构建 Android / iOS，不能把绿色 CI 当作原生构建或真机验证。

M1 原计划的逐项审计：

- 工程、主题、路由与状态管理：源码存在，双端已运行。
- 当天记录创建/读取/更新/删除、同日去重：Repository 与 SQLite 测试覆盖。
- 关闭连接/容器后从同一真实文件恢复、清空后重开不复活：数据库与 Provider 测试覆盖。
- 自动保存、后台最新草稿、读取/保存失败与重试：Controller 与页面测试覆盖。
- 用户基础验收：Android 2026-11-04、iOS 2026-11-06 已确认。
- 文档、隐私排除项与 CI：本次整理补齐状态与规则；构建产物、真实数据库和个人数据不入库。
- **尚未单独留档：从全新克隆在两个平台逐项重跑完整手工清单。** CI 已证明干净 checkout 的依赖、生成与 Dart 检查，但不替代此项。补齐后可将 M1 状态改为“验收归档完成”。

## 5. 已知边界与待办

- 统计与底栏已由用户在 iPhone 18 Pro 模拟器验收通过，按约定补齐 31 条新增文案及资源接线；本轮延后同步的临时例外已收尾，后续仍默认随功能维护 ARB。
- 当前无好梦／噩梦记录字段，统计首版省略该板块；周末仅指周六／周日，不含法定调休。

优先收尾：

1. 补一份干净克隆的双平台复现记录，沿 [M1 计划](<M1 基础工程与本地梦境记录>) 的测试清单记录环境与结果；使用独立测试安装，不清除已有个人梦境。
2. 安排真机通知回归：锁屏、前后台、长时间节电、重启与切换时区。Android 当前采用普通非精确提醒，不能保证分钟级准点。
3. 确定隐私与数据保护方案：系统备份策略、用户导出/恢复、数据库加密取舍、隐私说明；这些还没有完整实现。
4. 正式包名、签名、发行配置及内测安排；UI 整体打磨按用户要求后置。

其他已知边界：

- 系统强杀前尚未落盘的输入不能保证恢复；先看到“已保存”再重开才是持久化验收。
- 历史列表与搜索当前无分页；正文搜索是本地连续文字匹配，不含拼音、分词或全文索引。跨午夜不会自动切换正在编辑的文档日期。这些是能力边界，不代表记录已丢失。
- 未实现健康数据或手表接入、AI、账号、云同步、标签/心情、富文本。不要因为旧规划提及就自行立项。
- “每次未设提醒都弹提示”是早期设想；最新实现按用户要求改成一次性菜单入口引导，系统授权说明在首次进入提醒设置时单独展示。

文案维护按每个功能同步更新 ARB、每次交付检查遗漏执行，不积攒固定开发进度；完整翻译按版本另行安排，见 [文案指南](LOCALIZATION_GUIDE.md)。

用户已于 2026-11-09 授权并开展正文搜索开发，用户验收仅打开 iOS 模拟器；Android 做构建检查。后续继续按一个明确目标推进。可补 M1 验收归档或安排 M5 真机/隐私收尾；健康数据与 AI 仍需单独任务，不因旧规划自行开展。

## 6. 本机环境与已解决问题

最近验证环境：Flutter 3.47.7 / Dart 3.13.5；macOS arm64、完整 Xcode 27.2 与 iOS 27.2 模拟器；Android SDK Platform 36、NDK 28.2.13676358 与 ARM64 模拟器。平台最低版本与当前构建 SDK 不是同一概念；实际环境用工具查询，不把这些数字当成未来必须升级的指令。

- SDK、Xcode、Android 组件此前的缺失已补齐，不需要每个新对话重新安装环境。
- 本机命令行 Git 的 HTTPS 登录尚未配置，2026-11-08 的实际 `git push origin main` 返回无法读取用户名；GitHub 连接器已授权。本次主线同步使用连接器，仍直接交付 `main`，不创建 PR。以后如要使用命令行 push，先配置本人 Git 登录；不要把连接器成功当作命令行已登录。
- SQLite 原生库曾因 GitHub 下载中断导致双端构建卡住，已从官方来源下载并校验后恢复。本机缓存不入库；换机仍可能需要联网下载。
- Flutter startup lock 曾由另一个 Flutter 进程占用；先识别现有进程，避免同时运行多条 Flutter 命令或盲删锁文件。
- 模拟器曾有系统 UI/安装服务等待；保留数据重启后已恢复。故障恢复不要以卸载或清空数据作为第一步。
- 2026-11-09 原 iPhone 17 再次出现系统 UI/安装等待，保留数据关闭后改用 iPhone 18 Pro；备用设备首次初始化/系统索引耗时较长，等待后正常安装、启动并显示首页。当前 Xcode 的模拟器前端是其应用目录中的 Device Hub，不能假定旧版 Simulator 应用路径仍存在。未清空、卸载或迁移原设备数据。
- Java 原生访问或 SDK 版本警告需要结合最终错误判断；曾出现的下载失败才是当时的直接阻塞，不为消除警告擅自改动依赖源码。

## 7. 新对话开始和结束

在专案中保留一个规划/学习对话；每个功能在独立开发对话完成整个实现与交付。默认同一 checkout 一次只有一个写入对话；需要并行时使用隔离分支和 worktree，再统一整合。

新对话可复制：

> 继续开发 Morpheus。先读 AGENTS.md、docs/PROJECT_STATUS.md、docs/Log.md 最近记录及 README，核对当前代码、分支、工作区和远程状态。本次目标是【填写目标】，完成条件是【填写可检查结果】。保持中文教学注释、Android/iOS 同步；执行相应验证后更新交接文档并直接推送 main，不创建 PR。用户验收默认只打开 iOS 模拟器，Android 做构建检查；如本次另有要求，以本次要求为准。

结束前记录：实现范围、实际验证、未执行项、已知限制、下一步，以及交付提交/链接。历史日志只追加，旧决定明确标为历史，不抹掉当时的事实。

本地保存和远程同步分别核实：

```bash
git status --short
git branch --show-current
git log -3 --oneline
git fetch origin
git rev-list --left-right --count HEAD...origin/main
```

工作区应无意外改动；计划交付的 `main` 应与远程一致。若网络或认证失败，明确记录“仅本地保存/未同步”，不能把 commit 当成 push 成功。
