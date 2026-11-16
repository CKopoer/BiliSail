import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
  });

  for (final width in [300.0, 306.0, 360.0, 640.0]) {
    testWidgets('author header hides VIP label at $width pixels', (
      tester,
    ) async {
      final users = <UserId>[];
      final comment = CommentEntry(
        id: '1',
        authorId: const UserId('7'),
        author: '黑嵐uncle',
        message: 'nice，双十一的尾巴',
        nicknameColor: 0xfb7299,
        level: 6,
        vipLabel: '年度大会员',
        ipLocation: 'IP属地：上海',
        decorationImageUrl: Uri.https('i0.hdslb.com', '/card.png'),
        decorationFanNumber: '012515',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: width + CommentAuthorHeader.contentIndent,
              child: CommentAuthorHeader(
                comment: comment,
                onOpenUser: users.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final author = tester.getRect(find.text(comment.author));
      final level = tester.getRect(find.byType(BiliLevelBadge));
      expect(find.text(comment.vipLabel!), findsNothing);
      expect(
        tester.widget<Text>(find.text(comment.author)).style?.color,
        const Color(0xfffb7299),
      );
      final decoration = tester.getRect(find.byType(CommentAuthorDecoration));
      expect(level.center.dy, closeTo(author.center.dy, .01));
      expect(level.left, greaterThan(author.right));
      expect(level.right, lessThanOrEqualTo(decoration.left - 8));
      expect(decoration.right, width + CommentAuthorHeader.contentIndent);
      expect(decoration.height, 52);
      expect(tester.widget<Text>(find.text('NO.\n012515')).style?.fontSize, 12);
      await tester.tap(find.text(comment.author));
      await tester.tap(find.byType(NetworkAvatar));
      expect(users, [const UserId('7'), const UserId('7')]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final label in ['大会员', '年度大会员']) {
    testWidgets('reply preview hides VIP label $label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentRichContent(
              prefix: '作者：',
              compact: true,
              comment: CommentEntry(
                id: '1',
                author: '作者',
                message: '回复正文',
                vipLabel: label,
                level: 6,
                verifyType: 1,
                medalName: '粉丝牌',
                medalLevel: 10,
              ),
            ),
          ),
        ),
      );
      expect(find.text(label), findsNothing);
      expect(find.byType(BiliLevelBadge), findsOneWidget);
      expect(find.byType(BiliVerifyBadge), findsOneWidget);
      expect(find.text('粉丝牌 10'), findsOneWidget);
      expect(find.text('作者：回复正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final decorated in [false, true]) {
    testWidgets('single-line author stays centered, decorated: $decorated', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: CommentAuthorHeader(
                comment: CommentEntry(
                  id: '1',
                  author: '单行作者',
                  message: '',
                  pendantUrl: Uri.https('i0.hdslb.com', '/pendant.png'),
                  decorationImageUrl: decorated
                      ? Uri.https('i0.hdslb.com', '/card.png')
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avatar = tester.getRect(find.byType(NetworkAvatar));
      final author = tester.getRect(find.text('单行作者'));
      final header = tester.getRect(find.byType(CommentAuthorHeader));
      expect(author.center.dy, closeTo(avatar.center.dy, .01));
      expect(avatar.center.dy, closeTo(header.center.dy, .01));
      expect(avatar.width, closeTo(30, .01));
      expect(avatar.height, closeTo(30, .01));
      expect(author.left, CommentAuthorHeader.contentIndent);
      if (decorated) {
        final decoration = tester.getRect(find.byType(CommentAuthorDecoration));
        expect(decoration.center.dy, closeTo(avatar.center.dy, .01));
        expect(decoration.width, closeTo(108, .01));
        expect(decoration.height, closeTo(108 * 52 / 112, .01));
      } else {
        expect(header.height, 30);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
