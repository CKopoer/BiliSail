import 'package:bili_api/bili_api.dart';
import 'package:bili_lite/domain/dynamic_post.dart';
import 'package:bili_lite/shared/data/dynamic_post_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared mapping preserves rich content, original identity and video metadata', () {
    final stamp = DateTime.utc(2026, 10, 5);
    final image = Uri.https('i0.hdslb.com', '/emoji.png');
    final api = ApiDynamicPost(
      id: '1',
      authorId: '900719925474099312345',
      text: '[表情]@用户',
      spans: [
        ApiDynamicTextSpan(
          kind: ApiDynamicTextKind.emoji,
          text: '[表情]',
          imageUrl: image,
          emojiSize: 2,
        ),
        const ApiDynamicTextSpan(
          kind: ApiDynamicTextKind.mention,
          text: '@用户',
          userId: '2',
        ),
      ],
      imageUrls: [image],
      original: ApiDynamicPost(id: '3', text: '原动态'),
      video: ApiVideoSummary(
        bvid: 'BV1234567890',
        title: '视频',
        coverUrl: image,
        ownerName: '作者',
        ownerMid: '2',
        ownerAvatarUrl: image,
        duration: const Duration(seconds: 70),
        playCount: 123,
        danmakuCount: 4,
        publishedAt: stamp,
      ),
      likeCount: 5,
      commentCount: 6,
      repostCount: 7,
      linkTitle: '专栏',
      linkDescription: '描述',
      linkCoverUrl: image,
      linkUrl: Uri.https('t.bilibili.com', '/1'),
    );
    final post = mapDynamicPost(api);
    expect(post.authorId?.value, '900719925474099312345');
    expect(post.spans.first.kind, DynamicTextKind.emoji);
    expect(post.spans.first.emojiSize, 2);
    expect(post.spans.last.userId?.value, '2');
    expect(post.original?.id, '3');
    expect(post.video?.danmakuCount, 4);
    expect(post.video?.publishedAt, stamp);
    expect(post.video?.authorId?.value, '2');
    expect(post.repostCount, 7);
    expect(post.linkTitle, '专栏');
    expect(post.linkDescription, '描述');
    expect(() => post.spans.clear(), throwsUnsupportedError);
    expect(() => post.imageUrls.clear(), throwsUnsupportedError);
  });
}
