import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      routerConfig: router,
    );
  }
}
