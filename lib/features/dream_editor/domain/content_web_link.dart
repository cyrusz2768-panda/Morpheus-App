import 'package:morpheus/features/dream_editor/domain/dream_link.dart';

/// UTF-16偏移直接对应Dart字符串、TextSelection和TextSpan，不改正文内容。
class ContentWebLink {
  const ContentWebLink({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
  });
  final int start;
  final int end;
  final String text;
  final Uri uri;
}

/// 保守识别网页网址：不查DNS，不把邮箱、其他协议或常见文件名的一部分变成链接。
class ContentWebLinks {
  static final _candidate = RegExp(
    r'''(?:[a-z][a-z0-9+.-]*://|www\.)[^\s<>"'，。！？；：、（）【】《》]+|(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:xn--[a-z0-9-]{2,59}|[a-z]{2,63})(?::[0-9]+)?(?:[/?#][^\s<>"'，。！？；：、（）【】《》]*)?''',
    caseSensitive: false,
  );
  static final _prefix = RegExp(r'[a-zA-Z0-9_@/.:+-]');
  static final _following = RegExp(r'[a-zA-Z0-9_@.:-]');
  static const _fileExtensions = {
    'txt',
    'dart',
    'json',
    'yaml',
    'yml',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'pdf',
    'mp3',
    'mp4',
    'sqlite',
    'csv',
    'docx',
    'xlsx',
    'pptx',
  };

  static List<ContentWebLink> find(String text) {
    final links = <ContentWebLink>[];
    for (final match in _candidate.allMatches(text)) {
      // 防止在mailto:user@example.com、坏域名或/path/example.com中截出“看似合法”的后缀。
      if (match.start > 0 && _prefix.hasMatch(text[match.start - 1])) continue;
      var end = match.end;
      while (end > match.start && '.,!?;:)]}'.contains(text[end - 1])) {
        final last = text[end - 1];
        final token = text.substring(match.start, end);
        // URL路径里的成对括号保留，句末包围网址的右括号排除。
        final opener = {')': '(', ']': '[', '}': '{'}[last];
        if (opener != null &&
            opener.allMatches(token).length >= last.allMatches(token).length) {
          break;
        }
        end--;
      }
      if (end <= match.start) continue;
      // 未被修剪的候选后还有域名字符，说明匹配到了坏域名的一部分。
      if (match.end < text.length && _following.hasMatch(text[match.end])) {
        final sentencePeriod =
            '.:'.contains(text[match.end]) &&
            (match.end + 1 == text.length ||
                !_following.hasMatch(text[match.end + 1]));
        if (!sentencePeriod) continue;
      }
      final candidate = text.substring(match.start, end);
      final uri = DreamLink.parseUrl(candidate);
      if (uri == null) continue;
      final explicit = RegExp(
        r'^https?://',
        caseSensitive: false,
      ).hasMatch(candidate);
      if (!explicit &&
          _fileExtensions.contains(uri.host.split('.').last.toLowerCase())) {
        continue;
      }
      links.add(
        ContentWebLink(start: match.start, end: end, text: candidate, uri: uri),
      );
    }
    return List.unmodifiable(links);
  }
}
