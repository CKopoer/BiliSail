import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/bili_icons.dart';
import 'package:bilisail/shared/ui/comment_actions.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = CommentEntry(
  id: '10',
  author: '认真看视频的用户',
  message: '这段讲解很清楚，尤其是最后的例子。\n期待后续的更新！',
  ipLocation: 'IP属地：广东',
  likeCount: 124,
  replyCount: 1,
  replies: [_reply],
);
const _reply = CommentEntry(id: '11', author: '另一位观众', message: '同感，这个例子很有帮助。');

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      (
        'HarmonyOS Sans',
        'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
      ),
      ('BiliIcons', 'assets/fonts/biliicon.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  for (final type in [CommentTargetType.video, CommentTargetType.dynamic]) {
    for (final (width, scale, dark) in [
      (320.0, 1.0, false),
      (320.0, 2.0, true),
      (640.0, 2.0, false),
    ]) {
      testWidgets(
        '${type.name} actions align with context at $width / $scale',
        (tester) async {
          await _mount(
            tester,
            _Comments(),
            type: type,
            width: width,
            scale: scale,
            dark: dark,
          );
          final tile = find.byKey(const ValueKey(('comment', '10')));
          expect(
            tester.getCenter(find.byType(NetworkAvatar)).dy,
            closeTo(
              (tester.getTopLeft(find.text(_root.author)).dy +
                      tester.getBottomLeft(find.text('IP属地：广东')).dy) /
                  2,
              .01,
            ),
          );
          await _snapshot(tester, tile, '${type.name}-${width.toInt()}-$scale');
          final actions = find.descendant(
            of: tile,
            matching: find.byType(CommentActions),
          );
          final body = tester.getRect(
            find
                .descendant(of: tile, matching: find.byType(CommentRichContent))
                .first,
          );
          final replyIcon = tester.getRect(
            find.descendant(
              of: actions,
              matching: find.byIcon(BiliIcons.reply),
            ),
          );
          final likeIcon = tester.getRect(
            find.descendant(
              of: actions,
              matching: find.byIcon(Icons.thumb_up_alt_outlined),
            ),
          );
          final reply = tester.getRect(
            find.descendant(of: actions, matching: find.text('回复')),
          );
          final count = tester.getRect(
            find.descendant(of: actions, matching: find.text('124')),
          );
          final replyButton = tester.getRect(
            find.descendant(
              of: actions,
              matching: find.widgetWithIcon(TextButton, BiliIcons.reply),
            ),
          );
          final likeButton = tester.getRect(
            find.descendant(
              of: actions,
              matching: find.widgetWithIcon(
                TextButton,
                Icons.thumb_up_alt_outlined,
              ),
            ),
          );
          final preview = tester.getRect(
            find
                .ancestor(
                  of: find.text('共 1 条回复 ›'),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(likeIcon.left, closeTo(body.left, .01));
          expect(count.left, greaterThan(likeIcon.right));
          expect(replyIcon.left, closeTo(replyButton.left, .01));
          expect(replyButton.left - likeButton.right, closeTo(12, .01));
          expect(replyButton.right, lessThanOrEqualTo(body.right));
          expect(reply.center.dy, closeTo(count.center.dy, .01));
          expect(replyButton.top, greaterThan(body.bottom));
          expect(replyButton.bottom, lessThan(preview.top));
          expect(preview.left, closeTo(body.left, .01));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final (width, scale) in [
      (320.0, 1.0),
      (390.0, 1.0),
      (640.0, 1.0),
      (320.0, 2.0),
      (390.0, 2.0),
      (640.0, 2.0),
    ]) {
      testWidgets(
        '${type.name} decorated author aligns with avatar at $width / $scale',
        (tester) async {
          final comment = CommentEntry(
            id: '10',
            author: '测试用户',
            message: '16pro出之前这玩意399',
            publishedAt: DateTime(2026, 10, 16),
            ipLocation: 'IP属地：浙江',
            level: 6,
            vipLabel: '大会员',
            decorationImageUrl: Uri.https('i0.hdslb.com', '/card.png'),
            decorationFanNumber: '020451',
          );
          await _mount(
            tester,
            _Comments(root: comment),
            type: type,
            width: width,
            scale: scale,
            dark: scale == 2,
          );
          final tile = find.byKey(const ValueKey(('comment', '10')));
          await _snapshot(
            tester,
            tile,
            'avatar-${type.name}-${width.toInt()}-$scale',
          );
          final avatar = tester.getRect(find.byType(NetworkAvatar));
          final header = tester.getRect(find.byType(CommentAuthorHeader));
          final author = tester.getRect(find.text(comment.author));
          final metadata = tester.getRect(find.text('IP属地：浙江'));
          final decoration = tester.getRect(
            find.byType(CommentAuthorDecoration),
          );
          final body = tester.getRect(find.byType(CommentRichContent));
          expect(
            avatar.center.dy,
            closeTo((author.top + metadata.bottom) / 2, 1),
          );
          expect(metadata.top, greaterThanOrEqualTo(author.bottom));
          expect(body.top, greaterThanOrEqualTo(header.bottom + 8));
          expect(author.left, closeTo(body.left, .01));
          expect(avatar.left, closeTo(header.left, .01));
          expect(decoration.height, lessThanOrEqualTo(52));
          expect(decoration.width, lessThanOrEqualTo(header.width * .4));
          expect(decoration.height / decoration.width, closeTo(52 / 112, .01));
          expect(decoration.center.dy, closeTo(avatar.center.dy, .01));
          expect(decoration.right, closeTo(header.right, .01));
          expect(body.top, greaterThanOrEqualTo(decoration.bottom + 8));
          expect(decoration.left, greaterThan(author.right));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'like count shares the button and busy actions cannot repeat writes',
    (tester) async {
      final repo = _Comments()..pending = Completer<void>();
      final container = await _mount(tester, repo, touch: true);
      for (final button in tester.widgetList<TextButton>(
        find.descendant(
          of: find.byType(CommentActions),
          matching: find.byType(TextButton),
        ),
      )) {
        expect(
          tester.getSize(find.byWidget(button)).height,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.tap(find.text('124'));
      await tester.pump();
      expect(repo.likes, [true]);
      final replyButton = find.widgetWithIcon(TextButton, BiliIcons.reply);
      expect(tester.widget<TextButton>(replyButton).onPressed, isNull);
      await tester.tap(find.text('124'));
      await tester.tap(replyButton);
      await tester.pump();
      expect(repo.likes, [true]);
      expect(
        container.read(videoCommentsControllerProvider('42')).replyTarget,
        isNull,
      );
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('125'), findsOneWidget);
      expect(find.bySemanticsLabel('取消点赞评论'), findsOneWidget);
      final countContext = tester.element(find.text('125'));
      expect(
        DefaultTextStyle.of(countContext).style.color,
        Theme.of(countContext).colorScheme.primary,
      );
      expect(tester.widget<TextButton>(replyButton).onPressed, isNotNull);
      await tester.tap(replyButton);
      await tester.pumpAndSettle();
      expect(
        container.read(videoCommentsControllerProvider('42')).replyTarget?.id,
        '10',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );
      Focus.of(tester.element(find.byIcon(Icons.thumb_up_alt))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(repo.likes, [true, false]);
      expect(find.text('124'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Comments repo, {
  CommentTargetType type = CommentTargetType.video,
  double width = 390,
  double scale = 1,
  bool dark = false,
  bool touch = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_SignedIn.new),
        commentsRepositoryProvider(type).overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: (dark ? BiliTheme.dark() : BiliTheme.light()).copyWith(
          platform: touch ? TargetPlatform.android : TargetPlatform.windows,
          materialTapTargetSize: touch
              ? MaterialTapTargetSize.padded
              : MaterialTapTargetSize.shrinkWrap,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: CommentsPanel(target: CommentTarget('42', type)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CommentsPanel)));
}

Future<void> _snapshot(WidgetTester tester, Finder tile, String name) async {
  final directory = Platform.environment['BILISAIL_COMMENT_LAYOUT_SCREENSHOTS'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: tile, matching: find.byType(RepaintBoundary)).last,
  );
  final box = tester.renderObject<RenderBox>(tile);
  final bounds = MatrixUtils.transformRect(
    box.getTransformTo(boundary),
    Offset.zero & box.size,
  );
  await tester.runAsync(() async {
    final image = await (boundary.debugLayer! as OffsetLayer).toImage(
      bounds,
      pixelRatio: 2,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, mid: '7');
}

class _Comments extends Fake implements CommentsRepository {
  _Comments({this.root = _root});

  final CommentEntry root;
  final likes = <bool>[];
  Completer<void>? pending;
  @override
  String get accountScope => 'user:7';
  @override
  int get sessionEpoch => 0;
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => CommentPage(items: [root], hasMore: false);
  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async => const CommentPage(items: [_reply], hasMore: false);
  @override
  Future<void> like(
    String oid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) async {
    likes.add(liked);
    await pending?.future;
  }
}
