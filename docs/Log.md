# 开发日志

## 2026-11-12

- 每日记录与验收后文字库经 GitHub 连接器直接发布为 `ab8bbec`，核验父提交 `0c3a00a` 与文件树完全一致；原本地提交 `a5c037c`／`8c87b22` 保留在 `codex/local-daily-record-upgrade`。发布后命令行 fetch 成功，本地主线已对齐远程。
- [GitHub Actions 43186106432](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/43186106432) 首次运行失败，实际使用自动更新的 Flutter 3.50.0，分析报 29 条旧 Material 导入及生成本地化类弃用信息，测试被跳过；不是本机 214 项测试失败。固定 CI 为本机已验收 Flutter 3.47.7，不改 App 依赖、界面或降低检查规则；后续运行单独核验，不把首次失败写为通过。

- 用户在 `a5c037c` 的每日记录功能交付后明确确认“ok，没问题”，授权上传 GitHub 并完成新增文字库收尾；记录为本轮 iOS 模拟器用户验收通过，不扩展为 Android／真机验收。以下本日“先不上传”记录是验收前阶段，已被本次授权覆盖。
- 验收后复核新增文案：全部用户可见标题、选项、按钮、动态评分、未填写与历史整句摘要均走 ARB，补齐多项因素分隔符并移除未使用摘要资源；当前 143 条，无重复键且语境说明齐全，中文显示保持不变。新增资源注入回归，验证名称、标点、动态分数及摘要可由资源提供。
- 2026-11-12 在 `a5c037c` 上实际执行 `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded`，全部通过，214 项。仅文案接线和文档收尾，未重复双端构建、未重新操作模拟器，沿用本日下列功能构建与用户验收证据。
- 发布前 `git fetch origin` 遇到 HTTP/2 错误，`git -c http.version=HTTP/1.1 fetch origin` 连接超时；授权 GitHub 连接器确认远程 main 仍为 `0c3a00a`。本次沿用连接器直接同步同一已验证文件树到主线，不创建 PR，不索要凭据；本地原提交保留在备份分支，远程父提交、文件树及 CI 在交付时核验，不将连接器发布说成命令行 push 成功。

- 基于 `0c3a00a` 开发每日记录升级，起始工作区干净，fetch 确认与 `origin/main` 一致。用户明确要求本轮不上传 GitHub，双端测试后只打开 iOS 模拟器供验收；统计升级留后续。
- Android／iOS 共用分类 → 正文 → 1–5 分主观评分 → 因素多选 → 结束回顾流程，支持各步跳过及返回修改。旧正文切换状态前保存并仅收起，睡眠评分未填保持 null，与好梦／噩梦独立。
- 数据库升至 v2，追加可空反馈及完成标记，保留 v1 原文、日期、UTC 时间。无正文但有状态／评分／因素的日期可从历史和日历找回；全跳过只保存完成标记，不进入历史圆点。统计仍只按非空正文计天。
- 新增中文教学注释、同步 ARB 与每日记录指南；修正当前状态、历史/月历/统计及 M1 指南中的过时存储说明。正文与反馈共用串行写入、800ms 防抖、导航等待与失败重试；增加步骤保存与通知切日隔离。
- 2026-11-12 实际执行 `flutter --no-version-check pub get`、`flutter --no-version-check gen-l10n`、`dart run build_runner build`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded`，全部通过，213 项。新增真实 v1 临时文件迁移、反馈重开与查询、完成恢复、评分约束、串行/并发保存、状态切换、跳过路径、历史回访、切日竞态与窄屏大字号回归。
- 双端调试构建通过：`flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`（Gradle 34.0 秒）、`flutter --no-version-check build ios --simulator --debug --no-pub`（Xcode 24.3 秒）。Android 本轮未启动模拟器或人工验收；iOS 安装启动与用户验收分别记录，不把构建或自动测试视作人工验收。
- 原 iPhone 18 Pro／iOS 27.2 已保留数据升级安装，实际运行 `flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定当前设备），Dart VM 连接成功。Device Hub 实际显示当天“你昨晚做了什么梦？”、四分类及底部跳过，窗口留给用户验收；未填写模拟器反馈或手工完成其余步骤，也未测试实际通知送达／点击。未上传 GitHub。


