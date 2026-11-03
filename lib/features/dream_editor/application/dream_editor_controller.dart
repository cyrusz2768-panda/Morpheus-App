import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

// 保持旧测试及现有调用方的导入路径可用；实际绑定统一放在 data 层。
// Controller 只依赖仓库接口对应的 Provider，不关心底层是 SQLite 还是测试替身。
export 'package:morpheus/features/dream_editor/data/dream_providers.dart'
    show dreamRepositoryProvider;

/// Exposes one DreamEditorController and its immutable state to the UI.
final dreamEditorControllerProvider =
    NotifierProvider<DreamEditorController, DreamEditorState>(
      DreamEditorController.new,
    );

/// Coordinates loading, editing, debounce timing and repository writes.
///
/// A controller should contain behavior but no Flutter widgets. This keeps the
/// save rules testable and prevents the page from becoming a large mixture of
/// visual layout and database operations.
class DreamEditorController extends Notifier<DreamEditorState> {
  static const _saveDelay = Duration(milliseconds: 800);

  Timer? _saveTimer;
  bool _saveInProgress = false;
  bool _anotherSaveRequested = false;
  int _loadRequest = 0;

  @override
  DreamEditorState build() {
    final today = DreamEntry.dateOnly(DateTime.now());

    // A Notifier's build method is synchronous. Schedule the asynchronous read
    // after the initial state exists so listeners can immediately render a
    // loading indicator.
    Future<void>.microtask(() {
      // 测试或路由退出可能在这个 microtask 执行前就销毁 Provider。
      // 销毁后不能再读取 ref 或修改 state。
      if (ref.mounted) {
        unawaited(load(today));
      }
    });

    // Providers may be destroyed during tests or future route changes. Cancel
    // the timer so it cannot call a disposed controller.
    ref.onDispose(() {
      _saveTimer?.cancel();
      _loadRequest += 1;
    });

    return DreamEditorState(date: today);
  }

  /// Loads the dream for [date] and makes it the active editor document.
  Future<void> load(DateTime date) async {
    if (!ref.mounted) {
      return;
    }

    // M1 只编辑当天记录；这里保留 date 参数，方便后续日历按天读取。
    // request 编号用于忽略较早完成的读取，防止旧请求回写新的页面状态。
    _saveTimer?.cancel();
    final request = ++_loadRequest;
    final normalizedDate = DreamEntry.dateOnly(date);
    state = DreamEditorState(date: normalizedDate);

    try {
      final repository = ref.read(dreamRepositoryProvider);
      final entry = await repository.getByDate(normalizedDate);

      if (!ref.mounted || request != _loadRequest) {
        return;
      }

      state = DreamEditorState(
        date: normalizedDate,
        content: entry?.content ?? '',
        isLoading: false,
      );
    } on Object catch (error) {
      if (!ref.mounted || request != _loadRequest) {
        return;
      }

      state = DreamEditorState(
        date: normalizedDate,
        isLoading: false,
        saveStatus: DreamSaveStatus.failed,
        errorMessage: '读取梦境失败：$error',
        failure: DreamEditorFailure.load,
      );
    }
  }

  /// Records a text change and restarts the automatic-save countdown.
  void contentChanged(String value) {
    // UI 会禁用输入框，但业务层也必须保护这条规则。测试或未来其他页面
    // 即使直接调用 Controller，也不能在读取失败后覆盖原来的磁盘记录。
    if (!ref.mounted || !state.canEdit) {
      return;
    }

    state = state.copyWith(
      content: value,
      saveStatus: DreamSaveStatus.unsaved,
      clearError: true,
    );

    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  /// Immediately persists the latest content.
  ///
  /// If a save is already running, a second request is remembered and executed
  /// afterwards. This prevents an older, slower write from overwriting newer
  /// text — a common asynchronous race condition.
  Future<void> saveNow() async {
    if (!ref.mounted || !state.canEdit) {
      return;
    }

    _saveTimer?.cancel();

    if (_saveInProgress) {
      _anotherSaveRequested = true;
      return;
    }

    _saveInProgress = true;

    try {
      do {
        _anotherSaveRequested = false;
        final contentToSave = state.content;
        final dateToSave = state.date;

        state = state.copyWith(
          saveStatus: DreamSaveStatus.saving,
          clearError: true,
        );

        final repository = ref.read(dreamRepositoryProvider);
        if (contentToSave.trim().isEmpty) {
          await repository.deleteByDate(dateToSave);
        } else {
          await repository.save(date: dateToSave, content: contentToSave);
        }

        if (!ref.mounted) {
          return;
        }

        // If the user typed while the write was running, keep "unsaved" and
        // loop again with the newer content.
        if (state.content != contentToSave) {
          _anotherSaveRequested = true;
          state = state.copyWith(saveStatus: DreamSaveStatus.unsaved);
        } else {
          state = state.copyWith(saveStatus: DreamSaveStatus.saved);
        }
      } while (_anotherSaveRequested);
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          saveStatus: DreamSaveStatus.failed,
          errorMessage: '保存梦境失败：$error',
          failure: DreamEditorFailure.save,
        );
      }
    } finally {
      _saveInProgress = false;
    }
  }

  /// Retries loading the active date after a read failure.
  Future<void> retryLoad() async {
    // 保存失败时禁止用这个入口重新加载：那会丢掉内存中尚未保存的草稿。
    if (!ref.mounted || state.failure != DreamEditorFailure.load) {
      return;
    }
    await load(state.date);
  }

  /// 页面“重试”按钮的统一入口；按失败发生的阶段决定重试哪个操作。
  Future<void> retryLastOperation() async {
    if (!ref.mounted) {
      return;
    }

    switch (state.failure) {
      case DreamEditorFailure.load:
        await retryLoad();
      case DreamEditorFailure.save:
        // 直接保存当前 state.content，不读取磁盘，所以草稿不会被旧记录覆盖。
        await saveNow();
      case null:
        return;
    }
  }
}
