# Changelog

本文件记录 夜行者 / Morpheus 的重要变更。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Added

- 新增中文日期选择、过去日期补记、按日期倒序的历史列表及回到今天入口。
- 新增切日前保存等待与失败保护，以及历史查询、路由和日期切换测试。
- 新增 `docs/DATE_HISTORY_GUIDE.md`；标准组件中文翻译使用 SDK 的 `flutter_localizations`。
- 新增 Flutter Android / iOS 工程骨架、Riverpod / go_router 与当天梦境编辑器。
- 新增 Drift / SQLite 本地持久化、同日唯一、自动保存与删除流程。
- 新增数据库文件重开、默认后台连接、编辑器错误保护等测试。
- 新增 GitHub Actions 格式、代码生成、静态分析与测试检查。
- 新增 `docs/M1_SQLITE_GUIDE.md` 与 `docs/FLUTTER_PROJECT_SKELETON.md`，说明依赖、数据流及本机操作。
- 新增 `LICENSE`，采用 Apache License 2.0，与 README 许可证章节一致。
- 新增本变更日志文件。

### Fixed

- 保存失败重试不再重新读取旧内容覆盖草稿；读取失败时禁止误写或误删。
- 统一 Drift 生成文件的源码注释与仓库约定：本机和 CI 生成，Git 不跟踪。

### Notes

- Android M1 基本功能与持久化、日期选择及历史查看均已由开发者在模拟器中验收通过；iOS 验证仍待完成，不标记 M1 全部完成。
