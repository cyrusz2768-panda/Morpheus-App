# 每日提醒：实现说明与验收步骤

更新日期：2026-11-06。适用平台：Android 与 iOS。

## 功能与操作

编辑页右上角的铃铛进入“每日提醒”。第一次进入时，先显示关于系统通知的说明：

- “允许通知”：记住已经阅读说明，再请求系统通知权限。
- “稍后再说”：记住选择，本次不请求系统权限，梦境记录和历史查看继续可用。
- 后续可用“申请通知权限”再次申请，或“去系统设置”调整已经拒绝的权限。

授权本身不会自动开启每日提醒。用户自行设置时间、开启开关；默认时间为 08:00，默认关闭。时间和开关自动保存。“发送测试通知”立即发送一条测试消息，不改变每日提醒开关。

通知使用固定的通用文案，不包含用户的梦境正文。点击每日通知或测试通知，都打开当天的记录。若正在编辑另一天，会先等待草稿保存；保存失败则保留原日期和草稿。

## 语言与依赖

| 语言或依赖 | 本轮用途 |
| --- | --- |
| Dart / Flutter | 设置页面、首次说明、状态管理、调度和通知点击导航 |
| flutter_local_notifications 22.3.3 | Android/iOS 原生本地通知、权限查询和系统设置入口 |
| flutter_timezone 5.1.1 | 读取设备 IANA 时区，例如 Asia/Shanghai |
| timezone 0.11.2 | 计算当地下一次提醒时间，处理跨日及夏令时 |
| path_provider（已有） | 获取应用私有目录，保存提醒配置 JSON |
| Kotlin DSL / XML | Android Java API 脱糖、通知权限、重启恢复接收器和通知图标 |
| Swift | 在 AppDelegate 中连接 iOS 通知代理 |

选择通知插件 22.3 系列，是为了兼容当前 SDK 36 工程，同时包含 iOS 27 权限处理和夏令时修复。原生依赖仍通过 Flutter 的 Swift Package Manager 流程接入。

依赖已记录在根目录的 `pubspec.yaml` 和 `pubspec.lock` 中，拉取后在项目根目录运行 `flutter pub get` 即可恢复。原生依赖变化需要完整构建，再次 Hot Reload 不足以安装插件。

## 主要逻辑和目录

```text
提醒设置页面
  → ReminderController：串行处理授权、修改时间、开关和失败补偿
    → IReminderSettingsStore：私有 JSON 配置
    → IReminderNotifications：Android / iOS 通知插件

用户点击通知
  → App 层接收事件（含通知冷启动）
  → 等待梦境加载和最新草稿保存
  → 关闭设置/选择器，打开当天记录
```

- `lib/features/reminders/domain/`：设置模型及字段校验。
- `lib/features/reminders/data/`：文件读写、平台接口和本地通知实现。
- `lib/features/reminders/application/`：业务状态、权限结果和错误处理。
- `lib/features/reminders/presentation/`：首次说明、时间选择器和设置页面。
- `test/features/reminders/`：真实文件、时间边界、控制器、页面和原生方法通道测试。

设置保存到应用私有支持目录中的 `settings/reminders.json`，与梦境 SQLite 数据库分开。示例结构：

```json
{
  "notifications": {
    "enabled": false,
    "hour": 8,
    "minute": 0,
    "noticeSeen": true
  }
}
```

不把系统权限存入配置，因为用户随时可能在系统设置中撤销它。App 启动或返回前台会重新查询权限并同步已经保存的提醒。设置文件先写入临时文件、flush 后原子替换；读取损坏文件时展示错误，不静默覆盖。

每日提醒使用固定 ID，修改时间会替换同一任务。先更新系统调度，再保存配置；写入失败时尝试恢复原调度，并显示错误。清空、删除梦境不会改变提醒设置，提醒也不修改数据库表结构。

## 平台行为

Android 使用 `inexactAllowWhileIdle` 普通提醒，允许系统按节电策略调整送达时间，不申请额外的精确闹钟权限。Manifest 声明通知权限、重启权限及插件接收器，支持设备重启和应用升级后恢复已安排的提醒。

iOS 初始化阶段关闭自动授权请求。首次说明后，用户选择允许时，才申请提示和声音权限；不申请角标权限。AppDelegate 的通知代理支持前台显示和点击响应。本地通知不需要服务器推送证书或远程推送配置。

两端都可能受静音、专注/勿扰模式、通知渠道或系统节电策略影响。Android 在系统设置中“强行停止”应用后，需要重新打开才能恢复后续工作。切换设备时区后，重新打开 App 或返回前台会按当前时区重排提醒；本轮不实现 App 完全关闭期间的旅行时区实时同步。

## 本轮手工验收

以下步骤在 Android 和 iOS 各执行一次，使用测试内容即可。

1. 打开已有梦境记录，确认原数据仍然存在，点击右上角铃铛。
2. 首次应出现礼貌说明；选择“稍后再说”，确认不出现系统授权框，仍可返回记录梦境。
3. 再次进入设置，确认不重复出现说明。点击“申请通知权限”，在系统提示中允许；页面应显示“已允许通知”。如果拒绝，验证“去系统设置”可用，并确认原有记录功能不受影响。
4. 点击“发送测试通知”，确认能看到通知；测试本身不改变每日提醒开关。点击通知应回到当天记录。
5. 把提醒时间设为当前时间几分钟后，开启每日提醒，将 App 切到后台等待实际定时通知。Android 普通提醒可能延迟，需结合系统调度观察。
6. 修改提醒时间，确认只保留新的每日任务；关闭开关后，后续每日任务应被取消。
7. 完整退出、重新打开 App，进入设置，确认时间、开关和首次说明的已读状态仍然保留。
8. 在过去日期编辑测试文字，触发并点击通知，确认旧日期内容保留，当天内容对应正确。

真机上的锁屏、系统重启、长期节电和跨时区行为仍需实际验证；模拟器构建通过不等于这些场景全部通过。

## 开发验证与交付

```bash
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64 --no-pub
flutter build ios --simulator --debug --no-pub
```

本轮功能已通过用户验收，经 `feature/daily-reminders` 分支提交 GitHub PR，等待 partner 审查并手动合并。配置文件、数据库、原生库下载缓存和构建输出均不上传。

参考：[通知插件的版本说明与配置](https://pub.dev/packages/flutter_local_notifications/versions/22.3.3)、[设备时区插件](https://pub.dev/packages/flutter_timezone)、[时区计算](https://pub.dev/packages/timezone)。
