import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:morpheus/app/router.dart';
import 'package:morpheus/app/theme.dart';

/// The root widget of the application.
///
/// This widget owns application-wide concerns: routing, theme and the title
/// shown by the operating system. Feature-specific behavior does not belong
/// here; for example, saving a dream is handled by DreamEditorController.
class MorpheusApp extends ConsumerWidget {
  const MorpheusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reading the router through a provider makes it disposable and replaceable
    // in tests. `watch` rebuilds this widget if the provider ever changes.
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: '夜行者',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 当前练习项目以中文为默认语言。SDK 的 delegate 负责日期选择器等
      // 标准组件的本地化，避免出现页面中文、月份和星期却为英文的混用。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
