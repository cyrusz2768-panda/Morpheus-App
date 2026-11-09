# 开发日志

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
