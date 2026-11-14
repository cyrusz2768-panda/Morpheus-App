import 'package:morpheus/features/dream_editor/domain/content_web_link.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/features/dream_editor/data/link_opener.dart';
import 'package:flutter/services.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/dream_editor/data/image_attachment_service.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/l10n/app_text.dart';

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
  bool _linkOpenInProgress = false;
  int get dateRevision => _loadRequest;
  Completer<void>? _imageTask;
  List<DreamImage> _persistedImages = const [];
  bool _hasPendingSelection = false;
  bool _pendingSelectionCommitted = false;
  Set<String> _pendingImageNames = {};

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
        unawaited(_initialize(today));
      }
    });

    // Providers may be destroyed during tests or future route changes. Cancel
    // the timer so it cannot call a disposed controller.
    ref.onDispose(() {
      _saveTimer?.cancel();
      _loadRequest += 1;
      // 仓库写入可能仍在等待系统 IO；页面已经销毁时，导航等待方可以立即
      // 结束并返回失败，而无需等待一个不再影响页面的旧任务。
      final imageTask = _imageTask;
      if (imageTask != null && !imageTask.isCompleted) imageTask.complete();
      final completion = _saveCompletion;
      if (completion != null && !completion.isCompleted) {
        completion.complete();
      }
    });

    return DreamEditorState(date: today);
  }

  Future<void> _initialize(DateTime today) async {
    final completion = Completer<void>();
    _imageTask = completion;
    try {
      PendingImageSelection? pending;
      var failed = false;
      try {
        pending = await ref.read(imageAttachmentServiceProvider).recover();
      } on Object {
        failed = true;
      }
      if (!ref.mounted) return;
      if (!await _readDate(pending?.date ?? today) || !ref.mounted) return;
      if (pending != null) {
        _hasPendingSelection = true;
        _pendingImageNames = pending.images.map((e) => e.fileName).toSet();
        final names = state.images.map((e) => e.fileName).toSet();
        state = state.copyWith(
          images: List.unmodifiable([
            ...state.images,
            ...pending.images.where((e) => !names.contains(e.fileName)),
          ]),
          saveStatus: DreamSaveStatus.unsaved,
        );
        await saveNow();
      } else if (failed) {
        state = state.copyWith(
          attachmentError: ref.read(appLocalizationsProvider).imageAddFailed,
        );
      }
    } finally {
      if (!completion.isCompleted) completion.complete();
      _imageTask = null;
    }
  }

  /// 图片进入与正文同一个保存队列。操作期间仍可输入文字，保存时总取最新快照。
  Future<void> addImage() async {
    if (!ref.mounted ||
        !state.canEdit ||
        state.isAddingImages ||
        _imageTask != null ||
        state.isAdvancing ||
        _dateChangeInProgress) {
      return;
    }
    final completion = Completer<void>();
    _imageTask = completion;
    state = state.copyWith(isAddingImages: true, clearAttachmentError: true);
    try {
      if (!await _flushSavesOnly() || !ref.mounted) return;
      final date = state.date;
      final images = await ref.read(imageAttachmentServiceProvider).pick(date);
      if (!ref.mounted || images.isEmpty) return;
      _hasPendingSelection = true;
      _pendingImageNames = images.map((e) => e.fileName).toSet();
      state = state.copyWith(
        images: List.unmodifiable([...state.images, ...images]),
        saveStatus: DreamSaveStatus.unsaved,
        clearError: true,
      );
      await _flushSavesOnly();
    } on PlatformException catch (error) {
      // 用户拒绝系统授权时保持原记录，不叠加 App 自制权限提示。
      if (ref.mounted &&
          !error.code.contains('access_denied') &&
          !error.code.contains('access_restricted')) {
        state = state.copyWith(
          attachmentError: ref.read(appLocalizationsProvider).imageAddFailed,
        );
      }
    } on Object {
      if (ref.mounted) {
        state = state.copyWith(
          attachmentError: ref.read(appLocalizationsProvider).imageAddFailed,
        );
      }
    } finally {
      if (ref.mounted) state = state.copyWith(isAddingImages: false);
      if (!completion.isCompleted) completion.complete();
      _imageTask = null;
    }
  }

  void removeImage(DreamImage image) {
    if (!ref.mounted ||
        !state.canEdit ||
        state.isAddingImages ||
        _imageTask != null ||
        _pendingSelectionCommitted) {
      return;
    }
    if (!state.images.any((e) => e.fileName == image.fileName)) return;
    _pendingImageNames.remove(image.fileName);
    state = state.copyWith(
      images: List.unmodifiable(
        state.images.where((e) => e.fileName != image.fileName),
      ),
      saveStatus: DreamSaveStatus.unsaved,
      clearError: true,
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  /// 表单打开时捕获所属日期；通知可能在表单期间切日，旧表单不能写进新日期。
  /// 更新按稳定id替换，标题留空即清除；链接与正文/图片共用800ms串行队列。
  bool putLink({
    required DateTime date,
    required int loadRevision,
    String? id,
    required String url,
    required DreamLinkKind kind,
    String? title,
  }) {
    if (!ref.mounted ||
        !state.canEdit ||
        state.isAdvancing ||
        state.isAddingImages ||
        _imageTask != null ||
        _dateChangeInProgress ||
        state.date != DreamEntry.dateOnly(date) ||
        loadRevision != _loadRequest) {
      return false;
    }
    if (id != null && !state.links.any((link) => link.id == id)) return false;
    final link = DreamLink.create(id: id, url: url, kind: kind, title: title);
    final links = [...state.links];
    final index = links.indexWhere((item) => item.id == link.id);
    if (index < 0) {
      links.add(link);
    } else {
      links[index] = link;
    }
    _linksChanged(links);
    return true;
  }

  void removeLink({
    required DateTime date,
    required int loadRevision,
    required String id,
  }) {
    if (!ref.mounted ||
        !state.canEdit ||
        _dateChangeInProgress ||
        state.isAddingImages ||
        _imageTask != null ||
        state.date != DreamEntry.dateOnly(date) ||
        loadRevision != _loadRequest) {
      return;
    }
    if (!state.links.any((link) => link.id == id)) return;
    _linksChanged(state.links.where((link) => link.id != id).toList());
  }

  void _linksChanged(List<DreamLink> links) {
    state = state.copyWith(
      links: List.unmodifiable(links),
      saveStatus: DreamSaveStatus.unsaved,
      clearError: true,
      clearAttachmentError: true,
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  Future<bool> openLink({
    required DateTime date,
    required int loadRevision,
    required DreamLink link,
  }) => _openLinkTarget(
    date: date,
    loadRevision: loadRevision,
    link: link,
    isCurrent: () => state.links.any(
      (item) =>
          item.id == link.id && item.url == link.url && item.kind == link.kind,
    ),
  );

  /// 正文链接只是文字的一部分，不额外写附件；点击前后都检查它仍在当前正文中。
  Future<bool> openContentLink({
    required DateTime date,
    required int loadRevision,
    required ContentWebLink match,
  }) => _openLinkTarget(
    date: date,
    loadRevision: loadRevision,
    link: DreamLink(
      id: 'content:${match.start}:${match.end}',
      url: match.uri.toString(),
      kind: DreamLinkKind.web,
    ),
    isCurrent: () => ContentWebLinks.find(state.content).any(
      (item) =>
          item.start == match.start &&
          item.end == match.end &&
          item.text == match.text &&
          item.uri == match.uri,
    ),
  );

  Future<bool> _openLinkTarget({
    required DateTime date,
    required int loadRevision,
    required DreamLink link,
    required bool Function() isCurrent,
  }) async {
    if (!ref.mounted ||
        !state.canEdit ||
        _linkOpenInProgress ||
        state.date != DreamEntry.dateOnly(date) ||
        loadRevision != _loadRequest ||
        !isCurrent()) {
      return false;
    }
    _linkOpenInProgress = true;
    final request = _loadRequest;
    try {
      // 外部音乐App会让本App进入后台；内嵌浏览器也遮住编辑器。先确认磁盘已保存。
      if (!await flushPendingSave() ||
          !ref.mounted ||
          request != _loadRequest ||
          state.date != DreamEntry.dateOnly(date) ||
          loadRevision != _loadRequest) {
        return false;
      }
      if (!isCurrent()) {
        return false;
      }
      state = state.copyWith(clearAttachmentError: true);
      final opened = await ref.read(linkOpenerProvider).open(link);
      if (!opened && ref.mounted && request == _loadRequest) {
        state = state.copyWith(
          attachmentError: ref.read(appLocalizationsProvider).linkOpenFailed,
        );
      }
      return opened;
    } on Object {
      if (ref.mounted && request == _loadRequest) {
        state = state.copyWith(
          attachmentError: ref.read(appLocalizationsProvider).linkOpenFailed,
        );
      }
      return false;
    } finally {
      _linkOpenInProgress = false;
    }
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
    // 相册返回、文件复制与保存完成前，导航必须等候，不能把结果附到另一日期。
    final task = _imageTask;
    if (task != null) await task.future;
    return _flushSavesOnly();
  }

  Future<bool> _flushSavesOnly() async {
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

      _persistedImages = entry?.images ?? const [];
      state = DreamEditorState(
        date: normalizedDate,
        content: entry?.content ?? '',
        feedback: entry?.feedback ?? const DailyFeedback(),
        images: entry?.images ?? const [],
        links: entry?.links ?? const [],
        // 历史记录直接查看；当天未完成的流程重新从分类开始，正文始终保留。
        step:
            entry != null &&
                (entry.feedback.completed ||
                    normalizedDate != DreamEntry.dateOnly(DateTime.now()))
            ? DailyRecordStep.summary
            : DailyRecordStep.mood,
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
        errorMessage: ref
            .read(appLocalizationsProvider)
            .dreamLoadFailed(error.toString()),
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

  /// 所有反馈共用正文的串行队列；写入中修改反馈也会生成下一份快照。
  void feedbackChanged(DailyFeedback feedback) {
    if (!ref.mounted || !state.canEdit) return;
    state = state.copyWith(
      feedback: feedback,
      saveStatus: DreamSaveStatus.unsaved,
      clearError: true,
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  /// 步骤导航也必须等待磁盘确认。失败留在原步骤，重试始终写当前草稿。
  /// isAdvancing 防止连点；IO 期间正文仍可接收输入法最后一段回调并排队保存。
  Future<void> moveTo(DailyRecordStep step, {DailyFeedback? feedback}) async {
    if (!ref.mounted || !state.canEdit || state.isAdvancing) return;
    final date = state.date;
    final request = _loadRequest;
    state = state.copyWith(isAdvancing: true);
    try {
      if (feedback != null) feedbackChanged(feedback);
      if (!await flushPendingSave() || !ref.mounted) return;
      // 系统通知可抢占页面导航；旧日期的异步续体不能推进新日期的步骤。
      if (state.date != date || _loadRequest != request || state.isLoading) {
        return;
      }
      state = state.copyWith(step: step);
    } finally {
      if (ref.mounted && _loadRequest == request) {
        state = state.copyWith(isAdvancing: false);
      }
    }
  }

  Future<void> chooseMood(DreamMood? mood) => moveTo(
    mood == DreamMood.forgotten || mood == DreamMood.noDream
        ? DailyRecordStep.score
        : DailyRecordStep.content,
    feedback: mood == null ? null : state.feedback.copyWith(mood: mood),
  );

  Future<void> chooseScore(int score) => moveTo(
    DailyRecordStep.factors,
    feedback: state.feedback.copyWith(sleepScore: score),
  );

  Future<void> finishRecord() => moveTo(
    DailyRecordStep.summary,
    feedback: state.feedback.copyWith(completed: true),
  );

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
        final feedbackToSave = state.feedback;
        final imagesToSave = state.images;
        final linksToSave = state.links;

        state = state.copyWith(
          saveStatus: DreamSaveStatus.saving,
          clearError: true,
        );

        final repository = ref.read(dreamRepositoryProvider);
        if (contentToSave.trim().isEmpty &&
            imagesToSave.isEmpty &&
            linksToSave.isEmpty &&
            !feedbackToSave.hasData &&
            !feedbackToSave.completed) {
          await repository.deleteByDate(dateToSave);
        } else {
          await repository.save(
            date: dateToSave,
            content: contentToSave,
            feedback: feedbackToSave,
            images: imagesToSave,
            links: linksToSave,
          );
        }

        // 先提交数据库，再清理旧文件。文件清理失败最多留下孤立文件，不能
        // 把数据库成功误报为失败，更不能在重试前删掉数据库仍引用的图片。
        final removed = _persistedImages
            .where(
              (old) => !imagesToSave.any((e) => e.fileName == old.fileName),
            )
            .toList();
        _persistedImages = imagesToSave;
        if (ref.mounted &&
            _hasPendingSelection &&
            _pendingImageNames.every(
              (name) => imagesToSave.any((image) => image.fileName == name),
            )) {
          // 恢复日志确认属于保存流程，而非可忽略的文件清理。确认失败时保持
          // 失败草稿并锁定图片移除，重试成功前不允许旧日志在重启后复活已删图片。
          _pendingSelectionCommitted = true;
          await ref
              .read(imageAttachmentServiceProvider)
              .completeSelection(dateToSave);
          _hasPendingSelection = false;
          _pendingSelectionCommitted = false;
        }
        if (ref.mounted && removed.isNotEmpty) {
          try {
            await ref.read(imageAttachmentServiceProvider).removeFiles(removed);
          } on Object {
            // DB 已提交；清理失败仅留下孤立文件，不回滚或误报保存失败。
          }
        }
        if (!ref.mounted) return;

        // If the user typed while the write was running, keep "unsaved" and
        // loop again with the newer content.
        if (state.content != contentToSave ||
            !identical(state.feedback, feedbackToSave) ||
            !identical(state.images, imagesToSave) ||
            !identical(state.links, linksToSave)) {
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
          errorMessage: ref
              .read(appLocalizationsProvider)
              .dreamSaveFailed(error.toString()),
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
