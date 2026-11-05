import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comment_composer.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/message_reply_sheet.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  late AuthFake auth;
  late _Comments comments;
  setUp(() {
    auth = AuthFake();
    comments = _Comments();
  });
  tearDown(() => auth.stream.close());

  Future<void> mount(
    WidgetTester tester, {
    double width = 640,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(MessageRepositoryFake()),
          videoCommentsRepositoryProvider.overrideWithValue(comments),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: AppNoticeHost(child: child!),
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showMessageReply(
                  context,
                  ref,
                  const InboxEntry(
                    id: 'notification:900',
                    title: '作者回复了你',
                    text: '回复正文',
                    replyContext: MessageReplyContext(
                      subjectId: '170001',
                      businessId: 1,
                      rootId: '123',
                      parentId: '9007199254740993',
                      author: '作者',
                      userId: UserId('2'),
                    ),
                  ),
                ),
                child: const Text('打开回复'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开回复'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'notification reply preserves subject/root/parent without loading a comment feed',
    (tester) async {
      await mount(tester);
      expect(comments.loads, 0);
      expect(find.byTooltip('取消回复'), findsNothing);
      await tester.enterText(find.byType(TextField), '[微笑]收到');
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(comments.sent, ('170001', '123', '9007199254740993', '[微笑]收到'));
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reply sheet retains text and blocks uncertain resend until reviewed',
    (tester) async {
      comments.uncertain = true;
      await mount(tester, width: 320, scale: 2);
      await tester.enterText(find.byType(TextField), '保留草稿');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('发布'));
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsOneWidget);
      expect(find.text('我已核对结果，允许再次发送'), findsOneWidget);
      expect(comments.posts, 1);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '发布'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'standalone reply controller drops its initial target on account changes',
    () async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          videoCommentsRepositoryProvider.overrideWithValue(comments),
          videoCommentsControllerProvider('170001').overrideWith(
            () => CommentsController(
              '170001',
              loadInitially: false,
              initialReply: const CommentEntry(
                id: '9007199254740993',
                author: '作者',
                message: '原回复',
                rootId: '123',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        commentsProviderFor(
          const CommentTarget('170001', CommentTargetType.video),
        ),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        container
            .read(videoCommentsControllerProvider('170001'))
            .replyTarget
            ?.rootId,
        '123',
      );
      await auth.signOut();
      expect(
        container.read(videoCommentsControllerProvider('170001')).replyTarget,
        isNull,
      );
      expect(comments.loads, 0);
    },
  );
}

class _Comments extends Fake implements CommentsRepository {
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 1;
  int loads = 0, posts = 0;
  bool uncertain = false;
  (String, String?, String?, String)? sent;
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async {
    loads++;
    return const CommentPage(items: [], hasMore: false);
  }

  @override
  Future<CommentEntry> send(
    String oid,
    String message, {
    String? rootId,
    String? parentId,
    List<CommentPicture> pictures = const [],
    Map<String, UserId> mentions = const {},
    bool syncToDynamic = false,
    required RequestCancellation cancellation,
  }) async {
    posts++;
    if (uncertain) throw const CommentWriteUncertain();
    sent = (oid, rootId, parentId, message);
    return CommentEntry(id: 'reply:1', author: '我', message: message);
  }
}
