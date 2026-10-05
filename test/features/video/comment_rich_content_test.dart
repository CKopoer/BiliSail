import 'dart:ui' as ui;

import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bili_lite/features/image_viewer/domain/original_image.dart';
import 'package:bili_lite/shared/ui/app_network_image.dart';
import 'package:bili_lite/shared/ui/bili_badges.dart';
import 'package:bili_lite/shared/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bili_lite/features/video/presentation/comment_rich_content.dart';
import 'package:bili_lite/features/video/domain/video_comments_repository.dart';

void main() {
  for (final width in [180.0, 320.0]) {
    testWidgets('decoration image and fan serial fit $width pixel header', (
      tester,
    ) async {
      final comment = CommentEntry(
        id: '1',
        author: '很长的用户名称用于测试换行',
        message: 'comment',
        level: 6,
        publishedAt: DateTime(2026, 10, 6),
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
      expect(find.text('装扮名称'), findsNothing);
      final serial = tester.widget<Text>(find.text('NO.\n0014931'));
      expect(serial.style?.color, const Color(0xffabcdef));
      final image = tester.widget<AppNetworkImage>(
        find.byType(AppNetworkImage),
      );
      expect(image.url, 'https://i0.hdslb.com/card.png@336w_120h_0e.webp');
      expect(image.alignment, Alignment.centerRight);
      final decorationRect = tester.getRect(
        find.byType(CommentAuthorDecoration),
      );
      expect(decorationRect.right, width);
      if (width >= 220) {
        expect(
          decorationRect.left,
          greaterThan(tester.getRect(find.byType(BiliLevelBadge)).right),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
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
      level: 6,
      medalName: 'medal',
      medalLevel: 5,
      decorationImageUrl: Uri.https('i0.hdslb.com', '/card.png'),
      decorationName: '装扮名称',
      decorationFanNumber: '0014931',
      decorationFanColor: 0xabcdef,
      emotes: {'[笑]': Uri.https('i0.hdslb.com', '/e.png')},
      pictures: [Uri.https('i0.hdslb.com', '/p.png')],
    );
    for (final changed in [c.withLike(true), c.withReplies([])]) {
      expect(changed.level, 6);
      expect(changed.medalName, 'medal');
      expect(changed.medalLevel, 5);
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
    expect(find.text('原图无法读取，请重试'), findsOneWidget);
    expect(find.byTooltip('适应窗口'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsNothing);
  });
  testWidgets(
    'comment opens selected original in the shared multi-image viewer',
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
          child: MaterialApp(
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
      expect(originals.sources, [sources[1]]);
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(find.text('125%'), findsOneWidget);
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(originals.sources, [sources[1], sources[2], sources[1]]);
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
