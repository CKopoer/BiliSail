import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/shared/ui/dynamic_post_card.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets(
    'large original uses thumbnail until clicking then downloads original',
    (tester) async {
      final thumbnail = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(24, 16);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        if (data == null) throw StateError('Missing PNG');
        return data.buffer.asUint8List();
      });
      if (thumbnail == null) throw StateError('Missing thumbnail');
      final source = Uri.parse('https://i0.hdslb.com/bfs/new_dyn/large.png');
      final downloaded = <Uri>[];
      final originals = _Originals(thumbnail);
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (uri, limits) async {
            downloaded.add(uri);
            // Before the fix the card requests the original, which the existing
            // transport/cache boundary rejects before Flutter can decode it.
            return uri == source ? Uint8List(limits.maxBytes + 1) : thumbnail;
          },
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            originalImageRepositoryProvider.overrideWithValue(originals),
          ],
          child: AppImageCacheScope(
            cache: cache,
            child: MaterialApp(
              home: Scaffold(
                body: DynamicPostCard(
                  post: DynamicPost(id: 'large-picture', imageUrls: [source]),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> waitForImages() async {
        for (var attempt = 0; attempt < 30; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          final images = tester.widgetList<RawImage>(find.byType(RawImage));
          if (images.isNotEmpty &&
              images.every((image) => image.image != null)) {
            return;
          }
        }
        fail('Image did not decode');
      }

      await waitForImages();
      expect(downloaded.single.path, endsWith('@960w_1280h_0e.webp'));
      expect(cache.bytes.maxImageBytes, 4 * 1024 * 1024);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      await waitForImages();
      expect(downloaded, hasLength(1));
      expect(downloaded, isNot(contains(source)));
      expect(originals.sources, [source]);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );

  testWidgets('short Chinese body wraps and keeps trailing emoji visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynamicPostCard(
            post: DynamicPost(
              id: 'wrapped',
              title: '图文标题',
              spans: [
                DynamicTextSpan(text: List.filled(80, '字').join()),
                DynamicTextSpan(
                  kind: DynamicTextKind.emoji,
                  text: '[表情]',
                  imageUrl: Uri.parse('https://example.test/emoji.png'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final body = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().startsWith('字'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(body);
    expect(paragraph.size.height, greaterThan(50));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester.getTopLeft(find.text('图文标题')).dy,
      lessThan(tester.getTopLeft(body).dy),
    );
    expect(tester.takeException(), isNull);
  });
  for (final count in [4, 9]) {
    testWidgets('$count pictures retain two or three columns on desktop', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DynamicPostCard(
              post: DynamicPost(
                id: 'grid',
                imageUrls: List.generate(
                  count,
                  (i) => Uri.parse('https://example.test/$i.png'),
                ),
              ),
            ),
          ),
        ),
      );
      final columns = count == 4 ? 2 : 3;
      final first = tester.getRect(find.byType(AppNetworkImage).first);
      final lastInRow = tester.getRect(
        find.byType(AppNetworkImage).at(columns - 1),
      );
      final nextRow = tester.getRect(find.byType(AppNetworkImage).at(columns));
      expect(lastInRow.top, first.top);
      expect(nextRow.left, first.left);
      expect(nextRow.top, greaterThan(first.bottom));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('narrow image grid previews open and close within window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          originalImageRepositoryProvider.overrideWithValue(_FailedOriginals()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DynamicPostCard(
              post: DynamicPost(
                id: 'pictures',
                imageUrls: List.generate(
                  4,
                  (i) => Uri.parse('https://example.test/$i.png'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final first = tester.getRect(find.byType(AppNetworkImage).first);
    expect(first.width, 147);
    await tester.tap(
      find
          .ancestor(
            of: find.byType(AppNetworkImage).first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.width, lessThanOrEqualTo(375));
    expect(find.byTooltip('关闭图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(dialog.topLeft + const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  Future<void> show(
    WidgetTester tester,
    DynamicPost post, {
    double scale = 1,
    ValueChanged<VideoSummary>? onVideo,
    ValueChanged<Uri>? onLink,
  }) async {
    await tester.binding.setSurfaceSize(const Size(375, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: DynamicPostCard(
                post: post,
                onOpenVideo: onVideo,
                onOpenLink: onLink,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mixed text and sized emoji preserve fallback tokens', (
    tester,
  ) async {
    await show(
      tester,
      DynamicPost(
        id: '1',
        spans: [
          const DynamicTextSpan(text: '文字'),
          DynamicTextSpan(
            kind: DynamicTextKind.emoji,
            text: '[小表情]',
            imageUrl: Uri.parse('https://example.test/a.gif'),
          ),
          DynamicTextSpan(
            kind: DynamicTextKind.emoji,
            text: '[表情包]',
            imageUrl: Uri.parse('http://example.test/b.gif'),
            emojiSize: 2,
          ),
          const DynamicTextSpan(text: '结尾'),
        ],
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.map((image) => image.width), [24, 48]);
    expect(
      (images.first.image as ResizeImage).imageProvider,
      isA<NetworkImage>(),
    );
    final fallback = images.last.errorBuilder!(
      tester.element(find.byType(Image).last),
      Exception('failed'),
      null,
    );
    expect((fallback as Text).data, '[表情包]');
    final rich = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((text) => text.textSpan != null);
    expect(rich.textSpan!.toPlainText(), contains('文字'));
    expect(rich.textSpan!.toPlainText(), contains('结尾'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long mention wraps and short rich content is never collapsed', (
    tester,
  ) async {
    final id = UserId.tryParse('42');
    UserId? opened;
    await tester.binding.setSurfaceSize(const Size(375, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DynamicPostCard(
              post: DynamicPost(
                id: 'mention',
                spans: [
                  DynamicTextSpan(
                    kind: DynamicTextKind.mention,
                    text: '@${List.filled(80, '名字').join()}',
                    userId: id,
                  ),
                ],
              ),
              onOpenUser: (value) => opened = value,
            ),
          ),
        ),
      ),
    );
    final rich = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((text) => text.textSpan != null);
    expect(rich.maxLines, isNull);
    final span = (rich.textSpan as TextSpan).children!.single as TextSpan;
    expect(span.recognizer, isNotNull);
    (span.recognizer as TapGestureRecognizer).onTap!();
    expect(opened, id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forwarded nine images and video have correct navigation at large scale',
    (tester) async {
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title: '视频标题',
        coverUrl: '',
        author: 'UP',
        duration: Duration(seconds: 90),
      );
      VideoSummary? opened;
      final links = <Uri>[];
      await show(
        tester,
        DynamicPost(
          id: 'outer',
          authorName: '转发者',
          text: '转发正文',
          original: DynamicPost(
            id: 'original',
            authorName: '原作者',
            video: video,
            imageUrls: List.generate(
              9,
              (i) => Uri.parse('https://example.test/$i.png'),
            ),
          ),
        ),
        scale: 2,
        onVideo: (value) => opened = value,
        onLink: links.add,
      );
      expect(find.byType(Image), findsNWidgets(9));
      await tester.tap(find.text('视频标题'));
      expect(opened, video);
      await tester.tap(find.byTooltip('在浏览器打开原动态'));
      expect(links.single.path, '/original');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long content can expand and collapse without account actions', (
    tester,
  ) async {
    await show(
      tester,
      DynamicPost(
        id: '1',
        text: List.filled(400, '文字').join(),
        repostCount: 12,
        commentCount: 34,
        likeCount: 56,
      ),
    );
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Originals implements OriginalImageRepository {
  _Originals(this.bytes);
  final Uint8List bytes;
  final sources = <Uri>[];
  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    sources.add(source);
    return OriginalImage(bytes: bytes, width: 24, height: 16);
  }
}

class _FailedOriginals implements OriginalImageRepository {
  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async => throw const FormatException('test unavailable');
}
