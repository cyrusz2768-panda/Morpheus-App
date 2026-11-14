import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/data/image_attachment_service.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/features/dream_export/domain/dream_export_data.dart';
import 'package:morpheus/l10n/app_text.dart';
import 'package:qr/qr.dart';

class DreamExportTooLarge implements Exception {}

class DreamExportImage {
  const DreamExportImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

abstract interface class IDreamExportRenderer {
  Future<DreamExportImage> render(
    DreamExportData data, {
    bool Function()? isCancelled,
  });
}

final dreamExportRendererProvider = Provider<IDreamExportRenderer>(
  (ref) => DreamExportRenderer(
    ref.watch(imageAttachmentServiceProvider),
    ref.watch(appLocalizationsProvider),
  ),
);

/// 直接用 Canvas 排版，不截屏编辑器，也不依赖屏幕上是否已经滚动到图片。
/// 先测量、再绘制、最后编码，因此文字不会受屏幕高度限制或只截到一部分。
/// 像素预算同时约束最终位图和图片解码，超出时明确失败，不静默截断记录。
class DreamExportRenderer implements IDreamExportRenderer {
  DreamExportRenderer(this.images, this.text);
  final IImageAttachmentService images;
  final AppLocalizations text;
  static const width = 900;
  static const maxHeight = 16000;
  static const double margin = 64;
  static const double contentWidth = width - margin * 2;

  @override
  Future<DreamExportImage> render(
    DreamExportData data, {
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) {
        throw StateError('Export preview closed');
      }
    }

    checkCancelled();
    final blocks = <_ExportBlock>[];
    final decoded = <ui.Image>[];
    final painters = <TextPainter>[];
    var y = margin;
    void checkSize() {
      if (!y.isFinite || y > maxHeight - margin) {
        throw DreamExportTooLarge();
      }
    }

