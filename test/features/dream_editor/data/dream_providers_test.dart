import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';

void main() {
  test('正式 Provider 装配通过 SQLite 保存，容器重建后编辑器自动恢复正文', () async {
    // ProviderContainer 相当于不包含界面的 ProviderScope。
    // 这个测试连接真正的 Controller、默认 Repository 绑定和 SQLite 文件，
    // 避免出现“单独测试数据库没问题，实际 App 却仍然绑定内存仓库”的遗漏。
    final directory = await Directory.systemTemp.createTemp(
      'morpheus_provider_test_',
    );
    final file = File('${directory.path}/dreams.sqlite');
    const dream = '关闭应用，再次打开，仍然看得见这座月亮图书馆。';

    try {
      final savedDate = await _withStorageContainer(file, (container) async {
        final database = container.read(appDatabaseProvider);
        final repository = container.read(dreamRepositoryProvider);

        // 我们只替换数据库路径，没有 override dreamRepositoryProvider。
        // 因此这几条断言同时检查“正式装配已经切换成 Drift”和“连接被复用”。
        expect(repository, isA<DriftDreamRepository>());
        expect(container.read(appDatabaseProvider), same(database));
        expect(container.read(dreamRepositoryProvider), same(repository));

        final initial = await _waitForInitialLoad(container);
        expect(initial.content, isEmpty);
        expect(initial.canEdit, isTrue);

        final controller = container.read(
          dreamEditorControllerProvider.notifier,
        );
        controller.contentChanged(dream);
        await controller.saveNow();

        final savedState = container.read(dreamEditorControllerProvider);
        expect(savedState.saveStatus, DreamSaveStatus.saved);
        expect(savedState.content, dream);
        expect((await repository.getByDate(savedState.date))!.content, dream);
        expect(
          await database.select(database.dreamRecords).get(),
          hasLength(1),
        );
        return savedState.date;
      });

      // 到这里，第一份 Controller、ProviderContainer 和连接都已经销毁/关闭。
      // 测试仅验证已完成 saveNow 的数据，不声称系统强杀时还能等待未完成保存。
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));

      await _withStorageContainer(file, (container) async {
        final restored = await _waitForInitialLoad(container);

        // Controller.build() 会自动加载当天记录；这里没有手动调用 Repository
        // 把结果塞回 UI 状态，因此也覆盖了应用重开后的初始化读取链路。
        expect(restored.date, savedDate);
        expect(restored.isLoading, isFalse);
        expect(restored.failure, isNull);
        expect(restored.content, dream);

        // 再通过编辑器清空正文并保存，验证删除也走正式持久化绑定。
        final controller = container.read(
          dreamEditorControllerProvider.notifier,
        );
        controller.contentChanged('   \n');
        await controller.saveNow();
        expect(
          container.read(dreamEditorControllerProvider).saveStatus,
          DreamSaveStatus.saved,
        );
      });

      await _withStorageContainer(file, (container) async {
        final restoredAfterDeletion = await _waitForInitialLoad(container);
        expect(restoredAfterDeletion.content, isEmpty);
        final database = container.read(appDatabaseProvider);
        expect(await database.select(database.dreamRecords).get(), isEmpty);
      });
    } finally {
      // 只删除这个测试自己创建的随机临时目录，不涉及正式数据库或用户文件。
      await directory.delete(recursive: true);
    }
  });
}

/// 用同一文件创建一套全新的依赖容器，模拟一次完整的应用生命周期。
Future<T> _withStorageContainer<T>(
  File file,
  Future<T> Function(ProviderContainer container) action,
) async {
  final database = AppDatabase(NativeDatabase(file));
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  try {
    return await action(container);
  } finally {
    // overrideWithValue 使用测试提供的对象，不会运行被替换工厂里的 onDispose。
    // 所以测试自己负责关闭这个数据库，并且明确 await 完成后才重新打开文件。
    container.dispose();
    await database.close();
  }
}

/// 等待 Controller 的首次异步读取完成，而不是用固定 sleep 猜测运行速度。
///
/// fireImmediately 同时兼容“读取已经结束”和“仍在等待 SQLite”两种情况；
/// timeout 让初始化出问题时尽快报出明确测试失败，而不是永久等待。
Future<DreamEditorState> _waitForInitialLoad(
  ProviderContainer container,
) async {
  final loaded = Completer<DreamEditorState>();
  final subscription = container.listen(dreamEditorControllerProvider, (
    previous,
    next,
  ) {
    if (!next.isLoading && !loaded.isCompleted) {
      loaded.complete(next);
    }
  }, fireImmediately: true);
  try {
    return await loaded.future.timeout(const Duration(seconds: 10));
  } finally {
    subscription.close();
  }
}
