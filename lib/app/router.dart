import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/features/dream_editor/presentation/dream_editor_page.dart';

/// Central navigation configuration.
///
/// The skeleton has only one page, but defining the router now prevents page
/// navigation from becoming scattered across button callbacks later. M2 can
/// add `/calendar`, and a settings milestone can add `/settings` here.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'dream-editor',
        builder: (context, state) => const DreamEditorPage(),
      ),
    ],
  );

  // GoRouter owns streams and listeners. Disposing it with the provider avoids
  // resource leaks during hot restart and automated tests.
  ref.onDispose(router.dispose);
  return router;
});
