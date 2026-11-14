import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_export/data/dream_export_renderer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

abstract interface class IDreamExportOutput {
  Future<void> save(DreamExportImage image, DateTime date);
  Future<void> share(DreamExportImage image, DateTime date, Rect origin);
}

final dreamExportOutputProvider = Provider<IDreamExportOutput>(
  (ref) => LocalDreamExportOutput(),
);

/// 页面只传预览的PNG；平台差异和临时文件生命周期集中在此处，不访问DB。
class LocalDreamExportOutput implements IDreamExportOutput {
  LocalDreamExportOutput({
    Future<Directory> Function()? directory,
    MethodChannel? channel,
    Future<ShareResult> Function(ShareParams)? share,
  }) : _directory = directory ?? getTemporaryDirectory,
       _channel = channel ?? const MethodChannel('morpheus/dream_export'),
       _share = share ?? SharePlus.instance.share;
  final Future<Directory> Function() _directory;
  final MethodChannel _channel;
  final Future<ShareResult> Function(ShareParams) _share;

  Future<File> _write(DreamExportImage image, DateTime date) async {
    final root = Directory('${(await _directory()).path}/dream_exports');
    await root.create(recursive: true);
    // 分享接收方可能延迟读取文件，不能在分享面板关闭时立即删除。下次
    // 导出仅回收本目录超过一天的PNG，不触碰原图、数据库或其他缓存。
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.png')) {
        try {
          if ((await entity.lastModified()).isBefore(cutoff)) {
            await entity.delete();
          }
        } on FileSystemException {
          // 缓存回收失败不影响新的导出；系统也可能已清理该文件。
        }
      }
    }
    final file = File(
      '${root.path}/morpheus_${DreamEntry.dateKey(date)}_'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    );
    return file.writeAsBytes(image.bytes, flush: true);
  }

  @override
  Future<void> save(DreamExportImage image, DateTime date) async {
    final file = await _write(image, date);
    try {
      // 原生层必须等系统实际写入完成才返回，页面才可以显示“已保存”。
      await _channel.invokeMethod<void>('saveToAlbum', {'path': file.path});
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 缓存清理失败不能把系统已经完成的相册保存误报为失败。
      }
    }
  }

  @override
  Future<void> share(DreamExportImage image, DateTime date, Rect origin) async {
    final file = await _write(image, date);
    await _share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        sharePositionOrigin: origin,
      ),
    );
    // success 只表示系统接受调用，不能断言接收软件已发送。取消面板也
    // 不视为错误；本轮不显示“分享成功”或记录任何收件人信息。
  }
}
