import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/domain/content_web_link.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';

void main() {
  test('完整和省略协议/www的网址补https，保留路径参数fragment', () {
    for (final input in [
      'example.com/a?q=1#night',
      'www.example.com/a?q=1#night',
      'HTTPS://EXAMPLE.COM/a?q=1#night',
      'sub.example.com:8443/a?q=1#night',
      'xn--fsqu00a.xn--0zwm56d',
      'read.md',
    ]) {
      final uri = DreamLink.parseUrl(input);
      expect(uri, isNotNull, reason: input);
      expect(uri!.scheme, 'https');
      expect(ContentWebLinks.find(input).single.uri, uri);
    }
    expect(DreamLink.parseUrl('http://example.com')!.scheme, 'http');
    expect(
      DreamLink.create(url: 'example.com', kind: DreamLinkKind.web).url,
      'https://example.com',
    );
  });

  test('中文标点/换行/emoji边界与成对路径括号保留正确的UTF16偏移', () {
    const text =
        '🌙看看example.com，接着（www.example.org/a）。\n'
        '(https://en.wikipedia.org/wiki/Dream_(novel)).';
    final links = ContentWebLinks.find(text);
    expect(links.map((e) => e.text), [
      'example.com',
      'www.example.org/a',
      'https://en.wikipedia.org/wiki/Dream_(novel)',
    ]);
    for (final link in links) {
      expect(text.substring(link.start, link.end), link.text);
    }
    expect(links.first.start, 4);
    expect(ContentWebLinks.find('网址example.com.').single.text, 'example.com');
  });

  test('无效网址/邮箱/其他协议/普通文字不匹配，不从坏网址截取后缀', () {
    for (final input in [
      '没有网址 普通文字',
      'user@example.com',
      'mailto:user@example.com',
      'ftp://example.com',
      'javascript:example.com',
      'https://',
      'https:/example.com',
      'https://example..com',
      'bad_example.com',
      'example.com_bad',
      'example.com.123',
      'https://example.com:99999',
      'https://example.com:99999999999999999999999999999',
      'https://user:password@example.com',
      '报告.pdf version1.2.3',
      'example.com:abc',
    ]) {
      expect(ContentWebLinks.find(input), isEmpty, reason: input);
    }
    for (final input in [
      'example',
      'example..com',
      '-bad.com',
      'bad-.com',
      'https://256.1.2.3',
      'https://999999999999999999999999999999999.1.2.3',
      'https://example.com:99999',
      'https://example.com:99999999999999999999999999999',
      'https://example.com:0',
      'example.com:abc',
    ]) {
      expect(DreamLink.parseUrl(input), isNull, reason: input);
    }
  });

  test('收紧新输入校验不破坏旧版本已保存的显式HTTP附件', () {
    for (final address in ['http://intranet/a', 'https://old_host/a']) {
      final old = DreamLink(
        id: 'legacy',
        url: address,
        kind: DreamLinkKind.web,
      );
      expect(DreamLink.decode(DreamLink.encode([old])).single.url, address);
    }
  });
}