## 2026-11-11

- 本地功能提交 `88ac881`。推送前 fetch 与连接器均确认远程 main 为 `12703ac`，没有远程新增提交；实际命令 `GIT_TERMINAL_PROMPT=0 git -c http.version=HTTP/1.1 push origin main` 因缺少 GitHub HTTPS 登录失败。按本会话与仓库已有授权，改用 GitHub 连接器提交同一文件树；不索取凭据，不创建 PR，不将命令行 push 记录为成功。远程父提交、内容与 CI 在交付时核验。

- 用户最终明确确认“好的，验收通过”，授权将 Android／iOS 功能与文字库同步 GitHub；记录为统计回顾通知与设置卡片的 iOS 模拟器验收通过，无额外逐项清单，不扩大为 Android／真机验收。开发与验收基线为 `12703ac` 上的同一工作区，原 196 项测试和双端构建证据沿用本日下列实际记录，不因文档收尾重复构建。
- 验收后复核全部 112 条中文 ARB，确认无重复键、语境说明齐全；将消息通知／每周设置、通用通知及导航错误资源归入对应语境，稳定键和已验收文字不变。重新生成本地化资源并检查差异、文档链接及隐私排除，生成目录和构建产物不提交。按授权直接同步主线，实际远程结果在交付时核验。

- 根据用户验收反馈，在 `12703ac` 上的未提交统计回顾工作区继续调整通知设置；保留前轮源码、配置兼容及通知导航。每日提醒／每周回顾标题位于各自白色圆角卡片外，首行统一“消息通知”开关，关闭折叠时间／星期，重新开启恢复选择。关闭保存失败时保持已保存的开关和展开状态，不提前确认。
- 移除首尾说明、开关状态小字、系统通知栏和两个测试按钮；用户尝试开启时仍查询／申请系统权限，被拒绝时只在错误提示旁提供系统设置入口。页面保持原紫色主题，未改数据库、依赖或原生工程。删除 14 条不用的界面资源，新增消息通知标签并更新每周回顾标题及语境，当前 112 条中文 ARB。
- 更新页面交互测试及提醒／回顾／文案说明，最终验证和 iOS 模拟器展示结果待本轮收尾补充；按原约定继续等待用户最终验收后再提交推送。
- `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` 最终通过，完整 196 项；覆盖折叠后菜单导航、独立开关、时间恢复、关闭写入失败保持原状态、权限拒绝与窄屏大字号。格式、中文资源数量和本地 Markdown 链接已核对。首次 fetch 遇到 HTTP/2 网络错误，HTTP/1.1 重试成功，本地与远程主线无差异；本轮仍不提前推送。
- `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub` 与 `flutter --no-version-check build ios --simulator --debug --no-pub` 均通过（47.3 秒、41.2 秒）。使用 `flutter --no-version-check devices` 查询实际设备，并通过已构建 Runner.app 在原 iPhone 18 Pro / iOS 27.2 保留数据升级运行，Dart VM 已连接。实际点击三条杠菜单和通知设置，新卡片、外部标题、开关与原 08:00／周日 21:00 已显示，旧说明、系统栏及测试按钮消失；未改动真实开关/时间，也未人工验收通知送达，页面留给用户继续确认，尚未提交或推送。

## 2026-11-10

