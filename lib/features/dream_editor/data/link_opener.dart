import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:url_launcher/url_launcher.dart';

/// 链接打开不属于数据库职责；隔离系统调用后，测试可验证打开顺序而不启动真实软件。
abstract interface class ILinkOpener {
  Future<bool> open(DreamLink link);
}

final linkOpenerProvider = Provider<ILinkOpener>((ref) => SystemLinkOpener());

class SystemLinkOpener implements ILinkOpener {
  SystemLinkOpener({
    Future<bool> Function(Uri uri, LaunchMode mode)? launch,
    Future<bool> Function(LaunchMode mode)? supports,
    Future<bool?> Function(Uri uri)? legacyMusic,
  }) : _launch = launch ?? _launchSystem,
       _supports = supports ?? supportsLaunchMode,
       _legacyMusic = legacyMusic ?? _openLegacyMusic;

  final Future<bool> Function(Uri, LaunchMode) _launch;
  final Future<bool> Function(LaunchMode) _supports;
  final Future<bool?> Function(Uri) _legacyMusic;
  static const _channel = MethodChannel('morpheus/link_navigation');

  static Future<bool?> _openLegacyMusic(Uri uri) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('openMusicIfLegacy', {
        'url': uri.toString(),
      });
    } on Object {
      // 平台桥接失败时留在内部浏览器，不冒险回到普通外部浏览器Intent。
      return false;
    }
  }

  static Future<bool> _launchSystem(Uri uri, LaunchMode mode) => launchUrl(
    uri,
    mode: mode,
    browserConfiguration: const BrowserConfiguration(showTitle: true),
    webViewConfiguration: const WebViewConfiguration(
      enableJavaScript: true,
      enableDomStorage: true,
    ),
  );

  static bool isStoreUrl(Uri uri) =>
      uri.host == 'apps.apple.com' ||
      (uri.host == 'itunes.apple.com' && uri.path.contains('/app/')) ||
      (uri.host == 'play.google.com' && uri.path.startsWith('/store')) ||
      uri.host == 'appgallery.huawei.com' ||
      uri.host == 'galaxystore.samsung.com';

  Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
    try {
      return await _launch(uri, mode);
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> open(DreamLink link) async {
    // 入口已校验新输入；旧版允许的显式HTTP内网附件仍应能按原方式打开。
    final uri = DreamLink.parseUrl(link.url, fromStorage: true);
    if (uri == null) return false;
    // 商店地址明确交给外部处理；普通网页不直接启动独立浏览器App。
    if (isStoreUrl(uri)) return _tryLaunch(uri, LaunchMode.externalApplication);
    if (link.kind == DreamLinkKind.music) {
      // Universal Links / Android App Links优先交给已安装的软件；不根据域名
      // 拼接未公开的私有scheme，也不先canLaunch而误判某音乐软件未安装。
      final legacy = await _legacyMusic(uri);
      if (legacy == true) return true;
      if (legacy == null &&
          await _tryLaunch(uri, LaunchMode.externalNonBrowserApplication)) {
        return true;
      }
    }
    var browserAvailable = false;
    try {
      browserAvailable = await _supports(LaunchMode.inAppBrowserView);
    } on Object {
      /* 系统能力查询失败仍可尝试内部WebView。 */
    }
    if (browserAvailable &&
        await _tryLaunch(uri, LaunchMode.inAppBrowserView)) {
      return true;
    }
    // 必须显式选择内部模式：插件不支持某模式时可能退为默认外部浏览器。
    // 无Custom Tabs的Android使用内部WebView，保留“在Morpheus里浏览”的行为。
    return _tryLaunch(uri, LaunchMode.inAppWebView);
  }
}
