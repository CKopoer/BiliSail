import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/comment_badge.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _reply = CommentEntry(
  id: '11',
  author: '作者',
  authorId: UserId('7'),
  message: '作者回复正文',
  isUpAuthor: true,
  nicknameColor: 0x123456,
);
const _root = CommentEntry(
  id: '10',
  author: '读者',
  message: '置顶评论正文',
  isPinned: true,
  upLiked: true,
  upReplied: true,
  replyCount: 1,
  replies: [_reply],
);

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'badges follow ${dark ? 'dark' : 'light'} theme and wrap at $scale text scale',
        (tester) async {
          final theme = dark ? BiliTheme.dark() : BiliTheme.light();
          UserId? opened;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CommentAuthorHeader(
                          comment: const CommentEntry(
                            id: '10',
                            author: '有较长名称的作者',
                            authorId: UserId('7'),
                            message: '',
                            isPinned: true,
                            isUpAuthor: true,
                          ),
                          onOpenUser: (id) => opened = id,
                        ),
                        const CommentRichContent(comment: _root),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('置顶'), findsOneWidget);
          expect(find.text('UP'), findsOneWidget);
          _expectUpAfterAuthor(tester, find.text('有较长名称的作者'));
          expect(find.text('UP 主觉得很赞'), findsOneWidget);
          expect(find.text('UP 主回复过'), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('UP')).style?.color,
            theme.colorScheme.onPrimaryContainer,
          );
          expect(
            tester.widget<Text>(find.text('置顶')).style?.color,
            theme.colorScheme.primary,
          );
          await tester.tap(find.text('有较长名称的作者'));
          expect(opened, const UserId('7'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final compact in [false, true]) {
    for (final pictureCount in [1, 3]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('UP markers follow all $pictureCount pictures '
            'in ${compact ? 'preview' : 'full'} content at $scale text scale', (
          tester,
        ) async {
          final comment = CommentEntry(
            id: '1',
            author: '读者',
            message: '图片评论正文',
            upLiked: true,
            upReplied: true,
            pictures: List.generate(
              pictureCount,
              (index) => Uri.https('i0.hdslb.com', '/comment-$index.png'),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: BiliTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SizedBox(
                    width: 220,
                    child: CommentRichContent(
                      comment: comment,
                      compact: compact,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final images = find.byType(AppNetworkImage);
          expect(images, findsNWidgets(pictureCount));
          final body = tester.getRect(find.byType(SelectionArea));
          var lastImageBottom = body.bottom;
          for (var index = 0; index < pictureCount; index++) {
            final image = tester.getRect(images.at(index));
            expect(image.top, greaterThanOrEqualTo(body.bottom + 8));
            if (image.bottom > lastImageBottom) {
              lastImageBottom = image.bottom;
            }
          }
          for (final label in ['UP 主觉得很赞', 'UP 主回复过']) {
            expect(
              tester.getRect(find.text(label)).top,
              greaterThanOrEqualTo(lastImageBottom + 6),
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('ordinary comments do not show markers', (tester) async {
    const ordinary = CommentEntry(id: '1', author: '读者', message: '正文');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CommentAuthorHeader(comment: ordinary),
              CommentRichContent(comment: ordinary),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(CommentBadge), findsNothing);
    expect(find.textContaining('UP 主'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final type in [CommentTargetType.video, CommentTargetType.dynamic]) {
    testWidgets(
      '${type.name} comments retain markers in preview, detail and return',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final target = CommentTarget('42', type);
        UserId? opened;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_Guest.new),
              commentsRepositoryProvider(type).overrideWithValue(_Comments()),
            ],
            child: MaterialApp(
              theme: BiliTheme.light(),
              home: Scaffold(
                body: CommentsPanel(
                  target: target,
                  onOpenUser: (id) => opened = id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('置顶'), findsOneWidget);
        expect(find.text('UP'), findsOneWidget);
        _expectUpAfterAuthor(tester, find.text('作者'));
        _expectUpBeforeColon(tester);
        expect(find.text('UP 主觉得很赞'), findsOneWidget);
        expect(find.text('UP 主回复过'), findsOneWidget);
        await tester.tap(find.text('作者'));
        await tester.pumpAndSettle();
        expect(opened, const UserId('7'));
        expect(find.text('共 1 条回复 ›'), findsOneWidget);
        await tester.tap(find.text('共 1 条回复 ›'));
        await tester.pumpAndSettle();
        expect(find.text('置顶'), findsOneWidget);
        expect(find.text('UP'), findsOneWidget);
        expect(find.text('UP 主回复过'), findsOneWidget);
        expect(find.text('作者'), findsOneWidget);
        _expectUpAfterAuthor(tester, find.text('作者'));
        await tester.tap(find.byTooltip('返回评论'));
        await tester.pumpAndSettle();
        expect(find.text('作者'), findsOneWidget);
        _expectUpAfterAuthor(tester, find.text('作者'));
        _expectUpBeforeColon(tester);
        expect(find.text('UP'), findsOneWidget);
        expect(find.text('置顶'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectUpAfterAuthor(WidgetTester tester, Finder author) {
  final badge = tester.getRect(find.text('UP'));
  final name = tester.getRect(author);
  final sameRow = badge.top < name.bottom && name.top < badge.bottom;
  expect(
    sameRow ? name.right <= badge.left : name.bottom <= badge.top,
    isTrue,
    reason:
        'The UP badge must appear after the author, including after wrapping.',
  );
}

void _expectUpBeforeColon(WidgetTester tester) {
  final badge = tester.getRect(find.text('UP'));
  final colon = tester.getRect(find.text('：'));
  expect(badge.right, lessThanOrEqualTo(colon.left));
  expect(badge.center.dy, closeTo(colon.center.dy, 1));
  expect(
    tester.widget<Text>(find.text('：')).style?.color,
    tester.widget<Text>(find.text('作者')).style?.color,
  );
}

class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _Comments extends Fake implements CommentsRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => const CommentPage(items: [_root], hasMore: false);

  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async => const CommentPage(items: [_reply], hasMore: false);
}