- 本轮基于干净主线 `12703ac` 开发 Android / iOS 统计回顾通知，fetch 确认本地与远程一致。用户明确要求 iOS 模拟器验收通过后再提交推送，本轮不提前上传。
- 在同一“通知设置”中新增独立回顾开关、星期与时间，默认关闭、周日 21:00；同一私有 JSON 原子保存，旧配置缺失字段只在内存补默认值，不改数据库、依赖或原生权限。共享系统权限，独立通知 ID/payload，支持关闭取消和失败补偿。新增中文教学注释及 9 条中文 ARB（合计 125 条），同步通用权限说明。
- 用户选择“周日就回顾当周，包含截至点击时的记录”。因此回顾通知打开点击时所在自然周（周一至周日），跨周点击打开最新周；明确起止日期，沿用当前周截至今天的统计分母。点击先 unfocus 并循环保存最新草稿，失败保留输入；冷启动、连续不同目标点击与统计页月／年切回周均走同一导航保护。
- 提供“发送回顾测试通知”，不改变任何开关；无需等待周日即可验证系统通知点击链路。自动测试 194 项已通过，平台构建及 iOS 启动结果继续补充，尚未标记人工验收通过。
- 本轮执行 `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded`，最终全部通过（194 项）。新增用例覆盖真实配置重开、旧字段兼容、独立调度、失败补偿、跨年/DST、Android/iOS 方法通道、冷启动、统计月／年重置及最新通知优先。测试使用人工内容和独立数据。
- `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub` 与 `flutter --no-version-check build ios --simulator --debug --no-pub` 通过，分别 32.3 秒和 30.4 秒。Android 未启动或人工验收，iOS 安装启动单独记录。同步提醒／统计／文案说明及新回顾指南，本地 Markdown 链接与 `git diff --check` 通过。
- 使用已构建 Runner.app 执行 `flutter --no-version-check run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定当次实际设备），在原 iPhone 18 Pro / iOS 27.2 保留数据升级启动。Dart VM 连接成功，Device Hub 中实际首页、日期与底栏已显示，窗口留给用户验收；本轮未操作通知设置、系统通知点击或等待实际定时送达，不记录为功能人工验收通过。代码、文案资源与文档保留在本地工作区，待用户确认后提交推送。
- 用户在本对话明确确认“验收成功，没有问题”，记录为周／月／年统计与底栏的 iPhone 18 Pro 模拟器验收通过，基线 `a058b54`。不扩展为 Android 或真机验收，也不补造逐项操作清单。
- 验收后在干净主线 `a058b54` 上完成文字库收尾，fetch 确认无远程新增提交。新增 31 条带语境和占位符说明的 ARB（总计 116 条），统计／底栏统一使用 `context.l10n`；动态日期、数量整句、周期选择、未来分桶及读屏标签由资源生成，复用原月份／星期／重试文案，保留已验收的中文显示与统计行为。
- `flutter --no-version-check gen-l10n`、`dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` 全部通过，完整 173 项。新增资源注入用例覆盖底栏标签、统计动态句式及趋势读屏接线；生成目录不提交。无原生配置或依赖变化，本次未重复双端构建或操作模拟器，沿用下列功能基线的原生构建证据。
- 统计功能远程交付为 `a058b54`，已核验父提交和文件树，GitHub Actions [运行 42656692297](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/42656692297) 成功。验收后收尾沿用本会话已确认的 GitHub 连接器主线交付方式；命令行 HTTPS 登录仍未配置，不声称再次执行成功的 push。

- 基于主线 `a234951` 开发周／月／年统计与底部导航，起始工作区干净；已执行 `git fetch origin` 并确认本地主线无落后提交。
- 新增 `IStatisticsRepository`、Drift 有效日期实时投影及独立聚合层。周一开周、自然月／年，统计记录天数、截至今天的覆盖率、双休日／平日占比、趋势及上期天数差；按 dreamDate 归属，补记落入旧周期、同日修改不重复计数、清空删除实时减少。趋势按日／本月裁切周／月分组，未来分组区别显示，空数据与读失败分别处理。无新依赖、数据库迁移或统计缓存。
- 新增实色圆角底栏「记录、统计、日历」，沿用既有紫色主题；顶级日历选日回编辑器，旧快捷选日保留为全屏选择器。顶栏／底栏／选日共用导航令牌，切换前循环 flush 最新草稿，失败留在原页；提醒通知撤销旧意图并持有导航锁，避免异步保存完成后跳回旧目标。
- 用户明确要求新增文字在验收成功后再同步资源，因此本轮新增统计／底栏文字暂不改 ARB，既有资源继续使用。好梦／噩梦记录尚未开发，首版省略该比例。此例外不改变后续默认文案规则。
- `dart format --output=none --set-exit-if-changed lib test`、`flutter --no-version-check analyze --no-pub`、`flutter --no-version-check test --no-pub --reporter expanded` 全部通过，完整 172 项，新增 22 项涵盖跨年周、闰月、当前短月末同期比较、真实 SQLite 补记／修改／删除及重开、页面重试／实时变更／大字号、实际底栏导航及通知竞态。测试均使用人工内容和独立测试数据。
- `flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub` 通过（Gradle 20.5 秒）；按用户要求，本轮 Android 不启动模拟器人工验收。
- `flutter --no-version-check build ios --simulator --debug --no-pub` 通过（Xcode 55.5 秒）；在原 iPhone 18 Pro 上保留数据升级安装，不卸载或清库。
- 新增 `docs/STATISTICS_GUIDE.md`，同步 README、PROJECT_STATUS 与 CHANGELOG；iOS 安装启动与主线交付结果继续记录如下，不把构建或自动测试标成人工验收完成。
- 使用已构建 Runner.app 在当前 iPhone 18 Pro / iOS 27.2 上保留数据升级启动。安装／启动服务等待后，实际窗口已显示周统计和「记录、统计、日历」底栏，留给用户验收；没有写入人工记录到用户沙盒，也未标记完整人工验收或真机验证完成。
- 本地功能提交 `5583ef1`。推送前再次 fetch 并核对远程 main，命令行 `git push origin main` 因无法读取 GitHub HTTPS 用户名失败；按已有授权改用 GitHub 连接器直接同步同一文件树到主线，不创建 PR。远程父提交、文件树与 CI 在交付时核验；不将本地 push 记为成功。

## 2026-11-09

- 基于最新主线 `66b6b0d` 开始集中管理当前版本文案，含当天新增的正文搜索。工作区起始干净；Git fetch 网络等待后终止，通过已授权 GitHub 连接器确认远程 main 与本地相同。
- 新增 `lib/l10n/app_zh.arb`（85 条带语境说明的中文资源）、`l10n.yaml` 与资源访问辅助代码，接入 Flutter gen-l10n。页面、日期/星期、读屏提示、菜单图标完整句子、Controller 错误与通知渠道/正文统一读取资源。当前保持中文，不宣称完整英文支持或语言选择完成；梦境正文、数据库版本、提醒 JSON、通知 ID/payload 和草稿保护流程不变。
- `intl` 由既有间接依赖改为直接依赖，锁定版本仍为 0.20.3，无依赖升级。生成目录不提交，本机和 CI 显式生成；新增 `docs/LOCALIZATION_GUIDE.md`，将“每次功能同步维护 ARB、每个功能检查遗漏、完整翻译按版本审校”写入 AGENTS.md。
- 本轮 `flutter pub get`、`flutter gen-l10n`、`dart run build_runner build`、`dart format --output=none --set-exit-if-changed lib test`、`flutter analyze --no-pub`、`flutter test --no-pub --reporter expanded` 通过，完整 150 项。Flutter SDK 查新等待超时后实际使用全局 `--no-version-check`。新增 3 项验证英文系统下中文接线、Controller 资源注入、Android 通知/渠道从资源生成；所有数据库测试继续使用独立测试数据。

- 文案集中管理双端调试构建通过：`flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub`（Gradle 18.6 秒）、`flutter --no-version-check build ios --simulator --debug --no-pub`（Xcode 30.2 秒）。本轮未安装启动或人工验收，不操作现有模拟器数据。

- 本轮命令行 `git push origin main` 因 GitHub HTTPS 低速网络超时失败，改用已授权 GitHub 连接器同步同一文件树到主线，不创建 PR；交付前后核验远程父提交与文件树，本地原提交保留在 `codex/local-l10n` 供追溯。实际远程提交及 CI 结果以 GitHub 核验为准。

- 在主线 `fa51ad5` 上新增双端共用的梦境正文搜索：首页 🔍 打开独立搜索页，自动聚焦并请求键盘，300ms 防抖，中文组词等待确认；结果按日期倒序，预览命中附近文字，点击后复用原编辑器。
- 独立只读搜索接口通过 Drift 查询既有表；绑定参数并转义通配符，不新增依赖、不改 schemaVersion 1、不保存搜索历史或上传正文。保持导航前最新草稿保存、保存失败保留输入、空白删除、通知返回当天及旧异步结果隔离。
- `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze --no-pub`、`flutter test --reporter expanded` 通过；完整 147 项，新增 13 项搜索测试。数据库测试使用独立临时文件/内存，不操作用户数据。
- 新增 `docs/SEARCH_GUIDE.md`，同步项目状态、README 与 CHANGELOG；下列记录区分原生构建、启动画面与待用户验收，不把自动测试视为人工验收。
- 双端调试构建通过：`flutter build apk --debug --target-platform android-arm64 --no-pub`（27.5 秒）、`flutter build ios --simulator --debug --no-pub`（Xcode 99.5 秒）。Android 未启动或人工验收；iOS 的实际安装启动见下条，未卸载或清除原设备数据。
- 原 iPhone 17 的系统桌面/安装服务等待，保留数据重启未立即恢复，改用 iPhone 18 Pro / iOS 27.2。等待备用设备首次初始化与系统索引完成后，安装启动成功；通过 `flutter run --no-pub --use-application-binary=build/ios/iphonesimulator/Runner.app`（指定实际设备）连接 Dart VM，实际首页与 🔍 已显示。窗口留给用户；搜索结果和系统键盘人工验收待确认，原设备数据未改动。
- 命令行 `git push origin main` 仍因缺少 HTTPS 登录失败；使用已授权 GitHub 连接器将相同文件树直接提交到 `main`，功能提交 `a2bb0c1`，未创建 PR。核验远程文件树与本地逐字节一致、fetch 后本地主线对齐；原未发布的本地提交保存在 `codex/local-dream-search`。GitHub Actions [运行 42565723874](https://github.com/cyrusz2768-panda/Morpheus-App/actions/runs/42565723874) 成功。

## 2026-11-08

- 复核本项目 48 轮历史对话、原始 M1 计划、代码及 GitHub 状态；区分 M1 基础本地记录、M2 历史/月历、M3 本地提醒与整个 Version 0.1。M1 核心开发和双平台模拟器基础验收已完成，独立的干净克隆双端完整手工复现记录待补。
- 新增根目录 `AGENTS.md` 与 `docs/PROJECT_STATUS.md`，固化中文教学、双端同步、单 checkout 单写入对话、验证证据、待办与新对话接手提示；现有专案已指向正式仓库，无需重建工程或复制聊天全文入库。
- 用户变更后续交付规则为验证后直接推送 `main`，不再默认创建 PR 或等待 partner；同步修正 README、规格协作说明、工具规则与功能指南。下面的 PR 流程记录保留为当天较早的历史决定。
- 本次仅整理文档与交付主线，不改运行代码；文档差异、链接、隐私排除与线上提交核验作为本轮检查，134 项测试及双端构建结果沿用最近功能验证记录，不声称重新执行。
- 本机命令行 `git push origin main` 因缺少 HTTPS 登录失败；主线同步改用用户已授权的 GitHub 连接器，发布内容仍为已验证功能与交接文档，不新建 PR，实际结果以远程核验为准。
- 补充 Android ARM64 调试 APK 构建检查，通过（98.2 秒）；本轮按用户要求不打开安卓模拟器进行人工验收。
- 用户授权将月历与菜单更新一并提交 GitHub PR。交付包含 134 项测试、格式检查和静态分析通过，以及 iOS 模拟器构建、保留数据升级安装和首次引导画面检查通过。
- 使用 `feature/calendar-markers` 提出改动，交给 partner 审查并手动合并；不直接更新 `main`，不上传设备数据、原生库缓存或构建产物。

## 2026-11-07

- 按验收反馈移除月历非空月份底部的重复说明；新增左上角菜单及占屏幕 82% 宽度的侧边抽屉，通知设置迁入带铃铛图标的菜单项。
- 新增带菜单图标的首次入口引导，独立保存 `menuHintSeen`；兼容旧提醒配置，不改写原来的提醒时间、开关和授权说明状态。格式检查、静态分析及 134 项测试通过，iOS 模拟器调试构建通过，等待人工验收。
- 确认 PR #4 已合并，从最新 `main` 创建本地 `feature/calendar-markers` 分支。
- 新增梦境月历记录圆点、月份切换、回到今天及快速选日，保持原页面风格和编辑器。
- 按月监听既有 SQLite 表，保存/删除后日期投影更新；进入月历前先保存最新草稿，失败时保留输入。无新依赖、无表结构或数据库版本变化。
- 补充中文教学注释、月历说明和数据/页面/导航测试；最终格式检查、静态分析与 117 项自动测试全部通过，覆盖月份边界、实时标记、错误重试、草稿保护及提醒返回当天。
- iPhone 17 模拟器调试构建通过（19.1 秒），保留原数据升级安装并启动。本轮按要求仅打开 iOS 模拟器；月历功能等待用户验收，之后再提交 PR 交给 partner 合并。

## 2026-11-06

- 确认 PR #3 已合并到 `main`；iOS 的 SQLite 官方原生库下载后通过 SHA-256 校验，重新构建、启动成功，开发者确认原有基础功能验收通过。本机构建缓存不上传。
- 从已合并的主分支建立本地 `feature/daily-reminders`，接入 Android/iOS 每日提醒、首次说明、延后授权、系统设置入口与测试通知。
- 使用私有 JSON 保存提醒时间、开关和说明已读状态；梦境数据库结构保持不变。通知点击包含冷启动、旧日期草稿保护和当天记录导航。
- 补充中文教学注释、提醒说明及测试；最终格式检查、静态分析与 90 项自动测试全部通过，包含原生插件方法通道、配置文件重开、权限拒绝、调度补偿、夏令时及通知导航。
- Android ARM64 调试 APK 构建通过（194.2 秒），保留原数据升级安装并启动，未发现该 App 的 Flutter/原生启动错误。iOS 在 iPhone 17 模拟器上构建通过（37.3 秒），升级安装、启动并连接 Dart VM 成功。
- 用户确认本轮每日提醒功能验收通过，并授权提交 PR；本次经 `feature/daily-reminders` 发布，交给 partner 在 GitHub 网页审查并手动合并。真机锁屏、长期后台与重启行为仍需后续验证。

## 2026-11-04

- Android SDK/NDK 已补齐，SQLite 官方 ARM64 原生库下载后通过 SHA-256 校验，调试 APK 已成功构建与启动；模拟器保留数据冷启动后恢复。开发者确认 M1 基本操作与保存重开测试通过。
- 在本地 `feature/date-history` 开发日期选择、历史列表、过去日期补记和回到今天，保留原页面主题与本地数据库结构。
- 切日前等待当前日期最新草稿保存；保存失败时留在原日期并保留草稿。新增存储、控制器与路由交互测试，补充中文教学注释和功能说明。
- 格式化、静态分析和 57 项自动测试通过；回归覆盖切日/打开历史的 await 间隙新输入，避免漏存末尾草稿。错误提示保留可直接点击的重试入口。
- 日期与历史功能 Android ARM64 调试 APK 构建通过，已在原模拟器保留数据升级安装、启动；开发者完成验收，并明确确认“验收通过，可以合并”。
- 本轮在开发者确认后通过 `feature/date-history` 发布，按 PR 和 GitHub Actions 检查流程合并；不上传模拟器数据或本机构建缓存。

## 2026-11-03

- 将本机 M1 Flutter 工程合并到现有仓库根目录，文档沿用 `docs/`，保留原 README、Apache 许可证、规格书、计划与历史日志。
- 接入 Drift / SQLite、自动保存与错误重试保护；新增源码、测试、依赖锁文件和 CI。
- 沿用生成物不提交的约定：`.g.dart` 在本机和 CI 通过 build_runner 生成；不上传 SDK、缓存、私有数据库或增量压缩包。
- 在本仓库副本中重新执行依赖恢复、Drift 代码生成、格式检查、静态分析和测试，28 项全部通过。Android 构建下载失败与双平台重启验收继续保留为待办。
- GitHub 授权已完成；本次改动通过 `feature/m1-sqlite` 分支发布，并提出 PR 供审查与合并。
- 已创建 PR #2；GitHub Actions 的代码生成、格式检查、静态分析与测试通过。复核时修正了源码中与仓库约定不一致的生成文件注释。

## 2026-09-23

- 新增 `LICENSE`（Apache License 2.0），与 README 许可证章节保持一致。
- 新增 `CHANGELOG.md`，按 Keep a Changelog 约定记录变更。
- 完善 `README.md` 项目说明。
- 新增规格书 `docs/Document.md` 与项目规则 `.trae/rules/project_rules.md`。
- 提交：`docs: 新增 LICENSE 与 CHANGELOG`、`docs: 补充开发日志`、`docs: 完善 README 项目说明`、`docs: 新增规格书 Document.md`、`chore: 添加项目规则文件`。
