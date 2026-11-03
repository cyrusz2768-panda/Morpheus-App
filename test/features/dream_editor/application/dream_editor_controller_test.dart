import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/dream_repository.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

void main() {
  group('DreamEditorController 的错误保护和保存顺序', () {
    test('保存失败后重试保存草稿，不重新读取磁盘旧内容', () async {
      final repository = _ScriptedRepository(savesToFail: 1);
      await repository.storage.save(date: DateTime.now(), content: '磁盘旧版本');
      final container = await _loadedContainer(repository);
      addTearDown(container.dispose);
      final controller = container.read(dreamEditorControllerProvider.notifier);

      controller.contentChanged('用户没有存好的新草稿');
      await controller.saveNow();

      var state = container.read(dreamEditorControllerProvider);
      expect(state.failure, DreamEditorFailure.save);
      expect(state.content, '用户没有存好的新草稿');
      expect(state.canEdit, isTrue);

      // 即使误调用旧的 retryLoad 接口，也不能因此覆盖新草稿。
      await controller.retryLoad();
      expect(repository.readCount, 1);
      expect(
        container.read(dreamEditorControllerProvider).content,
        '用户没有存好的新草稿',
      );

      await controller.retryLastOperation();
      state = container.read(dreamEditorControllerProvider);
      expect(state.saveStatus, DreamSaveStatus.saved);
      expect(state.failure, isNull);
      expect(state.errorMessage, isNull);
      expect(repository.readCount, 1);
      expect(
        (await repository.storage.getByDate(DateTime.now()))?.content,
        '用户没有存好的新草稿',
      );
    });

    test('读取失败不允许编辑、保存或删除原记录，读取重试成功后恢复编辑', () async {
      final repository = _ScriptedRepository(readFails: true);
      await repository.storage.save(date: DateTime.now(), content: '不能丢失的旧梦境');
      final container = await _loadedContainer(repository);
      addTearDown(container.dispose);
      final controller = container.read(dreamEditorControllerProvider.notifier);

      expect(
        container.read(dreamEditorControllerProvider).failure,
        DreamEditorFailure.load,
      );
      expect(container.read(dreamEditorControllerProvider).canEdit, isFalse);

      // 不能仅靠输入框 disabled；业务层被直接调用时也要守住不覆盖的规则。
      controller.contentChanged('误输入的新内容');
      await controller.saveNow();
      expect(repository.saveAttempts, isEmpty);
      expect(repository.deleteCount, 0);
      expect(
        (await repository.storage.getByDate(DateTime.now()))?.content,
        '不能丢失的旧梦境',
      );

      repository.readFails = false;
      await controller.retryLastOperation();
      final state = container.read(dreamEditorControllerProvider);
      expect(state.canEdit, isTrue);
      expect(state.failure, isNull);
      expect(state.content, '不能丢失的旧梦境');
    });

    test('一次写入尚未完成时继续输入，只串行写入最新草稿', () async {
      final repository = _ScriptedRepository();
      final container = await _loadedContainer(repository);
      addTearDown(container.dispose);
      final controller = container.read(dreamEditorControllerProvider.notifier);

      // Completer 可以控制异步写入何时完成，不需要用真实磁盘制造随机延迟。
      final firstWriteGate = Completer<void>();
      repository.nextSaveGate = firstWriteGate;
      controller.contentChanged('第一版');
      final saving = controller.saveNow();
      expect(repository.saveAttempts, ['第一版']);

      controller.contentChanged('最后一版');
      await controller.saveNow();
      expect(repository.saveAttempts, ['第一版']);
      expect(
        container.read(dreamEditorControllerProvider).saveStatus,
        DreamSaveStatus.unsaved,
      );

      firstWriteGate.complete();
      await saving;

      expect(repository.maximumConcurrentWrites, 1);
      expect(repository.saveAttempts, ['第一版', '最后一版']);
      expect(
        (await repository.storage.getByDate(DateTime.now()))?.content,
        '最后一版',
      );
      expect(
        container.read(dreamEditorControllerProvider).saveStatus,
        DreamSaveStatus.saved,
      );
    });

    test('清空文字按删除处理，而不是保存一条空白记录', () async {
      final repository = _ScriptedRepository();
      await repository.storage.save(date: DateTime.now(), content: '准备删除');
      final container = await _loadedContainer(repository);
      addTearDown(container.dispose);
      final controller = container.read(dreamEditorControllerProvider.notifier);

      controller.contentChanged('  \n  ');
      await controller.saveNow();

      expect(repository.deleteCount, 1);
      expect(repository.saveAttempts, isEmpty);
      expect(await repository.storage.getByDate(DateTime.now()), isNull);
      expect(
        container.read(dreamEditorControllerProvider).saveStatus,
        DreamSaveStatus.saved,
      );
    });

    testWidgets('销毁 Provider 会取消未到期的防抖计时器', (tester) async {
      final repository = _ScriptedRepository();
      final container = ProviderContainer(
        overrides: [dreamRepositoryProvider.overrideWithValue(repository)],
      );
      container.read(dreamEditorControllerProvider);
      await tester.pump();

      container
          .read(dreamEditorControllerProvider.notifier)
          .contentChanged('还没等到八百毫秒');
      container.dispose();
      await tester.pump(const Duration(seconds: 1));

      expect(repository.saveAttempts, isEmpty);
      expect(repository.deleteCount, 0);
    });

    testWidgets('初始读取的 microtask 执行前销毁，不再访问已销毁的 ref', (tester) async {
      final repository = _ScriptedRepository();
      final container = ProviderContainer(
        overrides: [dreamRepositoryProvider.overrideWithValue(repository)],
      );
      container.read(dreamEditorControllerProvider);
      container.dispose();

      await tester.pump();
      expect(repository.readCount, 0);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 每个测试有独立的 Riverpod 容器，对应一次独立的应用状态生命周期。
/// 等待一个事件循环，让 Controller 的初始化 microtask 和模拟读取完成。
Future<ProviderContainer> _loadedContainer(
  _ScriptedRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [dreamRepositoryProvider.overrideWithValue(repository)],
  );
  container.read(dreamEditorControllerProvider);
  await Future<void>.delayed(Duration.zero);
  return container;
}

/// 可控制故障、延迟的“测试替身”，并非正式应用的数据库实现。
/// 用这个替身可以稳定复现“磁盘暂时不可写”等情况，而不用真的把电脑磁盘填满。
class _ScriptedRepository implements DreamRepository {
  _ScriptedRepository({this.readFails = false, this.savesToFail = 0});

  final storage = InMemoryDreamRepository();
  bool readFails;
  int savesToFail;
  int readCount = 0;
  int deleteCount = 0;
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;
  final List<String> saveAttempts = [];
  Completer<void>? nextSaveGate;

  @override
  Future<DreamEntry?> getByDate(DateTime date) async {
    readCount += 1;
    if (readFails) {
      throw StateError('测试用读取故障');
    }
    return storage.getByDate(date);
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    saveAttempts.add(content);
    _activeWrites += 1;
    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }
    final gate = nextSaveGate;
    nextSaveGate = null;

    try {
      if (gate != null) {
        await gate.future;
      }
      if (savesToFail > 0) {
        savesToFail -= 1;
        throw StateError('测试用写入故障');
      }
      return await storage.save(date: date, content: content);
    } finally {
      _activeWrites -= 1;
    }
  }

  @override
  Future<void> deleteByDate(DateTime date) async {
    deleteCount += 1;
    await storage.deleteByDate(date);
  }
}
