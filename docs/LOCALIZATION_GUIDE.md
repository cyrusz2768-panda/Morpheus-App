# 界面文案与后续多语言开发

更新日期：2026-11-09。当前仅交付中文资源，适用于 Android / iOS 共用的 Flutter 功能。集中管理文案已接入，完整翻译与语言选择尚未开发。

## 当前范围

`lib/l10n/app_zh.arb` 是应用文案的手写来源，共 85 条资源，包含应用内标题、编辑器、历史、搜索、月历、菜单引导、提醒设置、错误提示、本地通知及 Android 通知渠道名称/说明。每项附中文语境说明，动态内容以有类型的占位符表达。

日期、月份、星期与月历读屏标签也由资源生成；显示继续沿用当前中文年月日、周一开头与 24 小时提醒时间。数据库日期键仍是 `yyyy-mm-dd`，不参与翻译。梦境正文、搜索词、通知 ID/payload、配置字段名和开发者诊断不属于翻译文案。编辑器错误消息保留原有技术异常详情，资源只管理提示句式。

iOS 桌面名称 `Morpheus` 位于 `ios/Runner/Info.plist`，Android 桌面名称 `morpheus` 位于 `android/app/src/main/AndroidManifest.xml`。它们由原生系统读取，仍保留原来的名称；正式确定品牌或支持其他语言时，再分别配置原生名称资源，不能认为 ARB 会自动改变桌面名称。系统权限弹窗由操作系统管理。

## 资源如何到达界面

```text
app_zh.arb + l10n.yaml
  → flutter gen-l10n
    → lib/l10n/generated/（不提交）
      → 页面：context.l10n
      → Controller：appLocalizationsProvider
      → 通知服务：构造时注入 AppLocalizations
```

采用 [Flutter 官方本地化与代码生成机制](https://docs.flutter.dev/ui/internationalization)，没有引入另一套翻译框架。`intl` 已是原依赖树的一部分，本轮仅把锁定的 0.20.3 声明为直接依赖，不升级版本。

`MaterialApp` 使用生成的 delegates 与 supportedLocales，当前只有中文；`morpheusLocale` 保持 `zh_CN`，不会因手机系统语言而切换。页面导入 `package:morpheus/l10n/app_text.dart`，用 `context.l10n.searchDreams` 等有语义的键取文案。应用根部的 `onGenerateTitle` 使用 MaterialApp 内部的 context；根 State 自己的 context 位于本地化节点上方，不能直接在那里取资源。

Controller 和平台服务不持有 Widget context。已有错误状态和异步保存链路保持原样，通过 Provider 获取资源。将来实现动态语言切换时，需统一处理资源 Provider、现有错误消息刷新、每日通知重排及 Android 渠道名称更新；只改 `MaterialApp.locale` 不足以完成多语言支持。

菜单教学在完整句子中使用 `{menuIcon}` 占位符，页面将它替换为真正的菜单图标。翻译应保留一次该占位符，可按语序移动，不把句子拆成固定中文前后缀。

## 开发时怎样维护

**每开发一个功能，就同步管理该功能的文字，不按开发百分比或累计功能数安排。**

1. 新增按钮、标题、提示、错误、读屏标签或通知文字时，同一功能改动中加入 ARB，并填写 `description`。同样含义可复用已有键，不同语境不要仅因中文相同就强行合并。
2. 动态日期、数量、时间、错误详情等用占位符；整句放在资源中，让未来翻译可以重排。不要在 Dart 页面里拼接中文片段。
3. 修改文案时改 ARB，运行生成；不要编辑生成的 Dart 文件。页面测试宿主也要注册真实 delegates，避免缺资源时静默回退掩盖问题。
4. 每个功能完成时检查本次 diff 有无遗漏的用户可见字符串，执行对应格式、分析和测试。无需为纯业务逻辑或数据库内部标识新增翻译键。
5. 新增语言、发布测试版或进行大范围 UI 调整时，再做全量文案审校与布局检查。届时确认支持语言、系统跟随/手动选择、术语与字体布局。

所以后续开发对话应直接按此约定维护资源；不需要用户每完成几项功能再专门回来安排一次提取。本对话可继续负责全量审查、翻译接入和语言切换。

## 生成与验证

首次克隆或依赖变化，在仓库根目录执行：

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
```

`flutter pub get` 在开启 `flutter.generate` 后会生成本地化代码；显式的 `flutter gen-l10n` 用于单独修改资源后的恢复与检查。CI 也明确执行此步骤。生成目录加入 `.gitignore`，源 ARB、配置与手写辅助代码入库。

代码改动按范围检查：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --target-platform android-arm64 --no-pub
flutter build ios --simulator --debug --no-pub
```

本轮基于 `66b6b0d`；实际检查结果见 [项目状态](PROJECT_STATUS.md) 与 [开发日志](Log.md)，不把构建或自动测试当作人工验收。本轮不操作真实梦境、不清理沙盒、不改数据库版本或提醒 JSON。
