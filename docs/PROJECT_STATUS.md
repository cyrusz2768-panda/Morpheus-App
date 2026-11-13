# 项目状态与新对话交接

更新日期：2026-11-13。项目：夜行者 / Morpheus。本文记录当前状态；历史过程见 [开发日志](Log.md)，长期执行规则见 [AGENTS.md](../AGENTS.md)。后续任务结束时更新本文，不依赖旧聊天才能继续开发。

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

- **图片附件已发布到 main（2026-11-13）**：远程提交 [`821d8d3`](https://github.com/cyrusz2768-panda/Morpheus-App/commit/821d8d33e7038dfe2c39eed3238b8722a48f5b31)，父提交 `2a69db0`；完整文件树 `8a3c225a974d81202b14b847ee525810b07323d4` 与本地交付提交 `e4484bc` 完全一致，43个文件逐项blob SHA一致。经已授权连接器更新main，未创建PR或强推；原本地历史保留在 `codex/dream-image-attachments`，本地main已按准确Git对象SHA对齐远程。
- GitHub Actions [43377967034](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43377967034) 全部通过，包含依赖恢复、本地化/Drift生成、格式、分析与测试。沿用验收代码 `53d0236` 的本机270项测试和双端调试构建结果；CI本身不含原生构建或人工验收。本次发布后只补交付文档，以下“等待验收／尚未上传”为历史过程。

- **2026-11-13 用户确认图片附件及布局“验收通过，没有问题”，授权上传 GitHub。** 验收代码为 `53d0236`，图片功能基于 `1bf5e66`；原文、图片、仅图记录统计及完整展开布局均沿用同一已验证版本。本次只补验收/发布记录和文字库审校，不重做双端构建或操作模拟器。已复核159条中文资源无重复、语境齐全，图片8项文案全部接线；仅交付中文。下列“待验收／不合并／不上传”属于历史开发阶段，已被本次确认覆盖。
- 上传前命令行 fetch 低速超时，授权 GitHub 连接器确认远程 main 仍为 `2a69db0`，没有新增提交。按用户授权本地整合到 main 后发布，实际推送方式、远程内容与 CI 结果随后核验；Android 本轮仍仅构建检查，真机未验收，链接附件尚未开发。
- 本地已快进整合到 main；实际 `GIT_TERMINAL_PROMPT=0 git -c http.version=HTTP/1.1 -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=15 push origin main` 因缺少 GitHub HTTPS 登录凭据失败。按已有授权采用 GitHub 连接器发布相同文件树，不创建PR、不强推、不将其记为命令行push成功；原本地提交保留在 `codex/dream-image-attachments`，远程父提交、文件树与CI将实际核验。

- 2026-11-13 图片验收调整基于 `3c02ac4`：按用户截图移除正文区外框，图片完整展开并将加号及其下方控件（含保存提示）按自身高度向下推；正文步骤仅保留整页滚动，不再限制图片内部视口。工作区起始干净，本轮 fetch 成功，远程 main 无新增提交；继续等待用户验收，不合并或上传。最终完整270项测试、格式、分析和双端调试构建通过（Android 56.3秒、iOS 45.1秒）；包含横/竖图片的无外框、比例、位移和唯一页面滚动容器检查。
- 本次最终 iOS 用 `xcrun simctl install` 保留沙盒升级，`xcrun simctl launch --terminate-running-process` 启动，实际进入正文查看：外框已移除，原有横向图片完整显示，加号和继续按钮位于图片下方。未新增或移除模拟器图片，未做 Android 人工验收或真机测试；窗口停在正文图片页供用户继续验收。

- **历史开发阶段（2026-11-13）：相册图片附件，基于 `2a69db0`，分支 `codex/dream-image-attachments`，曾等待用户 iOS 验收，未整合或上传。** 此后用户已确认并授权发布，结果见本节最上方。链接附件未开发。开发中同步维护中文资源，验收后整体文案审校已完成。起始工作区干净；命令行 fetch 低速超时，授权连接器读取的远程 main 根目录文件/子树 SHA 与本地主线逐项一致。
- 图片采用私有文件 + v3 `images` 元数据，v1/v2 追加列无损升级；只有图片也算记录，历史/月历/统计活动按日期计入，同日多图去重。清空文字不会删图，已有反馈和完成标记继续保留。菜单、原比例缩略图、黑底放大、垃圾桶与长按移除共用 Controller 保存队列；Android lost-data 按原日期恢复。见 [图片附件说明](IMAGE_ATTACHMENTS_GUIDE.md)。
- 本地功能提交 `1bf5e66`；268项测试、格式、分析与最终双端构建通过。最终 iOS 构建已用 `xcrun simctl install` 保留沙盒安装，并用 `xcrun simctl launch --terminate-running-process` 重新打开，命令成功返回 App 进程。模拟器留给用户验收；尚未收到验收确认，没有推送或触发新 CI。

- 统计及图表现已发布到 main：功能提交 [`bca6713`](https://github.com/cyrusz2768-panda/Morpheus-App/commit/bca6713e3988a997849d8e01e5ee7587c939e31c)，父提交 `871725d`；远程完整文件树与已验证本地版本完全一致。GitHub Actions [43345986001](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43345986001) 全部通过。本地主线已按准确 Git 对象 SHA 对齐，原提交保留在 `codex/local-sleep-feedback-statistics-20261113`。下列“等待验收／尚未上传”均为历史阶段；此次发布通过授权连接器完成。
- 统计本地图表提交 `ccba4f6`，前一功能提交 `d436207`。本次命令行 push 遇到 GitHub 443 连接超时，改用已授权连接器发布同一文件树；不将其记为命令行 push 成功。原本地提交保留，远程父提交、内容与 CI 在交付时核验。
- 2026-11-13 用户确认当前结果并授权将统计升级及图表调整上传 GitHub。复核断连前的最终记录：250项测试、静态分析、格式及双端调试构建均通过，iOS 已实际查看周／月／年图表。代码保持同一已验证版本，本轮只补交付文档；fetch 成功，远程主线仍为 `871725d`，无新增提交。以下“先不上传”是开发验收阶段的历史安排，已被本次授权覆盖；发布结果与 CI 另行核验，不扩大为 Android 或真机验收。

- 2026-11-12 在本地 `d436207` 上继续调整统计验收反馈：月评分改为从1日起固定七日分组；三种周期折线图适应卡片宽度，不横向滚动；周状态改为“星期 × 四种状态”着色网格，未填及未来留空，月年仍为环图。工作区开始时干净；命令行 fetch 遇到网络低速超时，授权连接器确认远程 main 仍为 `871725d`。本轮继续仅本地开发，等待 iOS 用户验收，不上传。

- 2026-11-12 本轮统计升级基于 `871725d`，工作区开始时干净，fetch 确认与 `origin/main` 一致。按用户要求先本地开发、测试并打开 iOS 模拟器供验收，暂不上传。新增状态图与定性总结、评分均值和趋势、前三因素摘要。用户追加不展示天数或次数，故移除旧天数／覆盖率／记录趋势／周末指标界面；“没做梦”经用户确认单列蓝灰色，“未填写状态”保留灰色。

- 每日记录与文字库已通过连接器发布为 `ab8bbec`，父提交 `0c3a00a`，远程文件树与本地 `8c87b22` 完全一致；本地原提交保留在 `codex/local-daily-record-upgrade`。发布后命令行 fetch 恢复成功，本地 main 已对齐该远程提交。
- 首次 [CI 43186106432](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43186106432) 在分析阶段失败：工作流自动选用了 Flutter 3.50.0，全项目原有 Material 导入及生成本地化类出现 29 条弃用提示，测试步骤未执行。现将 CI 固定到双端构建已验收的 Flutter 3.47.7，不升级 App 依赖或迁移组件；修复提交 `32304e3` 的 [CI 43187115680](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43187115680) 已全部通过，包含 214 项测试；首次失败记录保留。

- 2026-11-12 每日记录升级基于 `0c3a00a`，本地功能提交 `a5c037c`。开发阶段按用户要求仅本地测试并打开 iOS 模拟器；用户同日确认“ok，没问题”，授权上传 GitHub 并完成文字库收尾。新增分类、正文、可空评分、因素与结束页；说明见 [每日记录](DAILY_RECORD_GUIDE.md)。本次记录为 iOS 模拟器用户验收通过，不扩展为 Android 或真机验收。
- 验收后复核文字库共 143 条，补齐因素分隔符、移除未使用摘要键并添加资源注入回归；完整 214 项测试、格式与静态分析通过。两次命令行 fetch 分别遇到 HTTP/2 错误和 HTTP/1.1 连接超时，已用授权 GitHub 连接器确认远程主线仍为 `0c3a00a`；本次沿用连接器直接同步 [main](https://github.com/cyrusz2768-panda/Morpheus-App/tree/main)，不创建 PR，不声称命令行 push 成功。发布前核对父提交，发布后核对文件树和 GitHub Actions，实际结果见本轮交付回复。

- 本轮本地功能提交 `88ac881`；命令行 `git push origin main` 因缺少 GitHub HTTPS 登录失败，按仓库已有授权改用 GitHub 连接器同步同一文件树，不创建 PR。发布前已确认远程 main 仍为 `12703ac`，远程父提交、文件树及 CI 以实际交付核验结果为准。

- 2026-11-11 根据验收反馈整理通知设置：每日提醒／每周回顾标题位于白色圆角卡片外，卡片首行为“消息通知”，关闭后折叠时间／星期，保留原设置。移除首尾说明、状态小字、系统通知栏及两个测试按钮；权限拒绝时保留按需系统设置入口。本轮基于 `12703ac` 的回顾功能工作区；用户已于 2026-11-11 明确确认“验收通过”，授权将 Android／iOS 共用功能及文案直接同步 GitHub 主线，不创建 PR。

- 本轮统计回顾通知开发基于 `12703ac`，2026-11-10 fetch 确认与远程 `main` 一致，起始工作区干净。新增独立每周开关、星期/时间、草稿保护与周统计通知目标；按用户确认，点击打开当前自然周，周日包含截至当时的记录。2026-11-11 用户最终确认 iOS 模拟器验收通过；Android 本轮为构建检查，真机与逐项手工操作不因本次确认而扩展记录。提交与远程结果按下列交付记录核验。
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
| 梦境编辑 | 每天一条，分类／正文／主观评分／因素引导、结束回顾，800ms 自动保存、相册图片附件；`lib/features/dream_editor/` |
| 草稿保护 | 串行保存、切日/导航前 flush、后台尽力提交；读失败禁用编辑，保存失败保留文字并重试 |
| 本地数据库 | Drift / SQLite，版本 3，v1/v2 追加列保留旧数据，私有支持目录 `nightwalker.sqlite`；`lib/core/db/`，`dream_editor/data/` |
| 日期与历史 | 补记过去日期、倒序列表、回到今天；`lib/features/dream_history/` 与编辑器导航 |
| 梦境搜索 | 首页 🔍、自动聚焦键盘、300ms 防抖正文连续匹配、结果选日；`lib/features/dream_search/`，详见 [搜索说明](SEARCH_GUIDE.md) |
| 梦境月历 | 月份切换、记录圆点、快速选日，按月监听数据库；`lib/features/dream_calendar/` |
| 周月年统计 | 周状态着色网格、月年五类环图，定性分析／比例、评分均值／整宽趋势、前三因素摘要；不直接显示天数／次数；`lib/features/dream_statistics/`，见 [统计说明](STATISTICS_GUIDE.md) |
| 底部导航 | 实色圆角「记录、统计、日历」；选日回记录，切页先保存，通知撤销旧导航意图；`lib/app/main_bottom_navigation.dart` |
| 侧边菜单 | 左上角菜单，82% 屏宽抽屉，带铃铛的“通知设置”；`dream_editor/presentation/widgets/` |
| 首次引导 | 菜单入口教学 `menuHintSeen` 和通知授权说明 `noticeSeen` 独立，首次教学不请求系统权限 |
| 每日提醒 | 分组卡片、独立消息通知开关、开启后展开时间、可延后授权与按需系统设置、点击回当天；`lib/features/reminders/` |
| 每周统计回顾 | 默认关闭、周日 21:00，独立星期/时间与开关；点击打开最新自然周，见 [回顾通知说明](WEEKLY_REVIEW_GUIDE.md) |
| 提醒配置 | 私有 JSON 原子保存，保留旧字段；系统权限实时重查，不永久信任旧权限状态 |
| 界面文案 | 159 条中文 ARB，含图片附件、每日记录、统计、底栏及回顾通知；页面、日期/读屏标签、Controller 提示与通知共用生成资源；`lib/l10n/`，见 [文案指南](LOCALIZATION_GUIDE.md) |
| 自动检查 | `.github/workflows/flutter_checks.yml`：依赖恢复、代码生成、格式、静态分析、测试 |

存储约定：本地 `yyyy-mm-dd` 日期主键，UTC 创建/更新时间；正文保留原格式，纯空白视为无正文；状态或睡眠反馈独立保留，无正文反馈、仅图片也进入历史与月历，图片同时计入统计活动。仅有完成标记的全跳过日期不展示历史圆点。当前数据库未加密。不要改包名、删除沙盒或重置模拟器来解决普通启动/升级故障。

当前身份为练习占位 `com.example.morpheus`，iOS 工程最低 15.0，Android SDK 基线沿用 Flutter 模板。正式发行身份、支持系统范围、证书和签名需单独确定。

## 4. 最近一次验证及其边界

| 日期 / 基线 | 检查 | 结果 |
|---|---|---|
| 2026-11-13，`2a69db0` 上图片附件工作区 | `flutter pub add image_picker:^1.2.4`、`flutter --no-version-check gen-l10n`、`dart run build_runner build` | 成功；SDK 查新超时后使用 `--no-version-check`；新依赖仅官方图片选择器及平台依赖，原锁定依赖不升级，生成物不提交 |
| 2026-11-13，同上 | `dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 最终全部通过，268项；覆盖 v1/v2 升级、私有图片重开、仅图统计、选图/保存/切日/启动通知竞态、失败保护及普通/两倍/三倍字号菜单；159条中文资源语境齐全且无重复键 |
| 2026-11-13，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub` | 最终通过，31.0秒；Android 未启动或逐项人工验收 |
| 2026-11-13，同上 | `flutter --no-version-check build ios --simulator --debug --no-pub` | 最终通过，36.0秒；模拟器手工操作边界见下一行，真机未验证 |
| 2026-11-13，同上 | 原 iOS 模拟器安装/启动，Device Hub 窗口检查 | 保留原沙盒升级，Dart VM 已连接；显示连接卡住后重启模拟器并重新启动 App，实际进入正文页、打开加号上方单行“添加图片”菜单。未在模拟器选/删照片或逐项重开图片，不标记用户验收通过；最终修复重装另记 |
| 2026-11-13，远程 `bca6713` | [GitHub Actions 43345986001](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43345986001) | 依赖恢复、文案／Drift 生成、格式、静态分析及测试全部通过；远程文件树与下列本机250项测试及双端构建的版本一致，CI 本身不含原生构建或人工验收 |
| 2026-11-12，`d436207` 上的图表验收调整 | `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，250 项；固定七日月分组含28／29／30／31日边界、当前组及未来排除、周逐日网格着色、月年环图保留、320宽普通／两倍／三倍字号完整显示且无横向滚动；151条中文资源语境齐全 |
| 2026-11-12，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`、`flutter --no-version-check build ios --simulator --debug --no-pub` | 最终双端通过（Gradle 25.7秒、Xcode 38.9秒）；Android 未启动或人工验收，iOS 安装及用户验收另记 |
| 2026-11-12，同上 | `flutter --no-version-check devices`、`flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定实际设备）及窗口操作 | 原 iPhone 18 Pro／iOS 27.2 保留数据升级，实际查看周网格、周评分、月固定分组、年12个月评分及月年环图，正常字号下无需横向滑动。停在全年评分图供用户验收；未修改记录，未手工测试辅助字号／通知送达／真机，不标记最终用户验收 |
| 2026-11-12，`871725d` 上的统计升级工作区 | `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，235 项；覆盖状态比例／定性边界、独立评分均值与缺口、前三因素和不确定、SQLite 更新／重开／错误、注入文案、窄屏大字号及回顾通知复用；148 条资源均有语境说明，无 schema 或依赖变化 |
| 2026-11-12，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`、`flutter --no-version-check build ios --simulator --debug --no-pub` | 双端通过（Gradle 39.7 秒、Xcode 98.7 秒）；Android 未启动或人工验收，iOS 安装及用户验收另记 |
| 2026-11-12，同上 | `flutter --no-version-check devices`、`flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定实际设备）与窗口操作 | 原 iPhone 18 Pro／iOS 27.2 保留数据升级运行，实际点击统计底栏，确认新版状态总结／图例、评分与因素区域显示，窗口留给用户。本轮未修改模拟器反馈、未手工逐项测试月年或系统通知，用户最终验收及真机验证待确认 |
| 2026-11-12，远程 `32304e3` | [GitHub Actions 43187115680](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43187115680)，Flutter 3.47.7 | 依赖恢复、文案／Drift 生成、格式、静态分析及 214 项测试全部通过；CI 不包含原生双端构建或人工验收 |
| 2026-11-12，`a5c037c` 上的验收后文字库收尾 | `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，214 项；143 条 ARB 无重复键、语境说明齐全，新增注入资源验证状态／因素名、分隔符、评分与摘要句式。不改中文显示，未重复双端构建或操作模拟器，沿用下列同日功能构建结果 |
| 2026-11-12，`a5c037c` | 用户确认“ok，没问题，上传github吧，然后合并新加入的文字到文字库” | 每日记录 iOS 模拟器用户验收通过，并授权双端源码及文字库同步主线；未新增逐项操作清单，不扩展 Android 或真机验收 |
| 2026-11-12，`0c3a00a` 上的每日记录工作区 | `flutter --no-version-check pub get`、`flutter --no-version-check gen-l10n`、`dart run build_runner build`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，213 项；覆盖 v1 文件无损升级、无正文反馈重开与历史/月历、评分约束、全部跳过完成恢复、串行写入、失败保护、步骤与切日竞态、窄屏大字号；生成文件不提交 |
| 2026-11-12，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`、`flutter --no-version-check build ios --simulator --debug --no-pub` | 双端通过（Gradle 34.0 秒、Xcode 24.3 秒）；Android 未启动或人工验收，iOS 启动另记 |
| 2026-11-12，同上 | `flutter --no-version-check devices`、`flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定当次实际 iOS 设备）及窗口检查 | 原 iPhone 18 Pro／iOS 27.2 保留数据升级启动，Dart VM 已连接，实际显示当天分类问题、四选项及底部跳过，页面已留给用户验收。本轮未在模拟器填写反馈、手工走完流程或验证系统通知点击，不标记最终用户验收或真机验证 |
| 2026-11-11，同一验收工作区 | 用户明确确认“好的，验收通过”，授权双端源码及文字库上传 GitHub | 统计回顾通知与设置卡片的 iOS 模拟器用户验收通过；未提供额外逐项清单，不扩展为 Android 或真机验收 |
| 2026-11-11，`12703ac` 上的回顾通知与卡片调整工作区 | `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，196 项；新增/调整卡片展开与折叠、移除旧入口、时间保留、保存失败保持展开、权限拒绝补救和窄屏大字号交互。中文资源当前 112 条；未提交或推送 |
| 2026-11-11，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`、`flutter --no-version-check build ios --simulator --debug --no-pub` | 双端通过（Gradle 47.3 秒、Xcode 41.2 秒）；Android 本轮未启动模拟器或人工验收 |
| 2026-11-11，同上 | `flutter --no-version-check devices`、`flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定实际设备）与窗口操作 | 原 iPhone 18 Pro / iOS 27.2 保留数据升级，Dart VM 连接成功；实际经三条杠菜单打开新版通知设置，两个外置标题、开关及原时间显示正确，无旧说明/系统栏/测试按钮。页面留给用户验收；本轮未手动切换开关或验收实际通知送达，不代表用户最终验收或真机通过 |
| 2026-11-10，`12703ac` 上的统计回顾通知工作区 | `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` | 全部通过，194 项；覆盖旧配置兼容、真实文件重开、独立开关/调度、失败补偿、夏令时、双端插件桥接、冷启动与草稿/通知竞态。中文资源总计 125 条，生成物不提交 |
| 2026-11-10，同上 | `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`、`flutter --no-version-check build ios --simulator --debug --no-pub` | 双端通过（Gradle 32.3 秒、Xcode 30.4 秒）；Android 本轮不启动模拟器，iOS 安装启动见后续记录，尚未用户验收或真机验证 |
| 2026-11-10，同上 | `flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定当次实际设备）与设备窗口检查 | 原 iPhone 18 Pro / iOS 27.2 保留数据升级启动，Dart VM 已连接，实际首页及底栏显示；模拟器窗口已打开供用户验收。本轮未手动操作通知设置、系统通知点击或定时送达，不标为功能人工验收通过；尚未提交／推送 |
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
- 本轮已接入状态比例、主观评分与因素摘要；旧天数指标不再展示。反馈与正文独立，未填状态不推断、未评分不记 0 分。2026-11-13 用户确认当前结果并授权上传；Android 人工验收、真机与真实通知验证仍未执行。

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
