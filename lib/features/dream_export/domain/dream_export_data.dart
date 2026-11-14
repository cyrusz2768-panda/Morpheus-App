import 'dart:convert';

import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';

/// 保存队列排空后复制一次数据。预览期间不继续订阅编辑器，保证用户看到、
/// 保存和交给分享面板的是同一版内容；不包含数据库路径和健康反馈。
class DreamExportData {
  DreamExportData({
    required this.date,
    required this.content,
    required List<DreamImage> images,
    required List<DreamLink> links,
  }) : images = List.unmodifiable(images),
       links = List.unmodifiable(links);

  final DateTime date;
  final String content;
  final List<DreamImage> images;
  final List<DreamLink> links;

  bool get hasContent =>
      content.trim().isNotEmpty || images.isNotEmpty || links.isNotEmpty;
}

/// 二维码是有限容量的离线文字容器，不是云端记录入口。按 UTF-8 字节控制
/// 摘要长度，并遍历 Unicode 码点，避免把中文或 emoji 的代理对截成乱码。
/// 只缩短二维码摘要，长图中的正文始终完整保留。
String boundedQrExcerpt(
  String text, {
  int maxBytes = 360,
  String suffix = '…',
}) {
  if (utf8.encode(text).length <= maxBytes) return text;
  final output = StringBuffer();
  var used = utf8.encode(suffix).length;
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    used += utf8.encode(character).length;
    if (used > maxBytes) break;
    output.write(character);
  }
  return '$output$suffix';
}
