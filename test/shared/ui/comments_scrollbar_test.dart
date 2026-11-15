import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = CommentTarget('42', CommentTargetType.video);

void main() {
  testWidgets('measuring comments leaves offscreen media unloaded', (
    tester,
  ) async {
    final requests = <ImageLoadRequest>[];
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (_, request) {
          requests.add(request);
          return Completer<Uint8List>().future;
        },
      ),
    );
    final repo = _Comments(media: true);
    try {
      await _mount(tester, repo: repo, cache: cache);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(requests, isNotEmpty);
      expect(requests.length, lessThan(35));
      final position = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .position;
      final extent = position.maxScrollExtent;
      position.jumpTo(extent * .5);
      await tester.pumpAndSettle();
      expect(position.maxScrollExtent, closeTo(extent, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(requests.every((request) => request.cancelled), isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox());
      cache.dispose();
    }
  });
  testWidgets('comment extents follow width and text scale changes', (
    tester,
  ) async {
    final metrics = ValueNotifier(const MediaQueryData(size: Size(800, 600)));
    addTearDown(metrics.dispose);
    await _mount(tester, metrics: metrics);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    final original = controller.position.maxScrollExtent;
    metrics.value = metrics.value.copyWith(size: const Size(200, 600));
    await tester.pumpAndSettle();
    final narrow = controller.position.maxScrollExtent;
    expect(narrow, greaterThan(original));
    metrics.value = metrics.value.copyWith(
      textScaler: const TextScaler.linear(1.5),
    );
    await tester.pumpAndSettle();
    final scaled = controller.position.maxScrollExtent;
    expect(scaled, greaterThan(narrow));
    controller.jumpTo(scaled);
    await tester.pumpAndSettle();
    expect(find.text('没有更多了'), findsOneWidget);
    expect(controller.position.maxScrollExtent, closeTo(scaled, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final replies in [false, true]) {
    testWidgets(
      '${replies ? 'replies' : 'comments'} keep the scroll range stable while dragging a mouse thumb',
      (tester) async {
        final container = await _mount(tester);
        if (replies) {
          final provider = commentsProviderFor(_target);
          await container
              .read(provider.notifier)
              .openReplies(container.read(provider).items.first);
          await tester.pumpAndSettle();
        }
        final list = find.byType(ListView);
        final position = tester.widget<ListView>(list).controller!.position;
        final extent = position.maxScrollExtent;
        final rect = tester.getRect(list);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: rect.topRight + const Offset(-6, 10));
        await tester.pumpAndSettle();
        await mouse.down(rect.topRight + const Offset(-6, 10));
        await mouse.moveBy(const Offset(0, 20));
        await tester.pump();
        for (final dy in [20.0, 40.0, 60.0, 80.0, -20.0, -40.0, -60.0]) {
          final before = position.pixels;
          await mouse.moveBy(Offset(0, dy));
          await tester.pump();
          expect(
            position.pixels,
            dy > 0 ? greaterThan(before) : lessThan(before),
          );
          expect(position.maxScrollExtent, closeTo(extent, .01));
          expect(
            find.byType(CommentRichContent).evaluate().length,
            lessThan(35),
          );
          expect(tester.takeException(), isNull);
        }
        await mouse.up();
        await mouse.removePointer();
        await tester.pumpAndSettle();
      },
    );
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  ValueNotifier<MediaQueryData>? metrics,
  _Comments? repo,
  AppImageCache? cache,
}) async {
  const panel = CommentsPanel(target: _target);
  final app = ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_Guest.new),
      commentsRepositoryProvider(_target.type)
          .overrideWithValue(repo ?? _Comments()),
    ],
    child: MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        scrollbarTheme: const ScrollbarThemeData(
          thumbVisibility: WidgetStatePropertyAll(true),
          thickness: WidgetStatePropertyAll(12),
          mainAxisMargin: 0,
          crossAxisMargin: 0,
          minThumbLength: 18,
        ),
      ),
      home: Scaffold(
        body: metrics == null
            ? panel
            : ValueListenableBuilder(
                valueListenable: metrics,
                child: panel,
                builder: (_, value, child) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: value.size.width,
                    child: MediaQuery(data: value, child: child!),
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpWidget(
    cache == null ? app : AppImageCacheScope(cache: cache, child: app),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CommentsPanel)));
}

class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _Comments extends Fake implements CommentsRepository {
  _Comments({bool media = false})
    : items = List.generate(
        150,
        (i) => CommentEntry(
          id: '$i',
          author: '用户 $i',
          message: List.filled(
            1 + (i ~/ 10 % 3) * 8,
            '长短交替评论 $i${media ? '[笑]' : ''}',
          ).join('\n'),
          avatarUrl: media ? Uri.https('i0.hdslb.com', '/avatar-$i.png') : null,
          decorationImageUrl: media
              ? Uri.https('i0.hdslb.com', '/decoration-$i.png')
              : null,
          emotes: media
              ? {'[笑]': Uri.https('i0.hdslb.com', '/emote-$i.png')}
              : const {},
          pictures: media
              ? [Uri.https('i0.hdslb.com', '/picture-$i.png')]
              : const [],
          replyCount: 150,
          replies: i.isEven
              ? [
                  const CommentEntry(
                    id: 'preview',
                    author: '回复',
                    message: '楼中楼\n回复预览',
                  ),
                ]
              : const [],
        ),
      );
  final List<CommentEntry> items;

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
  }) async => CommentPage(items: items, hasMore: false);
  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async => CommentPage(items: items, hasMore: false);
}
