import 'package:bili_api/bili_api.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/shared/data/dynamic_post_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dynamic actions retain typed comment identity and flags across originals',
    () {
      final post = mapDynamicPost(
        ApiDynamicPost(
          id: '9007199254740993123',
          commentOid: '9007199254740993124',
          commentType: 11,
          liked: true,
          commentForbidden: true,
          repostForbidden: true,
          original: ApiDynamicPost(id: '3', commentOid: '4', commentType: 1),
        ),
      );
      expect(
        post.commentTarget,
        const CommentTarget('9007199254740993124', CommentTargetType.album),
      );
      expect(
        post.original?.commentTarget,
        const CommentTarget('4', CommentTargetType.video),
      );
      expect(post.liked, true);
      expect(post.commentForbidden, true);
      expect(post.repostForbidden, true);
      expect(
        mapDynamicPost(
          ApiDynamicPost(id: '1', commentOid: '2', commentType: 99),
        ).commentTarget,
        isNull,
      );
    },
  );
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
      imageAspectRatios: {image: 1.5},
      original: ApiDynamicPost(
        id: '3',
        text: '原动态',
        imageUrls: [image],
        imageAspectRatios: {image: 2 / 3},
      ),
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
    expect(post.imageAspectRatios[image], 1.5);
    expect(post.original?.imageAspectRatios[image], 2 / 3);
    expect(post.video?.danmakuCount, 4);
    expect(post.video?.publishedAt, stamp);
    expect(post.video?.authorId?.value, '2');
    expect(post.repostCount, 7);
    expect(post.linkTitle, '专栏');
    expect(post.linkDescription, '描述');
    expect(() => post.spans.clear(), throwsUnsupportedError);
    expect(() => post.imageUrls.clear(), throwsUnsupportedError);
    expect(() => post.imageAspectRatios.clear(), throwsUnsupportedError);
  });
}
