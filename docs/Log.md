# 开发日志

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
