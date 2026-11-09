import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/l10n/generated/app_localizations.dart';

export 'package:morpheus/l10n/generated/app_localizations.dart';

/// 本轮先集中管理中文，保留现有 zh_CN 的日期/时间选择器行为。
/// 未来加入经过审校的翻译后，再统一实现系统语言跟随和手动切换。
/// 不提前声明英文支持，避免标准组件变成英文而应用文字仍是中文。
const morpheusLocale = Locale('zh', 'CN');

/// Controller 和通知服务不在 Widget 树中，不能持有 BuildContext。
/// 通过 Provider 提供同一语言的生成资源，既可注入测试，也保留现有状态、
/// 异步保存与通知调度链路。未来动态切换语言时需一并处理错误提示刷新、
/// 已调度通知重排与 Android 渠道名称更新，不能只改 MaterialApp.locale。
final appLocalizationsProvider = Provider<AppLocalizations>(
  (ref) => lookupAppLocalizations(morpheusLocale),
);

/// 页面从 Localizations 读取资源；依赖随 Widget 生命周期管理。
/// 测试或新页面的 MaterialApp 也必须注册生成的 delegates，不能静默回退，
/// 否则容易掩盖本地化接线遗漏。
extension AppTextContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
