import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:path_provider/path_provider.dart';

class PendingImageSelection {
  const PendingImageSelection(this.date, this.images);
  final DateTime date;
  final List<DreamImage> images;
}

/// Controller 只处理日期与附件快照；相册、沙盒路径、原子文件写入集中在此接口。
abstract interface class IImageAttachmentService {
  Future<List<DreamImage>> pick(DateTime date);
  Future<PendingImageSelection?> recover();
  Future<void> completeSelection(DateTime date);
  Future<File> fileFor(DreamImage image);
  Future<void> removeFiles(Iterable<DreamImage> images);
}

final imageAttachmentServiceProvider = Provider<IImageAttachmentService>(
  (ref) => LocalImageAttachmentService(),
);

class LocalImageAttachmentService implements IImageAttachmentService {
  LocalImageAttachmentService({
    ImagePicker? picker,
    Future<Directory> Function()? directory,
    bool? isAndroid,
  }) : _picker = picker ?? ImagePicker(),
       _directory = directory ?? getApplicationSupportDirectory,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  final ImagePicker _picker;
  final Future<Directory> Function() _directory;
  final bool _isAndroid;

  Future<Directory> _imageDirectory() async {
    final root = await _directory();
    return Directory('${root.path}/dream_images').create(recursive: true);
  }

  Future<File> _pendingFile() async =>
      File('${(await _imageDirectory()).path}/pending.json');

  Future<void> _writePending(DateTime date, List<DreamImage> images) async {
    final file = await _pendingFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'date': DreamEntry.dateKey(date),
        'images': images.map((e) => e.toJson()).toList(),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  @override
  Future<List<DreamImage>> pick(DateTime date) async {
    // Android 在系统相册前台时可能回收 Activity；先保存所属日期，恢复后不会附错日。
    await _writePending(date, const []);
    final selected = await _picker.pickImage(source: ImageSource.gallery);
    if (selected == null) {
      await completeSelection(date);
      return const [];
    }
    final images = [await importFile(selected)];
    await _writePending(date, images);
    return List.unmodifiable(images);
  }

  /// 先校验图片尺寸，再把数据 flush 到临时文件并原子改名；DB 只能引用完整文件。
  /// 不重编码原图；缩略图的解码尺寸由 UI 控制，放大时才解码大图。
  Future<DreamImage> importFile(XFile source) async {
    final bytes = await source.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final name =
          '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}.img';
      final directory = await _imageDirectory();
      final temporary = File('${directory.path}/$name.part');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename('${directory.path}/$name');
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      return DreamImage(
        fileName: name,
        width: descriptor.width,
        height: descriptor.height,
      );
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  @override
  Future<PendingImageSelection?> recover() async {
    // iOS 不存在 Android Activity 的 lost-data 机制；普通启动不读取或申请相册权限。
    if (!_isAndroid) return null;
    final file = await _pendingFile();
    final lost = await _picker.retrieveLostData();
    if (!await file.exists()) return null;
    final pending =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final date = DateTime.parse(pending['date'] as String);
    var images = DreamImage.decode(jsonEncode(pending['images']));
    final recoveredFiles =
        lost.files ?? (lost.file == null ? <XFile>[] : [lost.file!]);
    if (images.isEmpty && recoveredFiles.isNotEmpty) {
      images = [for (final source in recoveredFiles) await importFile(source)];
      await _writePending(date, images);
    }
    if (images.isEmpty) {
      await completeSelection(date);
      if (lost.exception != null) throw lost.exception!;
      return null;
    }
    // DB 失败时不清除此恢复日志，下次可用相同文件名幂等合并。
    return PendingImageSelection(date, images);
  }

  @override
  Future<void> completeSelection(DateTime date) async {
    final file = await _pendingFile();
    if (!await file.exists()) return;
    final pending =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (pending['date'] == DreamEntry.dateKey(date)) await file.delete();
  }

  @override
  Future<File> fileFor(DreamImage image) async =>
      File('${(await _imageDirectory()).path}/${image.fileName}');

  @override
  Future<void> removeFiles(Iterable<DreamImage> images) async {
    for (final image in images) {
      final file = await fileFor(image);
      if (await file.exists()) await file.delete();
    }
  }
}
