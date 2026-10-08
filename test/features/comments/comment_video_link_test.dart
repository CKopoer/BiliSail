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
  ]) {
    test('recognizes complete BV path: $url', () {
      expect(parseCommentVideoLink(Uri.parse(url))?.video, const VideoId(bvid));
    });
  }
  for (final url in [
    'https://b23.tv/av170001',
    'https://www.bilibili.com/video/av170001/',
    'http://m.bilibili.com/video/av170001.html?from=share',
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
  ]) {
    test('does not misidentify a video: $url', () {
      expect(parseCommentVideoLink(Uri.parse(url)), isNull);
    });
  }
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
