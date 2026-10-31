import 'dart:async';
import 'dart:convert';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comment_composer.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';

final _image = CommentLocalImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  ),
  'image/png',
);
const _target = CommentTarget('42', CommentTargetType.video);

void main() {
  late _Repo repo;
  late DynamicAuthFake auth;
  late ProviderContainer container;
  late CommentsController controller;
  Completer<List<CommentLocalImage>>? pendingPick;

  setUp(() async {
    pendingPick = null;
    repo = _Repo();
    auth = DynamicAuthFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        commentsRepositoryProvider.overrideWith((ref, type) => repo),
        videoCommentsRepositoryProvider.overrideWithValue(repo),
        commentImagePickerProvider.overrideWithValue(
          (remaining) async => pendingPick?.future ?? [_image],
        ),
      ],
    );
    container.listen(commentsProviderFor(_target), (_, _) {});
    controller = container.read(commentsProviderFor(_target).notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    auth.stream.close();
  });

  Future<void> show(
    WidgetTester tester, {
    double width = 800,
    double scale = 1,
    double keyboard = 0,
    CommentTarget target = _target,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: AppNoticeHost(child: child!),
          ),
          home: Scaffold(
            body: CommentsPanel(
              target: target,
              playbackPosition: target.type == CommentTargetType.video
                  ? () => const Duration(seconds: 3723)
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
  }

  test(
    'upload failure sends no comment; explicit retry uploads and submits once',
    () async {
      repo.uploadError = const AppFailure(AppFailureKind.network, '上传失败');
      expect(await controller.send('图文', images: [_image]), false);
      expect(repo.posts, 0);
      expect(container.read(commentsProviderFor(_target)).uncertain, isEmpty);
      repo.uploadError = null;
      expect(
        await controller.send(
          '@读者 ',
          images: [_image],
          mentions: {
            '读者': const UserId('9007199254740993'),
            '已删除': const UserId('8'),
          },
          syncToDynamic: true,
        ),
        true,
      );
      expect(repo.posts, 1);
      expect(repo.pictures, hasLength(1));
      expect(repo.mentions, {'读者': const UserId('9007199254740993')});
      expect(repo.sync, true);
    },
  );

  test(
    'account changes during upload never post with the next account',
    () async {
      repo.pendingUpload = Completer<CommentPicture>();
      final result = controller.send('', images: [_image]);
      await Future<void>.delayed(Duration.zero);
      repo.sessionEpoch++;
      auth.change(const AuthState());
      await Future<void>.delayed(Duration.zero);
      repo.pendingUpload!.complete(_picture);
      expect(await result, false);
      expect(repo.posts, 0);
    },
  );

  test(
    'image replies and excessive image counts are rejected before upload',
    () async {
      controller.target(
        const CommentEntry(id: '10', author: '甲', message: '原文'),
      );
      expect(await controller.send('回复', images: [_image]), false);
      controller.cancelTarget();
      expect(
        await controller.send('图片', images: List.filled(10, _image)),
        false,
      );
      expect(repo.uploads, 0);
      expect(repo.posts, 0);
    },
  );

  testWidgets('late image selection is discarded after an account transition', (
    tester,
  ) async {
    pendingPick = Completer<List<CommentLocalImage>>();
    await show(tester);
    await tester.tap(find.byTooltip('添加图片（最多9张，每张10MB）'));
    await tester.pump();
    repo.sessionEpoch++;
    auth.change(const AuthState());
    await tester.pump();
    pendingPick!.complete([_image]);
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除图片 1'), findsNothing);
    expect(repo.uploads, 0);
    expect(repo.posts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'image-only draft previews, removes, and submits after explicit Publish',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('添加图片（最多9张，每张10MB）'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('移除图片 1'), findsOneWidget);
      expect(repo.uploads, 0);
      await tester.tap(find.byTooltip('移除图片 1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('移除图片 1'), findsNothing);
      await tester.tap(find.byTooltip('添加图片（最多9张，每张10MB）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(repo.uploads, 1);
      expect(repo.posts, 1);
      expect(find.byTooltip('移除图片 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale, keyboard) in [
    (800.0, 1.0, 0.0),
    (320.0, 2.0, 300.0),
  ]) {
    testWidgets(
      'tools and attachments fit $width pixels at $scale scale with keyboard',
      (tester) async {
        await show(tester, width: width, scale: scale, keyboard: keyboard);
        await tester.tap(find.byTooltip('插入当前播放时间'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '1:02:03 ',
        );
        await tester.tap(find.byTooltip('同步到动态'));
        await tester.pumpAndSettle();
        expect(find.text('发布时同步到动态'), findsOneWidget);
        await tester.tap(find.byTooltip('添加图片（最多9张，每张10MB）'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('发布'));
        await tester.tap(find.text('发布'));
        await tester.pumpAndSettle();
        expect(repo.posts, 1);
        expect(repo.sync, true);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dynamic composer inserts selected mention into the selection', (
    tester,
  ) async {
    await show(
      tester,
      target: const CommentTarget('42', CommentTargetType.album),
    );
    expect(find.byTooltip('插入当前播放时间'), findsNothing);
    await tester.enterText(find.byType(TextField), '替换');
    final input = tester.widget<TextField>(find.byType(TextField)).controller!;
    input.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    await tester.tap(find.byTooltip('@用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('读者'));
    await tester.pumpAndSettle();
    expect(input.text, '@读者 ');
    expect(repo.posts, 0);
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(repo.mentions, {'读者': const UserId('9007199254740993')});
    expect(tester.takeException(), isNull);
  });
}

final _picture = CommentPicture(
  Uri.parse('https://i0.hdslb.com/bfs/new_dyn/fixture.png'),
  1,
  1,
  1,
);

class _Repo extends Fake
    implements CommentsRepository, CommentComposerRepository {
  @override
  String get accountScope => 'user:7';
  @override
  int sessionEpoch = 1;
  int posts = 0, uploads = 0;
  bool sync = false;
  List<CommentPicture> pictures = [];
  Map<String, UserId> mentions = {};
  Object? uploadError;
  Completer<CommentPicture>? pendingUpload;
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => const CommentPage(items: [], hasMore: false);
  @override
  Future<List<CommentMention>> searchMentions(
    String keyword,
    RequestCancellation cancellation,
  ) async => const [CommentMention(UserId('9007199254740993'), '读者')];
  @override
  Future<CommentPicture> uploadPicture(
    CommentLocalImage image,
    RequestCancellation cancellation,
  ) async {
    uploads++;
    if (uploadError case final Object error) throw error;
    return pendingUpload?.future ?? _picture;
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
    this.pictures = pictures;
    this.mentions = mentions;
    sync = syncToDynamic;
    return CommentEntry(id: '$posts', author: '我', message: message);
  }
}