    TextPainter measureText(
      String value,
      double size, {
      bool accent = false,
      double maxWidth = contentWidth,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: size,
            height: 1.65,
            color: accent ? const Color(0xff66518b) : const Color(0xff292535),
            fontWeight: accent ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      painters.add(painter);
      return painter;
    }

    void addText(String value, double size, {bool accent = false}) {
      final painter = measureText(value, size, accent: accent);
      blocks.add(
        _ExportBlock(y, (canvas, top) {
          painter.paint(canvas, Offset(margin, top));
        }),
      );
      y += painter.height + 24;
      checkSize();
    }

    QrImage qrFor(String payload) => QrImage(
      QrCode(
        payload: QrPayload()
          ..addECI(QrEciValue.utf8)
          ..addString(payload),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );

    bool fitsCompactQr(QrImage qr, double side) =>
        (qr.moduleCount + 8) * 2 <= side;

    void addQrRow(List<_ExportLine> lines, QrImage qr, double side) {
      // 左文右码共用一行：左栏只在自身宽度内换行，行高取两栏较大值。
      // 缩小的是二维码边长，不缩放整张图，因此正文与原图清晰度保持原样。
      const gap = 24.0;
      final leftWidth = contentWidth - side - gap;
      final rowPainters = <TextPainter>[];
      var textHeight = 0.0;
      for (final line in lines) {
        final painter = measureText(
          line.value,
          line.size,
          accent: line.accent,
          maxWidth: leftWidth,
        );
        rowPainters.add(painter);
        textHeight += painter.height;
      }
      textHeight += (lines.length - 1) * 10;
      final rowHeight = textHeight > side ? textHeight : side;
      blocks.add(
        _ExportBlock(y, (canvas, top) {
          var lineTop = top + (rowHeight - textHeight) / 2;
          for (final painter in rowPainters) {
            painter.paint(canvas, Offset(margin, lineTop));
            lineTop += painter.height + 10;
          }
          final qrLeft = width - margin - side;
          final qrTop = top + (rowHeight - side) / 2;
          canvas.drawRect(
            Rect.fromLTWH(qrLeft, qrTop, side, side),
            Paint()..color = const Color(0xffffffff),
          );
          // 至少2px/module，保留四模块白边；整数像素绘制避免缩小后的边缘
          // 模糊。实际码在固定白底正方形中居中，四分之一面积保持一致。
          final cell = (side / (qr.moduleCount + 8)).floorToDouble();
          final inset = ((side - cell * (qr.moduleCount + 8)) / 2)
              .floorToDouble();
          final ink = Paint()
            ..color = const Color(0xff181322)
            ..isAntiAlias = false;
          for (var row = 0; row < qr.moduleCount; row++) {
            for (var column = 0; column < qr.moduleCount; column++) {
              if (qr.isDark(row, column)) {
                canvas.drawRect(
                  Rect.fromLTWH(
                    qrLeft.floorToDouble() + inset + (column + 4) * cell,
                    qrTop.floorToDouble() + inset + (row + 4) * cell,
                    cell,
                    cell,
                  ),
                  ink,
                );
              }
            }
          }
        }),
      );
      y += rowHeight + 28;
      checkSize();
    }

    try {
      addText(text.appTitle, 30, accent: true);
      final date = text.dreamDate(
        data.date.year,
        data.date.month,
        data.date.day,
      );
      addText(date, 46, accent: true);
      y += 20;
      if (data.content.trim().isNotEmpty) addText(data.content, 34);
      // 先检查全部图片预计高度，避免到末尾才发现超限并解码了许多大图。
      final imageHeight = data.images.fold<double>(
        0,
        (sum, image) => sum + contentWidth / image.aspectRatio + 28,
      );
      if (!imageHeight.isFinite || y + imageHeight > maxHeight - margin) {
        throw DreamExportTooLarge();
      }
      for (final image in data.images) {
        final file = await images.fileFor(image);
        final bytes = await file.readAsBytes();
        checkCancelled();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;
        try {
          // 不仅信任DB元数据：解码前检查文件头中的真实比例，避免损坏或
          // 被替换的图片先分配超高位图再发现超过预算。
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          checkCancelled();
          final height = contentWidth * descriptor.height / descriptor.width;
          if (!height.isFinite || y + height > maxHeight - margin) {
            throw DreamExportTooLarge();
          }
          codec = await descriptor.instantiateCodec(
            targetWidth: descriptor.width < contentWidth
                ? descriptor.width
                : contentWidth.ceil(),
          );
          final frame = await codec.getNextFrame();
          decoded.add(frame.image);
          checkCancelled();
          blocks.add(
            _ExportBlock(y, (canvas, top) {
              canvas.drawImageRect(
                frame.image,
                Rect.fromLTWH(
                  0,
                  0,
                  frame.image.width.toDouble(),
                  frame.image.height.toDouble(),
                ),
                Rect.fromLTWH(margin, top, contentWidth, height),
                Paint()..filterQuality = FilterQuality.medium,
              );
            }),
          );
          y += height + 28;
          checkSize();
        } finally {
          codec?.dispose();
          descriptor?.dispose();
          buffer.dispose();
        }
      }
      for (final link in data.links) {
        final label = link.kind == DreamLinkKind.music
            ? text.exportMusicLabel
            : text.exportWebLabel;
        const side = 140.0;
        final qr = utf8.encode(link.url).length <= 700 ? qrFor(link.url) : null;
        // 超长网址仍完整排在图片中，不伪造缩短链接或请求外部短链服务。
        if (qr != null && fitsCompactQr(qr, side)) {
          addQrRow(
            [
              _ExportLine(label, 27, accent: true),
              if (link.title?.isNotEmpty == true) _ExportLine(link.title!, 34),
              _ExportLine(link.url, 24),
              _ExportLine(text.exportLinkQrHint, 22),
            ],
            qr,
            side,
          );
        } else {
          addText(label, 27, accent: true);
          if (link.title?.isNotEmpty == true) addText(link.title!, 34);
          addText(link.url, 24);
          addText(text.exportLinkTooLong, 22);
        }
      }
      y += 28;
      final qrContent = data.content.trim().isEmpty
          ? text.exportQrImageOnly
          : data.content;
      const footerSide = 160.0;
      var excerptBytes = 360;
      late QrImage footerQr;
      // 摘要可以变短，完整正文不变。按实际模块数判断密度，避免中文/emoji
      // 或较长摘要在小二维码中降到1px/module而难以扫描。
      do {
        final excerpt = boundedQrExcerpt(
          qrContent,
          maxBytes: excerptBytes,
          suffix: text.exportExcerptEllipsis,
        );
        footerQr = qrFor('$date\n$excerpt');
        if (fitsCompactQr(footerQr, footerSide)) break;
        excerptBytes -= 24;
        if (excerptBytes < 12) {
          throw StateError('QR date exceeds compact capacity');
        }
      } while (true);
      addQrRow(
        [
          _ExportLine(text.exportBrand, 30, accent: true),
          _ExportLine(text.exportQrHint, 25),
        ],
        footerQr,
        footerSide,
      );
      final height = (y + margin).ceil();
      if (height > maxHeight) throw DreamExportTooLarge();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xfffaf7ff), BlendMode.src);
      for (final block in blocks) {
        block.paint(canvas, block.y);
      }
      final picture = recorder.endRecording();
      ui.Image? result;
      try {
        result = await picture.toImage(width, height);
        checkCancelled();
        final png = await result.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('PNG encoder returned no data');
        return DreamExportImage(png.buffer.asUint8List(), width, height);
      } finally {
        result?.dispose();
        picture.dispose();
      }
    } finally {
      for (final painter in painters) {
        painter.dispose();
      }
      for (final image in decoded) {
        image.dispose();
      }
    }
  }
}

class _ExportBlock {
  const _ExportBlock(this.y, this.paint);
  final double y;
  final void Function(Canvas, double) paint;
}

class _ExportLine {
  const _ExportLine(this.value, this.size, {this.accent = false});
  final String value;
  final double size;
  final bool accent;
}
