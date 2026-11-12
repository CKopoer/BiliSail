import '../../support/input_test_app.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilisail/features/video/presentation/comment_rich_content.dart';
import 'package:bilisail/features/video/domain/video_comments_repository.dart';

void main() {
  testWidgets(
    'large comment GIF animates and opens a preview before its original',
    (tester) async {
      // Two lossless 2x2 WebP frames, red then blue, at 100ms per frame.
      // Generated from raw RGBA pixels with FFmpeg's libwebp_anim encoder.
      final bytes = base64Decode(
        'UklGRoQAAABXRUJQVlA4WAoAAAACAAAAAQAAAQAAQU5JTQYAAAD/////AABB'
        'Tk1GKAAAAAAAAAAAAAEAAAEAAGQAAAJWUDhMDwAAAC8BQAAABxD9j/4HIqL/'
        'AQBBTk1GKAAAAAAAAAAAAAEAAAEAAGQAAABWUDhMDwAAAC8BQAAABxDR//4H'
        'IqL/AQA=',
      );
      final source = Uri.parse('http://i0.hdslb.com/bfs/new_dyn/large.gif');
      final downloaded = <Uri>[];
      final originals = _Originals(
        OriginalImage(bytes: bytes, width: 2, height: 2),
      );
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (uri, limits) async {
            downloaded.add(uri);
            // Reproduce a GIF larger than the unchanged 4 MiB cache limit.
            return uri.path == source.path
                ? Uint8List(limits.maxBytes + 1)
                : bytes;
          },
        ),
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              originalImageRepositoryProvider.overrideWithValue(originals),
            ],
            child: AppImageCacheScope(
              cache: cache,
              child: InputTestApp(
                home: Scaffold(
                  body: CommentRichContent(
                    comment: CommentEntry(
                      id: 'large-gif',
                      author: 'reader',
                      message: 'comment',
                      pictures: [source],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final thumbnail = find.descendant(
          of: find.byType(CommentRichContent),
          matching: find.byType(RawImage),
        );
        Future<List<int>?> pixels() async {
          if (thumbnail.evaluate().isEmpty) return null;
          final image = tester.widget<RawImage>(thumbnail).image?.clone();
          if (image == null) return null;
          try {
            final data = await tester.runAsync(image.toByteData);
            return data?.buffer.asUint8List().take(4).toList();
          } finally {
            image.dispose();
          }
        }

        Future<List<int>> waitForFrame({List<int>? differentFrom}) async {
          for (var attempt = 0; attempt < 40; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 50));
            final frame = await pixels();
            if (frame != null &&
                (differentFrom == null ||
                    frame.toString() != differentFrom.toString())) {
              return frame;
            }
          }
          fail('Animated comment thumbnail did not deliver a frame');
        }

        final first = await waitForFrame();
        final second = await waitForFrame(differentFrom: first);
        expect(
          [first, second],
          unorderedEquals([
            [255, 0, 0, 255],
            [0, 0, 255, 255],
          ]),
        );
        expect(downloaded, [
          Uri.parse('$source@264w_1280h_0e.webp').replace(scheme: 'https'),
        ]);
        expect(cache.bytes.maxImageBytes, 4 * 1024 * 1024);
        expect(find.text('图片加载失败'), findsNothing);
        expect(originals.sources, isEmpty);
        await tester.tap(find.byType(InkWell));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ImageViewer), findsOneWidget);
        expect(originals.sources, [
          Uri.parse('$source@1280w_1280h_0e.webp').replace(scheme: 'https'),
        ]);
        expect(find.text('查看原图'), findsOneWidget);
        await tester.tap(find.text('查看原图'));
        await tester.pump();
        expect(originals.sources.last, source);
        expect(downloaded, hasLength(1));
        await tester.tap(find.byTooltip('关闭图片'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await cache.close();
      }
    },
  );

  testWidgets(
    'mention taps update with user IDs, callbacks and missing metadata',
    (tester) async {
      final first = <UserId>[], second = <UserId>[];
      Future<void> show(
        Map<String, UserId> mentions,
        ValueChanged<UserId>? onOpenUser,
      ) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentRichContent(
              comment: CommentEntry(
                id: '1',
                author: 'author',
                message: '回复 @小迷糊陈 :看了',
                mentionedUsers: mentions,
              ),
              onOpenUser: onOpenUser,
            ),
          ),
        ),
      );
      await show(const {'小迷糊陈': UserId('100')}, first.add);
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      await show(const {'小迷糊陈': UserId('100')}, second.add);
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      await show(const {'小迷糊陈': UserId('101')}, second.add);
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      await show(const {}, second.add);
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      await show(const {'小迷糊陈': UserId('101')}, null);
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      expect(first, [const UserId('100')]);
      expect(second, [const UserId('100'), const UserId('101')]);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inline links and timestamps share style and respond to real taps',
    (tester) async {
      final opened = <Uri>[], sought = <Duration>[];
      final message =
          '30tps -&gt; 50tps没有\nhttps://daily.juya.uk/issues/2026-10-06/\n'
          '00:09  内容\n00：34  内容\n00：52  内容\n0：01:02  内容\n0:01：03  内容';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: CommentRichContent(
                comment: CommentEntry(id: '1', author: 'a', message: message),
                onOpenLink: opened.add,
                onSeek: sought.add,
              ),
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(CommentRichContent),
          matching: find.byType(Text),
        ),
      );
      expect(text.textSpan?.toPlainText(), contains('30tps -> 50tps没有'));
      final children = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      final interactive = children
          .where((span) => span.recognizer != null)
          .toList();
      expect(interactive, hasLength(6));
      expect(interactive.map((span) => span.style).toSet(), hasLength(1));
      expect(interactive.first.style?.color, const Color(0xFF008AC5));
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(opened, isEmpty);
      expect(sought, isEmpty);
      await tester.tapOnText(
        find.textRange.ofSubstring('https://daily.juya.uk/issues/2026-10-06/'),
      );
      for (final time in ['00:09', '00：34', '00：52', '0：01:02', '0:01：03']) {
        await tester.tapOnText(find.textRange.ofSubstring(time));
      }
      expect(opened, [Uri.parse('https://daily.juya.uk/issues/2026-10-06/')]);
      expect(sought, [
        const Duration(seconds: 9),
        const Duration(seconds: 34),
        const Duration(seconds: 52),
        const Duration(minutes: 1, seconds: 2),
        const Duration(minutes: 1, seconds: 3),
      ]);
    },
  );

  testWidgets(
    'narrow scaled comments keep emotes, links and timecodes inline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 180,
                child: CommentRichContent(
                  compact: true,
                  comment: CommentEntry(
                    id: '1',
                    author: 'a',
                    message: '[笑] 00:09 https://example.com/a/b/c',
                    emotes: {'[笑]': Uri.https('i0.hdslb.com', '/e.png')},
                  ),
                  onOpenLink: (_) {},
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reused rich content updates text and tap handlers', (
    tester,
  ) async {
    final first = <Duration>[], second = <Duration>[];
    Future<void> show(String message, ValueChanged<Duration> onSeek) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CommentRichContent(
                comment: CommentEntry(id: '1', author: 'a', message: message),
                onSeek: onSeek,
              ),
            ),
          ),
        );
    await show('00:09', first.add);
    await tester.tapOnText(find.textRange.ofSubstring('00:09'));
    await show('00:09', second.add);
    await tester.tapOnText(find.textRange.ofSubstring('00:09'));
    await show('00:34', second.add);
    await tester.tapOnText(find.textRange.ofSubstring('00:34'));
    expect(first, [const Duration(seconds: 9)]);
    expect(second, [const Duration(seconds: 9), const Duration(seconds: 34)]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final width in [180.0, 220.0, 260.0, 299.0, 320.0]) {
    testWidgets('decoration image and fan serial fit $width pixel header', (
      tester,
    ) async {
      final comment = CommentEntry(
        id: '1',
        author: '很长的用户名称用于测试换行',
        nicknameColor: 0x123456,
        message: 'comment',
        level: 6,
        publishedAt: DateTime(2026, 10, 6),
        ipLocation: 'IP属地：内蒙古',
        decorationImageUrl: Uri.https('i0.hdslb.com', '/card.png'),
        decorationName: '装扮名称',
        decorationFanNumber: '0014931',
        decorationFanColor: 0xabcdef,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: CommentAuthorHeader(comment: comment),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BiliLevelBadge), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(comment.author)).style?.color,
        const Color(0xFF123456),
      );
      expect(find.text('IP属地：内蒙古'), findsOneWidget);
      expect(find.text('装扮名称'), findsNothing);
      final serial = tester.widget<Text>(find.text('NO.\n0014931'));
      expect(serial.style?.color, const Color(0xffabcdef));
      final image = tester.widget<AppNetworkImage>(
        find.byType(AppNetworkImage),
      );
      expect(image.url, 'https://i0.hdslb.com/card.png');
      expect(image.cacheWidth, isNull);
      expect(image.cacheHeight, 52);
      expect(image.fit, BoxFit.contain);
      expect(image.height, 52);
      expect(serial.style?.fontSize, 12);
      final serialText = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('NO.\n0014931'),
          matching: find.byType(RichText),
        ),
      );
      expect(serialText.didExceedMaxLines, isFalse);
      final decorationRect = tester.getRect(
        find.byType(CommentAuthorDecoration),
      );
      expect(decorationRect.height, lessThanOrEqualTo(52));
      expect(decorationRect.width, lessThanOrEqualTo(width * .4));
      expect(decorationRect.right, width);
      expect(
        tester.getRect(find.text('NO.\n0014931')).right,
        decorationRect.right,
      );
      final headerRect = tester.getRect(find.byType(CommentAuthorHeader));
      expect(decorationRect.top, greaterThanOrEqualTo(headerRect.top));
      expect(decorationRect.bottom, lessThanOrEqualTo(headerRect.bottom));
      expect(
        decorationRect.left,
        greaterThan(tester.getRect(find.byType(BiliLevelBadge)).right),
      );
      expect(
        decorationRect.left,
        greaterThan(tester.getRect(find.text(comment.author)).right),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('comment dates include the year outside the current local year', (
    tester,
  ) async {
    final year = DateTime.now().year;
    final dates = [
      (DateTime(year - 1, 5, 25), '${year - 1}-05-25'),
      (DateTime(year + 1, 5, 25), '${year + 1}-05-25'),
      (DateTime(year - 1, 1, 1).toUtc(), '${year - 1}-01-01'),
    ];
    for (final (publishedAt, label) in dates) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentAuthorHeader(
              comment: CommentEntry(
                id: '1',
                author: 'reader',
                message: 'comment',
                publishedAt: publishedAt,
              ),
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('IP location follows the date in the existing metadata style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentAuthorHeader(
            comment: CommentEntry(
              id: '1',
              author: 'reader',
              message: 'comment',
              publishedAt: DateTime.now().subtract(const Duration(minutes: 5)),
              ipLocation: 'IP属地：广东',
            ),
          ),
        ),
      ),
    );
    final date = find.text('5分钟前');
    final location = find.text('IP属地：广东');
    expect(
      tester.widget<Text>(location).style,
      tester.widget<Text>(date).style,
    );
    expect(tester.getTopLeft(location).dy, tester.getTopLeft(date).dy);
    expect(tester.getTopLeft(location).dx, tester.getTopRight(date).dx + 8);
    expect(tester.takeException(), isNull);
  });
  testWidgets('absent IP location leaves the date without a placeholder', (
    tester,
  ) async {
    for (final location in <String?>[null, '', ' \n ']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentAuthorHeader(
              comment: CommentEntry(
                id: '1',
                author: 'reader',
                message: 'comment',
                publishedAt: DateTime.now().subtract(
                  const Duration(seconds: 30),
                ),
                ipLocation: location,
              ),
            ),
          ),
        ),
      );
      expect(find.text('刚刚'), findsOneWidget);
      expect(find.textContaining('IP属地'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CommentAuthorHeader),
          matching: find.text('reader'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('absent decoration or serial never invents image metadata', (
    tester,
  ) async {
    const empty = CommentEntry(id: '1', author: 'reader', message: 'comment');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CommentAuthorHeader(comment: empty)),
      ),
    );
    expect(find.byType(CommentAuthorDecoration), findsNothing);
    final decoration = CommentEntry(
      id: '2',
      author: 'reader',
      message: 'comment',
      decorationImageUrl: Uri.https('i0.hdslb.com', '/card.png'),
      decorationName: '装扮名称',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommentAuthorHeader(comment: decoration)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommentAuthorDecoration), findsOneWidget);
    expect(find.text('装扮名称'), findsNothing);
    expect(find.textContaining('NO.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('emote insertion replaces selection and preserves caret', () {
    final value = insertCommentEmote(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 3, extentOffset: 1),
      ),
      '[笑]',
    );
    expect(value.text, 'a[笑]d');
    expect(value.selection.baseOffset, 4);
    expect(
      insertCommentEmote(const TextEditingValue(text: 'draft'), '[笑]').text,
      'draft[笑]',
    );
    final full = TextEditingValue(text: 'a' * 1000);
    expect(insertCommentEmote(full, '[笑]'), full);
  });
  test('like and reply copies preserve rich content', () {
    final c = CommentEntry(
      id: '1',
      author: 'a',
      message: '[笑]',
      ipLocation: 'IP属地：广东',
      level: 6,
      medalName: 'medal',
      medalLevel: 5,
      decorationImageUrl: Uri.https('i0.hdslb.com', '/card.png'),
      decorationName: '装扮名称',
      decorationFanNumber: '0014931',
      decorationFanColor: 0xabcdef,
      pendantUrl: Uri.https('i0.hdslb.com', '/pendant.png'),
      emotes: {'[笑]': Uri.https('i0.hdslb.com', '/e.png')},
      pictures: [Uri.https('i0.hdslb.com', '/p.png')],
    );
    for (final changed in [c.withLike(true), c.withReplies([])]) {
      expect(changed.level, 6);
      expect(changed.ipLocation, 'IP属地：广东');
      expect(changed.medalName, 'medal');
      expect(changed.medalLevel, 5);
      expect(changed.pendantUrl, c.pendantUrl);
      expect(changed.decorationImageUrl, c.decorationImageUrl);
      expect(changed.decorationName, '装扮名称');
      expect(changed.decorationFanNumber, '0014931');
      expect(changed.decorationFanColor, 0xabcdef);
      expect(changed.emotes, c.emotes);
      expect(changed.pictures, c.pictures);
    }
  });
  testWidgets('rich media on narrow screen retains readable fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          originalImageRepositoryProvider.overrideWithValue(_Originals()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: CommentRichContent(
                comment: CommentEntry(
                  id: '1',
                  author: 'a',
                  message: 'before[笑]after',
                  emotes: {'[笑]': Uri.https('i0.hdslb.com', '/e.png')},
                  pictures: [Uri.https('i0.hdslb.com', '/p.png')],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('图片加载失败'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsOneWidget);
    expect(find.text('预览图无法读取，请重试'), findsOneWidget);
    expect(find.byTooltip('适应窗口'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsNothing);
  });
  testWidgets(
    'comment opens selected preview in the shared multi-image viewer',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(24, 16);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        if (data == null) throw StateError('PNG missing');
        return data.buffer.asUint8List();
      });
      if (bytes == null) throw StateError('PNG missing');
      final originals = _Originals(
        OriginalImage(bytes: bytes, width: 24, height: 16),
      );
      final sources = List.generate(
        3,
        (index) => Uri.https('i0.hdslb.com', '/original$index.png'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            originalImageRepositoryProvider.overrideWithValue(originals),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: CommentRichContent(
                comment: CommentEntry(
                  id: '1',
                  author: 'a',
                  message: 'comment',
                  pictures: sources,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(originals.sources, isEmpty);
      expect(
        tester
            .widgetList<AppNetworkImage>(find.byType(AppNetworkImage))
            .map((image) => image.url),
        sources.map((source) => '$source@264w_1280h_0e.webp'),
      );
      await tester.tap(find.byType(InkWell).at(1));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(originals.sources, [
        Uri.parse('${sources[1]}@1280w_1280h_0e.webp'),
      ]);
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(find.text('125%'), findsOneWidget);
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(
        originals.sources,
        [
          sources[1],
          sources[2],
          sources[1],
        ].map((uri) => Uri.parse('$uri@1280w_1280h_0e.webp')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Originals implements OriginalImageRepository {
  _Originals([this.image]);
  final OriginalImage? image;
  final sources = <Uri>[];
  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    sources.add(source);
    final result = image;
    if (result == null) throw StateError('Unreadable image');
    return result;
  }
}
