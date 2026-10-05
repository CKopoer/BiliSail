import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_lite/app/theme.dart';
import 'package:bili_lite/core/presentation/app_image_provider.dart';
import 'package:bili_lite/core/storage/image_byte_cache.dart';
import 'package:bili_lite/domain/user.dart';
import 'package:bili_lite/features/live/domain/live_room.dart';
import 'package:bili_lite/features/live/presentation/live_chat_bubble.dart';
import 'package:bili_lite/shared/ui/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _fixtureImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 160, 80),
    Paint()..color = Colors.lightBlue.shade100,
  );
  canvas.drawCircle(const Offset(80, 40), 34, Paint()..color = Colors.amber);
  for (final x in [68.0, 92.0]) {
    canvas.drawCircle(Offset(x, 33), 4, Paint()..color = Colors.black87);
  }
  canvas.drawArc(
    const Rect.fromLTWH(65, 35, 30, 25),
    0,
    3.14,
    false,
    Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 80);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (bytes == null) throw StateError('Fixture image encoding failed');
  return bytes.buffer.asUint8List();
}

void main() {
  testWidgets(
    'inline emotes and stickers decode with text order, profile links and bounded layout',
    (tester) async {
      if (const bool.fromEnvironment('EXPORT_LIVE_CHAT_PREVIEW')) {
        await tester.runAsync(() async {
          final loader = FontLoader('HarmonyOS Sans')
            ..addFont(
              rootBundle.load(
                'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
              ),
            );
          await loader.load();
        });
      }
      final bytes = await tester.runAsync(_fixtureImage);
      if (bytes == null) throw StateError('Fixture bytes missing');
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async =>
              throw const FileSystemException('No disk cache in test'),
          loader: (_, _) async => bytes,
        ),
      );
      final smile = LiveChatImage(
        url: Uri.parse('https://i0.hdslb.com/fixture-smile.png'),
      );
      final sticker = LiveChatImage(
        url: Uri.parse('https://i0.hdslb.com/fixture-sticker.png'),
        width: 160,
        height: 80,
      );
      final opened = <UserId>[];
      const boundary = ValueKey('live-chat-preview');
      await tester.binding.setSurfaceSize(const Size(380, 280));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget frame({double scale = 1, double width = 380}) =>
          AppImageCacheScope(
            cache: cache,
            child: MaterialApp(
              theme: BiliTheme.light(),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    child: RepaintBoundary(
                      key: boundary,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LiveChatBubble(
                              message: LiveChatMessage(
                                userName: '表情观众',
                                userId: const UserId('123'),
                                text: '前文[笑]后文[未知]再来[笑]',
                                emotes: {'[笑]': smile},
                              ),
                              onOpenUser: opened.add,
                            ),
                            LiveChatBubble(
                              message: LiveChatMessage(
                                userName: '贴纸观众',
                                userId: const UserId('456'),
                                text: '[大表情]',
                                sticker: sticker,
                              ),
                              onOpenUser: opened.add,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child ?? const SizedBox(),
              ),
            ),
          );
      await tester.pumpWidget(frame());
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null)) {
          break;
        }
      }
      expect(tester.widgetList<RawImage>(find.byType(RawImage)), hasLength(3));
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null),
        isTrue,
      );
      expect(find.textContaining('前文'), findsOneWidget);
      expect(find.textContaining('后文[未知]再来'), findsOneWidget);
      final images = tester
          .widgetList<AppNetworkImage>(find.byType(AppNetworkImage))
          .toList();
      expect(
        images.where((image) => image.semanticLabel == '[笑]'),
        hasLength(2),
      );
      expect(images.last.width, 80);
      expect(images.last.height, 40);
      await tester.tap(find.text('表情观众'));
      await tester.tap(find.text('贴纸观众'));
      expect(opened, [const UserId('123'), const UserId('456')]);
      expect(tester.takeException(), isNull);

      if (const bool.fromEnvironment('EXPORT_LIVE_CHAT_PREVIEW')) {
        // Let tap feedback finish before capturing the actual Flutter widgets.
        await tester.pumpAndSettle();
        final render = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundary),
        );
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final output = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (output == null) throw StateError('Preview encoding failed');
          final file = File('artifacts/live-chat/live-chat-preview.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(output.buffer.asUint8List());
        });
      }
      await tester.binding.setSurfaceSize(const Size(320, 740));
      await tester.pumpWidget(frame(scale: 2, width: 280));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );

  testWidgets(
    'failed images retain labels and invalid user IDs are not links',
    (tester) async {
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async =>
              throw const FileSystemException('No disk cache in test'),
          loader: (_, _) async =>
              throw const FileSystemException('Missing fixture image'),
        ),
      );
      final missing = LiveChatImage(
        url: Uri.parse('https://i0.hdslb.com/missing.png'),
      );
      final opened = <UserId>[];
      await tester.pumpWidget(
        AppImageCacheScope(
          cache: cache,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  LiveChatBubble(
                    message: LiveChatMessage(
                      userName: '无UID观众',
                      text: '内容[表情]',
                      emotes: {'[表情]': missing},
                    ),
                    onOpenUser: opened.add,
                  ),
                  LiveChatBubble(
                    message: LiveChatMessage(
                      userName: '无效UID观众',
                      userId: const UserId('0'),
                      text: '[贴纸]',
                      sticker: missing,
                    ),
                    onOpenUser: opened.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('[表情]'), findsOneWidget);
      expect(find.text('[贴纸]'), findsOneWidget);
      await tester.tap(find.text('无UID观众'));
      await tester.tap(find.text('无效UID观众'));
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );
}
