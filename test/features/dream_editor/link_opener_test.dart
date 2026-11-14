import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/data/link_opener.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:url_launcher/url_launcher.dart';
import 'link_attachment_test.dart' show sampleMusic, sampleWeb;

void main() {
  test('普通网页只用App内浏览器，不尝试外部浏览器', () async {
    final calls = <LaunchMode>[];
    final opener = SystemLinkOpener(
      launch: (uri, mode) async {
        calls.add(mode);
        return true;
      },
      supports: (mode) async => true,
    );
    expect(await opener.open(sampleWeb), isTrue);
    expect(calls, [LaunchMode.inAppBrowserView]);
    calls.clear();
    const legacy = DreamLink(
      id: 'legacy',
      url: 'http://intranet/a',
      kind: DreamLinkKind.web,
    );
    final restored = DreamLink.decode(DreamLink.encode([legacy])).single;
    expect(await opener.open(restored), isTrue);
    expect(calls, [LaunchMode.inAppBrowserView]);
  });
  test('没有CustomTabs或内嵌浏览器失败时用内部WebView，不使用平台默认外部模式', () async {
    for (final supports in [true, false]) {
      final calls = <LaunchMode>[];
      final opener = SystemLinkOpener(
        launch: (uri, mode) async {
          calls.add(mode);
          if (mode == LaunchMode.inAppBrowserView) {
            throw PlatformException(code: 'no-browser');
          }
          return true;
        },
        supports: (_) async => supports,
      );
      expect(await opener.open(sampleWeb), isTrue);
      expect(calls.last, LaunchMode.inAppWebView);
      expect(calls, isNot(contains(LaunchMode.externalApplication)));
    }
  });
  test('音乐只尝试非浏览器App，成功后不再开网页或预先canLaunch', () async {
    final calls = <LaunchMode>[];
    final opener = SystemLinkOpener(
      launch: (uri, mode) async {
        calls.add(mode);
        return true;
      },
      supports: (_) async => throw StateError('不应查询'),
      legacyMusic: (_) async => null,
    );
    expect(await opener.open(sampleMusic), isTrue);
    expect(calls, [LaunchMode.externalNonBrowserApplication]);
  });
  test('未安装音乐软件/系统拒绝AppLink后回App内网页，保留原音乐fragment', () async {
    final calls = <LaunchMode>[];
    final opener = SystemLinkOpener(
      launch: (uri, mode) async {
        calls.add(mode);
        expect(uri.toString(), sampleMusic.url);
        if (mode == LaunchMode.externalNonBrowserApplication) {
          throw PlatformException(code: 'not-installed');
        }
        return true;
      },
      supports: (_) async => true,
      legacyMusic: (_) async => null,
    );
    expect(await opener.open(sampleMusic), isTrue);
    expect(calls, [
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.inAppBrowserView,
    ]);
  });
  test('旧Android桥接没找到音乐软件时跳过普通外部Intent，留在App内网页', () async {
    final calls = <LaunchMode>[];
    final opener = SystemLinkOpener(
      launch: (uri, mode) async {
        calls.add(mode);
        return true;
      },
      supports: (_) async => true,
      legacyMusic: (_) async => false,
    );
    expect(await opener.open(sampleMusic), isTrue);
    expect(calls, [LaunchMode.inAppBrowserView]);
    final nativeSuccess = SystemLinkOpener(
      launch: (_, _) async => throw StateError('原生已打开'),
      legacyMusic: (_) async => true,
    );
    expect(await nativeSuccess.open(sampleMusic), isTrue);
  });
  test('网易云QQ酷狗AppleMusicSpotify分享URL不转换私有scheme，交系统关联', () async {
    final urls = [
      'https://music.163.com/#/song?id=123',
      'https://y.qq.com/n/ryqq/songDetail/test',
      'https://www.kugou.com/song/test.html',
      'https://music.apple.com/cn/album/test/123?i=456',
      'https://open.spotify.com/track/test',
      'https://spotify.link/test',
    ];
    for (final url in urls) {
      final opener = SystemLinkOpener(
        launch: (uri, mode) async {
          expect(uri.toString(), url);
          expect(mode, LaunchMode.externalNonBrowserApplication);
          return true;
        },
        legacyMusic: (_) async => null,
      );
      expect(
        await opener.open(
          DreamLink.create(url: url, kind: DreamLinkKind.music),
        ),
        isTrue,
      );
    }
  });
  test('商店链接明确外跳，普通网页全部失败只返回失败，不偷开外部浏览器', () async {
    final calls = <LaunchMode>[];
    final opener = SystemLinkOpener(
      launch: (uri, mode) async {
        calls.add(mode);
        return false;
      },
      supports: (_) async => true,
    );
    expect(
      await opener.open(
        DreamLink.create(
          url: 'https://apps.apple.com/app/id123',
          kind: DreamLinkKind.web,
        ),
      ),
      isFalse,
    );
    expect(calls, [LaunchMode.externalApplication]);
    calls.clear();
    expect(await opener.open(sampleWeb), isFalse);
    expect(calls, [LaunchMode.inAppBrowserView, LaunchMode.inAppWebView]);
    expect(
      SystemLinkOpener.isStoreUrl(
        Uri.parse('https://apps.apple.com.evil.test/app'),
      ),
      isFalse,
    );
  });
}
