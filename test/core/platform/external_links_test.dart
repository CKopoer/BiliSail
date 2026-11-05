import 'package:bilisail/core/platform/external_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message short links use the same HTTPS external-link boundary', () {
    expect(isAllowedExternalLink(Uri.parse('https://b23.tv/fixture')), isTrue);
    for (final url in [
      'http://b23.tv/fixture',
      'https://b23.tv:444/fixture',
      'https://user@b23.tv/fixture',
      'https://b23.tv.evil.example/fixture',
    ]) {
      expect(isAllowedExternalLink(Uri.parse(url)), isFalse, reason: url);
    }
  });

  test('comment opener accepts arbitrary HTTP(S) hosts and query strings', () {
    for (final url in [
      'https://daily.juya.uk/issues/2026-10-06/',
      'http://example.com:8080/watch?t=00:09#part',
    ]) {
      expect(isAllowedWebLink(Uri.parse(url)), isTrue);
    }
    expect(
      isAllowedExternalLink(
        Uri.parse('https://daily.juya.uk/issues/2026-10-06/'),
      ),
      isFalse,
    );
  });

  test(
    'comment opener rejects non-web schemes, missing hosts and credentials',
    () {
      for (final url in [
        'javascript:alert(1)',
        'file:///tmp/x',
        'bilibili://video/123',
        '/relative',
        'https:///path',
        'https://user:secret@example.com/',
      ]) {
        expect(isAllowedWebLink(Uri.parse(url)), isFalse, reason: url);
      }
    },
  );
}
