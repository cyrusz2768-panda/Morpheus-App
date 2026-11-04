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
  // saveNow 的重复调用仍然立即返回；需要真正等待写入完成的“离开页面 / 切日”
  // 操作用这个完成信号。两种语义分开，避免后台保存与日期切换互相死锁。
  Completer<void>? _saveCompletion;
  bool _dateChangeInProgress = false;
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
        unawaited(_readDate(today));
      }
    });

    // Providers may be destroyed during tests or future route changes. Cancel
    // the timer so it cannot call a disposed controller.
    ref.onDispose(() {
      _saveTimer?.cancel();
      _loadRequest += 1;
      // 仓库写入可能仍在等待系统 IO；页面已经销毁时，导航等待方可以立即
      // 结束并返回失败，而无需等待一个不再影响页面的旧任务。
      final completion = _saveCompletion;
      if (completion != null && !completion.isCompleted) {
        completion.complete();
      }
    });

    return DreamEditorState(date: today);
  }

  /// 保留已有调用入口，但所有主动切换日期都必须先保护当前草稿。
  /// 新页面需要知道切换结果时应使用 [selectDate]。
  Future<void> load(DateTime date) async {
    await selectDate(date);
  }

  /// 真正等待当前日期的最新草稿写入完成，供打开历史和切换日期使用。
  ///
  /// 这里不能只写 `await saveNow()`：如果已有写入任务，saveNow 的约定是
  /// 记住请求后立即返回，并不意味着磁盘已写完。必须等待完成信号；若等待
  /// 期间又输入了新文字，还要确认最后一版也保存成功，才能离开当前日期。
  /// 保存失败返回 false，保留草稿和错误提示，由用户决定何时重试。
  Future<bool> flushPendingSave() async {
    if (!ref.mounted || state.isLoading) {
      return false;
    }

    _saveTimer?.cancel();
    while (ref.mounted) {
      if (state.isLoading) {
        return false;
      }
      if (_saveInProgress) {
        await _saveCompletion!.future;
      } else if (state.hasPendingSave) {
        await saveNow();
      } else {
        // 初次进入的空编辑器、已经保存的内容以及读取失败时都没有可写草稿。
        // 不为“查看历史”凭空执行一次 DELETE 或重复保存。
        return true;
      }

      if (!ref.mounted || state.failure == DreamEditorFailure.save) {
        return false;
      }
      // 状态监听者也可能在“已保存”通知时提交新输入；再次检查 pending 状态，
      // 比只等待一次 Future 更稳妥，避免最后一小段文字被后续读取覆盖。
    }
    return false;
  }

  /// 安全切换到另一日期；同一天的重复选择不会重读或覆盖当前草稿。
  ///
  /// 同一时间只接受一次切换。保存失败时不改日期、不清空草稿；新日期读取
  /// 失败时则显示该日期的只读错误状态，可继续使用现有“重试”按钮恢复。
  Future<bool> selectDate(DateTime date) async {
    if (!ref.mounted || state.isLoading || _dateChangeInProgress) {
      return false;
    }
    final normalizedDate = DreamEntry.dateOnly(date);
    if (normalizedDate == state.date &&
        state.failure != DreamEditorFailure.load) {
      return true;
    }

    _dateChangeInProgress = true;
    try {
      do {
        if (!await flushPendingSave() || !ref.mounted) {
          return false;
        }
        // 即使 flush 当时没有草稿，它返回 Future 时仍会让出一次执行机会。
        // 这段间隙可能收到刚到达的输入或保存请求，因此必须在 await 之后
        // 再检查一次；若出现新草稿就继续保存，而不是取消计时器直接切走。
      } while (state.hasPendingSave || _saveInProgress);
      // 最后的 pending 检查与 _readDate 的调用处于同一同步执行段。
      // _readDate 会先切换到只读加载状态，再等待 IO，不再留下丢草稿的空隙。
      return await _readDate(normalizedDate);
    } finally {
      _dateChangeInProgress = false;
    }
  }

  /// 只负责读取，调用者必须先保证旧日期没有待保存草稿。
  /// 初次启动尚无旧草稿，因此可以直接调用；后续操作统一经过 selectDate。
  Future<bool> _readDate(DateTime date) async {
    if (!ref.mounted) {
      return false;
    }

    // request 编号用于忽略较早完成的读取，防止旧请求回写新的页面状态。
    _saveTimer?.cancel();
    final request = ++_loadRequest;
    final normalizedDate = DreamEntry.dateOnly(date);
    state = DreamEditorState(date: normalizedDate);

    try {
      final repository = ref.read(dreamRepositoryProvider);
      final entry = await repository.getByDate(normalizedDate);

      if (!ref.mounted || request != _loadRequest) {
        return false;
      }

      state = DreamEditorState(
        date: normalizedDate,
        content: entry?.content ?? '',
        isLoading: false,
      );
      return true;
    } on Object catch (error) {
      if (!ref.mounted || request != _loadRequest) {
        return false;
      }

      state = DreamEditorState(
        date: normalizedDate,
        isLoading: false,
        saveStatus: DreamSaveStatus.failed,
        errorMessage: '读取梦境失败：$error',
        failure: DreamEditorFailure.load,
      );
      return false;
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

    // 没有修改的空白页不能仅因进入后台就删除一次记录；同理，已保存的
    // 页面无需再写一遍。明确修改、保存中和保存失败才属于待提交内容。
    if (!state.hasPendingSave) {
      return;
    }

    _saveInProgress = true;
    final completion = Completer<void>();
    _saveCompletion = completion;

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
      if (!completion.isCompleted) {
        completion.complete();
      }
      _saveCompletion = null;
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
