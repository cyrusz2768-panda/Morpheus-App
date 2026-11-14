import 'dart:convert';
import 'dart:math';

/// 类型只决定打开策略，不从链接或音乐内容推断梦境状态、评分。
enum DreamLinkKind { web, music }

/// 网页与音乐附件统一存链接与可选标题，不下载网页、不抓取音乐或自动联网预览。
class DreamLink {
  const DreamLink({
    required this.id,
    required this.url,
    required this.kind,
    this.title,
  });
  final String id;
  final String url;
  final DreamLinkKind kind;
  final String? title;

  factory DreamLink.create({
    String? id,
    required String url,
    required DreamLinkKind kind,
    String? title,
  }) {
    final uri = parseUrl(url);
    if (uri == null) throw const FormatException('Invalid attachment URL');
    final trimmedTitle = title?.trim();
    return DreamLink(
      id:
          id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      url: uri.toString(),
      kind: kind,
      title: trimmedTitle == null || trimmedTitle.isEmpty ? null : trimmedTitle,
    );
  }

  /// 接受完整网址或裸域名，打开前补https；保存/显示的正文不经过这个转换。
  /// 这里只校验格式，不联网查询域名或网页是否存在，避免输入时泄露正文。
  static Uri? parseUrl(String value, {bool fromStorage = false}) {
    final input = value.trim();
    if (input.isEmpty || RegExp(r'\s|[\x00-\x1f\x7f]').hasMatch(input)) {
      return null;
    }
    final explicitHttp = RegExp(
      r'^https?://',
      caseSensitive: false,
    ).hasMatch(input);
    try {
      final uri = Uri.tryParse(explicitHttp ? input : 'https://$input');
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.host.contains('\\')) {
        return null;
      }
      // 旧版显式HTTP附件曾接受单标签内网地址；读取旧数据时不收紧此规则。
      // 新输入和正文检测做更严格的域名/端口校验，不能因此让旧记录整体读失败。
      if (!(fromStorage && explicitHttp)) {
        if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
        if (!isWebHost(uri.host, allowLocal: explicitHttp)) return null;
      }
      return uri;
    } on FormatException {
      // Uri的port等属性可能延迟解析；极长数字端口同样只当普通无效文字处理。
      return null;
    }
  }

  /// 裸域名必须有至少两段，避免把普通单词当网址；数字IP逐段校验。
  /// Unicode域名可使用浏览器提供的xn--编码；不把正文里的中文词句吞进域名。
  static bool isWebHost(String host, {bool allowLocal = false}) {
    if (allowLocal && (host == 'localhost' || host.contains(':'))) return true;
    if (RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(host)) {
      return host.split('.').every((part) {
        final number = int.tryParse(part);
        return number != null && number <= 255;
      });
    }
    final labels = host.split('.');
    if (labels.length < 2 || host.length > 253) return false;
    final labelPattern = RegExp(
      r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
    );
    if (!labels.every(labelPattern.hasMatch)) return false;
    return RegExp(
      r'^(?:[a-zA-Z]{2,63}|xn--[a-zA-Z0-9-]{2,59})$',
    ).hasMatch(labels.last);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'url': url,
    'kind': kind.name,
    'title': title,
  };
  static String encode(List<DreamLink> links) =>
      jsonEncode(links.map((e) => e.toJson()).toList());
  static List<DreamLink> decode(String value) {
    final ids = <String>{};
    return List.unmodifiable(
      (jsonDecode(value) as List).map((item) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String;
        if (id.isEmpty || !ids.add(id)) {
          throw const FormatException('Invalid attachment ID');
        }
        // 损坏元数据必须上报读取失败，不能假装没有链接后覆盖原记录。
        final uri = parseUrl(map['url'] as String, fromStorage: true);
        if (uri == null) throw const FormatException('Invalid attachment URL');
        return DreamLink(
          id: id,
          url: uri.toString(),
          kind: DreamLinkKind.values.byName(map['kind'] as String),
          title: map['title'] as String?,
        );
      }),
    );
  }
}
