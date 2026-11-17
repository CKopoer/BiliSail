import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/comments/application/comment_link_resolver.dart';
import 'package:bilisail/features/comments/domain/comment_video_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bvid = 'BV117BkBsEWw';
  for (final url in [
    'https://b23.tv/$bvid',
    'http://b23.tv/$bvid/',
    'https://www.bilibili.com/video/$bvid?share_source=copy_link',
    'https://bilibili.com/video/$bvid/',
    'https://m.bilibili.com/video/$bvid.html',
    'https://www.bilibili.com/video/bv117BkBsEWw',
    'bilibili://video/$bvid',
  ]) {
    test('recognizes complete BV path: $url', () {
      expect(parseCommentVideoLink(Uri.parse(url))?.video, const VideoId(bvid));
    });
  }
  for (final url in [
    'https://b23.tv/av170001',
    'https://www.bilibili.com/video/av170001/',
    'http://m.bilibili.com/video/av170001.html?from=share',
    'https://www.bilibili.com/video/AV170001',
    'bilibili://video/170001',
    'bilibili://video/av170001',
  ]) {
    test('keeps AV identity as a decimal string: $url', () {
      expect(parseCommentVideoLink(Uri.parse(url))?.aid, '170001');
    });
  }
  for (final url in [
    'https://example.com/video/$bvid',
    'https://b23.tv.example.com/$bvid',
    'https://www.bilibili.com.example.com/video/$bvid',
    'https://b23.tv@evil.example/$bvid',
    'https://name:password@b23.tv/$bvid',
    'https://b23.tv:8443/$bvid',
    'ftp://b23.tv/$bvid',
    'https://www.bilibili.com/read/cv123?target=$bvid',
    'https://www.bilibili.com/video/$bvid/extra',
    'https://www.bilibili.com/video/BV117BkBsEWw0',
    'https://www.bilibili.com/video/BV117BkBsEW',
    'https://www.bilibili.com/video/av0',
    'https://www.bilibili.com/video/av12evil',
    'https://b23.tv/randomToken',
    'bilibili://video/0',
    'bilibili://video/170001/extra',
    'bilibili://user@video/170001',
    'bilibili://video:80/170001',
    'bilibili://live/170001',
  ]) {
    test('does not misidentify a video: $url', () {
      expect(parseCommentVideoLink(Uri.parse(url)), isNull);
    });
  }
  for (final reference in [
    bvid,
    'bv117BkBsEWw',
    'Bv117BkBsEWw',
    'www.bilibili.com/video/$bvid?p=2',
    '//m.bilibili.com/video/$bvid.html',
    'bilibili://video/$bvid?p=2',
  ]) {
    test('normalizes a comment video reference: $reference', () {
      final uri = parseCommentLinkUri(reference);
      expect(uri, isNotNull);
      expect(uri?.scheme, 'https');
      expect(parseCommentVideoLink(uri!)?.video, const VideoId(bvid));
      if (reference.contains('p=2')) expect(uri.queryParameters['p'], '2');
    });
  }
  test('app references normalize without adding an empty query', () {
    expect(
      parseCommentLinkUri('bilibili://video/170001').toString(),
      'https://www.bilibili.com/video/av170001',
    );
  });
  test('direct BV links need no repository or network', () async {
    final resolver = CommentLinkResolver(() => throw StateError('network'));
    expect(
      await resolver.resolve(
        Uri.parse('https://b23.tv/$bvid'),
        RequestCancellation(),
      ),
      const VideoId(bvid),
    );
    expect(
      await resolver.resolve(
        Uri.parse('https://example.com/$bvid'),
        RequestCancellation(),
      ),
      isNull,
    );
    expect(
      await resolver.resolve(
        Uri.parse('https://b23.tv/$bvid'),
        RequestCancellation()..cancel(),
      ),
      isNull,
    );
  });
}
