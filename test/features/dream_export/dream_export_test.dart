import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/data/image_attachment_service.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/features/dream_export/data/dream_export_output.dart';
import 'package:morpheus/features/dream_export/data/dream_export_renderer.dart';
import 'package:morpheus/features/dream_export/domain/dream_export_data.dart';
import 'package:morpheus/l10n/app_text.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final text = lookupAppLocalizations(morpheusLocale);
  final date = DateTime(2026, 11, 14);
  late Directory directory;
  late LocalImageAttachmentService images;
  late DreamExportRenderer renderer;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('morpheus_export_test_');
    images = LocalImageAttachmentService(directory: () async => directory);
    renderer = DreamExportRenderer(images, text);
  });
  tearDown(() => directory.delete(recursive: true));

  test('二维码按UTF8字节限制并保留完整Unicode码点，长图数据原文不变', () {
    final original = '  梦境🌙\n' * 100;
    final excerpt = boundedQrExcerpt(original);
    expect(utf8.encode(excerpt).length, lessThanOrEqualTo(360));
    expect(excerpt.endsWith('…'), isTrue);
    expect(excerpt.contains('\uFFFD'), isFalse);
    expect(
      original.startsWith(excerpt.substring(0, excerpt.length - 1)),
      isTrue,
    );
    expect(boundedQrExcerpt('🌙 短文'), '🌙 短文');
    final data = DreamExportData(
      date: date,
      content: original,
      images: [],
      links: [],
    );
    expect(data.content, original);
  });

  test('长文比短文生成更高PNG；超限明确报错，不截断正文', () async {
    final short = await renderer.render(
      DreamExportData(
        date: date,
        content: '  人工梦境\n结尾🌙  ',
        images: [],
        links: [],
      ),
    );
    final long = await renderer.render(
      DreamExportData(
        date: date,
        content: '人工梦境\n' * 40,
        images: [],
        links: [],
      ),
    );
    expect(short.width, 900);
    expect(long.height, greaterThan(short.height + 1000));
    final codec = await ui.instantiateImageCodec(long.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.height, long.height);
    frame.image.dispose();
    codec.dispose();
    await expectLater(
      renderer.render(
        DreamExportData(
          date: date,
          content: '人工超长记录\n' * 1000,
          images: [],
          links: [],
        ),
      ),
      throwsA(isA<DreamExportTooLarge>()),
    );
  });

  test('横竖图片均完整展开，仅图和仅音乐可导出，缺图不静默丢失', () async {
    Future<XFile> picture(
      String name,
      int width,
      int height,
      ui.Color color,
    ) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..drawColor(color, ui.BlendMode.src);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), 5),
        ui.Paint()..color = const ui.Color(0xff0000ff),
      );
      final pic = recorder.endRecording();
      final image = await pic.toImage(width, height);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${directory.path}/$name.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      pic.dispose();
      return XFile(file.path);
    }

    final landscape = await images.importFile(
      await picture('wide', 400, 200, const ui.Color(0xffff0000)),
    );
    final portrait = await images.importFile(
      await picture('tall', 100, 300, const ui.Color(0xff00ff00)),
    );
    final base = await renderer.render(
      DreamExportData(date: date, content: '', images: [], links: []),
    );
    final result = await renderer.render(
      DreamExportData(
        date: date,
        content: '',
        images: [landscape, portrait],
        links: [],
      ),
    );
    expect(result.height - base.height, closeTo(772 * 3.5 + 56, 2));
    final music = DreamLink.create(
      url: 'https://example.com/music',
      title: '人工音乐',
      kind: DreamLinkKind.music,
    );
    final linked = await renderer.render(
      DreamExportData(date: date, content: '', images: [], links: [music]),
    );
    expect(linked.height, greaterThan(base.height));
    final longUrl = DreamLink.create(
      url: 'https://example.com/${'a' * 800}',
      kind: DreamLinkKind.web,
    );
    expect(
      (await renderer.render(
        DreamExportData(date: date, content: '', images: [], links: [longUrl]),
      )).height,
      greaterThan(base.height),
    );
    await (await images.fileFor(landscape)).delete();
    await expectLater(
      renderer.render(
        DreamExportData(
          date: date,
          content: '',
          images: [landscape],
          links: [],
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('相册等待系统结果、传递同版PNG且清理保存临时文件；权限错误透传', () async {
    const channel = MethodChannel('morpheus/export_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final image = DreamExportImage(Uint8List.fromList([1, 2, 3]), 1, 1);
    String? path;
    var denied = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveToAlbum');
      path = (call.arguments as Map)['path'] as String;
      expect(await File(path!).readAsBytes(), image.bytes);
      if (denied) throw PlatformException(code: 'permissionDenied');
      return null;
    });
    final output = LocalDreamExportOutput(
      directory: () async => directory,
      channel: channel,
    );
    await output.save(image, date);
    expect(await File(path!).exists(), isFalse);
    denied = true;
    await expectLater(
      output.save(image, date),
      throwsA(isA<PlatformException>()),
    );
    expect(await File(path!).exists(), isFalse);
  });

  test('紧凑二维码位于文字右栏，链接140px、底部160px且连续行互不重叠', () async {
    final links = [
      DreamLink.create(
        url: 'https://example.com/music?a=1',
        title: '人工音乐',
        kind: DreamLinkKind.music,
      ),
      DreamLink.create(
        url: 'https://example.com/dream',
        title: '人工网页',
        kind: DreamLinkKind.web,
      ),
    ];
    final result = await renderer.render(
      DreamExportData(
        date: date,
        content: '人工梦境🌙\n' * 20,
        images: [],
        links: links,
      ),
    );
    final codec = await ui.instantiateImageCodec(result.bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      // 此人工长图没有用户图片，纯白像素只来自二维码底板。直接检查导出
      // PNG的实际像素，保证测试能发现二维码退回左侧、尺寸或行间隔错误。
      final regions = <({int left, int right, int top, int bottom})>[];
      for (var row = 0; row < result.height; row++) {
        var left = result.width;
        var right = -1;
        for (var column = 0; column < result.width; column++) {
          final offset = (row * result.width + column) * 4;
          if (rgba[offset] == 255 &&
              rgba[offset + 1] == 255 &&
              rgba[offset + 2] == 255) {
            if (left == result.width) left = column;
            right = column;
          }
        }
        if (right < 0) continue;
        if (regions.isNotEmpty && regions.last.bottom == row - 1) {
          final previous = regions.removeLast();
          regions.add((
            left: previous.left,
            right: previous.right,
            top: previous.top,
            bottom: row,
          ));
        } else {
          regions.add((left: left, right: right, top: row, bottom: row));
        }
      }
      expect(regions.length, 3);
      for (var index = 0; index < regions.length; index++) {
        final region = regions[index];
        final side = index < 2 ? 140 : 160;
        expect(region.right, 835);
        expect(region.left, 836 - side);
        expect(region.bottom - region.top + 1, closeTo(side, 1));
        if (index > 0) {
          expect(region.top, greaterThan(regions[index - 1].bottom));
        }
      }
    } finally {
      image.dispose();
      codec.dispose();
    }
    expect(text.exportBrand, '夜行者·Morpheus');
    expect(text.exportQrHint, '扫描右侧二维码，查看日期与文字摘要');
    // 可选输出仅含人工内容的PNG，用于本机独立扫码核验；不进入仓库。
    const qaPath = String.fromEnvironment('EXPORT_QA_PATH');
    if (qaPath.isNotEmpty) await File(qaPath).writeAsBytes(result.bytes);
  });

  test('分享保留接收方所需临时文件与iPad锚点，取消不报成功；只回收旧导出PNG', () async {
    final root = Directory('${directory.path}/dream_exports')..createSync();
    final old = File('${root.path}/old.png')..writeAsStringSync('old');
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final other = File('${root.path}/keep.json')..writeAsStringSync('{}');
    final image = DreamExportImage(Uint8List.fromList([1, 2, 3]), 1, 1);
    String? sharedPath;
    final output = LocalDreamExportOutput(
      directory: () async => directory,
      share: (params) async {
        expect(
          params.sharePositionOrigin,
          const ui.Rect.fromLTWH(10, 20, 30, 40),
        );
        expect(params.files!.single.mimeType, 'image/png');
        sharedPath = params.files!.single.path;
        expect(await File(sharedPath!).readAsBytes(), image.bytes);
        return const ShareResult('', ShareResultStatus.dismissed);
      },
    );
    await output.share(image, date, const ui.Rect.fromLTWH(10, 20, 30, 40));
    expect(await File(sharedPath!).exists(), isTrue);
    expect(await old.exists(), isFalse);
    expect(await other.exists(), isTrue);
  });
}
