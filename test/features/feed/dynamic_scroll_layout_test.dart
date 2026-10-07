import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final section in ['全部', '图文']) {
    for (final (kind, ratio, fails, forwarded) in [
      ('missing dimensions', null, false, false),
      ('landscape', 1.5, false, false),
      ('portrait', 2 / 3, false, false),
      ('long picture', .1, false, false),
      ('failed image', 1.5, true, false),
      ('forwarded image', 1.5, false, true),
    ]) {
      testWidgets(
        '$section $kind keeps its layout across loading and scrolling',
        (tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final bytes = await tester.runAsync(_png);
          if (bytes == null) throw StateError('Missing PNG');
          final loaded = Completer<Uint8List>();
          final cache = AppImageCache(
            ImageByteCache(
              directory: () async =>
                  throw const FileSystemException('optional'),
              loader: (_, _) => loaded.future,
            ),
          );
          final source = Uri.parse(
            'https://i0.hdslb.com/bfs/new_dyn/probe.png',
          );
          final picture = DynamicPost(
            id: forwarded ? 'original' : '0',
            authorName: 'image post',
            imageUrls: [source],
            imageAspectRatios: ratio == null ? {} : {source: ratio},
          );
          final posts = [
            forwarded ? DynamicPost(id: '0', original: picture) : picture,
            for (var i = 1; i < 40; i++)
              DynamicPost(
                id: '$i',
                authorName: 'post $i',
                text: 'Following card $i',
              ),
          ];
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                homeRepositoryProvider.overrideWithValue(_Repository(posts)),
              ],
              child: AppImageCacheScope(
                cache: cache,
                child: MaterialApp(
                  scrollBehavior: const SmoothScrollBehavior(),
                  home: Scaffold(
                    body: HomeContent(
                      channel: HomeChannel.dynamic,
                      section: section,
                      isSignedIn: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final position = tester
              .state<ScrollableState>(
                find.descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                ),
              )
              .position;
          Finder card(String id) => find.byWidgetPredicate(
            (widget) =>
                widget is InteractiveDynamicPostCard && widget.post.id == id,
          );
          double anchor() => tester.getTopLeft(card('1')).dy + position.pixels;
          final initialHeight = tester.getSize(card('0')).height;
          final initialAnchor = anchor();
          final slot = tester.getSize(find.byType(AppNetworkImage));
          expect(slot.width, lessThanOrEqualTo(320));
          expect(slot.height, lessThanOrEqualTo(360));
          expect(slot.width / slot.height, closeTo(ratio ?? 1, .001));
          if (fails) {
            loaded.completeError(const ImageLoadCancelled());
          } else {
            loaded.complete(bytes);
          }
          await _waitForImage(tester, fails: fails);
          expect(tester.getSize(card('0')).height, initialHeight);
          expect(anchor(), initialAnchor);

          // The image leaves its 160px prefetch margin before the card leaves the
          // sliver cache. Neither that transition nor later remounts may change it.
          position.jumpTo(initialHeight + 190);
          for (var i = 0; i < 4; i++) {
            await tester.pump();
            expect(anchor(), closeTo(initialAnchor, .01));
          }
          position.jumpTo(2500);
          await tester.pumpAndSettle();
          expect(card('0'), findsNothing);
          expect(
            find.byType(InteractiveDynamicPostCard).evaluate().length,
            lessThan(15),
          );
          position.jumpTo(80);
          for (var i = 0; i < 4; i++) {
            await tester.pump();
            expect(tester.getSize(card('0')).height, initialHeight);
            expect(anchor(), closeTo(initialAnchor, .01));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await cache.close();
        },
      );
    }
  }
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 160);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('PNG encoding failed');
  return data.buffer.asUint8List();
}

Future<void> _waitForImage(WidgetTester tester, {required bool fails}) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (fails &&
        find.byIcon(Icons.image_not_supported_outlined).evaluate().isNotEmpty) {
      return;
    }
    if (tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null)) {
      return;
    }
  }
  fail('Image did not decode');
}

final class _Repository implements HomeRepository {
  _Repository(this.posts);
  final List<DynamicPost> posts;
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => HomePage([
    for (final post in posts)
      HomeEntry(
        id: post.id,
        title: '',
        kind: HomeEntryKind.dynamic,
        dynamicPost: post,
      ),
  ], hasMore: false);
}
