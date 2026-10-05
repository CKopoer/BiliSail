import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_lite/core/presentation/app_image_provider.dart';
import 'package:bili_lite/core/storage/image_byte_cache.dart';
import 'package:bili_lite/domain/page_result.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/features/feed/application/feed_controller.dart';
import 'package:bili_lite/features/feed/application/home_controller.dart';
import 'package:bili_lite/features/feed/domain/feed_repository.dart';
import 'package:bili_lite/features/feed/domain/home_channel.dart';
import 'package:bili_lite/features/feed/domain/home_repository.dart';
import 'package:bili_lite/features/feed/presentation/feed_screen.dart';
import 'package:bili_lite/shared/ui/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 24, 24), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 24);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('Missing PNG');
  return data.buffer.asUint8List();
}

void main() {
  for (final enabled in [true, false]) {
    testWidgets(
      'subtab switch and pagination recover visible covers with caching=$enabled',
      (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bytes = await tester.runAsync(_png);
        if (bytes == null) throw StateError('Missing PNG');
        final gate = Completer<Uint8List>();
        var calls = 0;
        final cache = AppImageCache(
          ImageByteCache(
            enabled: enabled,
            directory: () async => throw const FileSystemException('optional'),
            maxPending: 3,
            maxConcurrent: 1,
            loader: (_, _) {
              calls++;
              return gate.future;
            },
          ),
        );
        final home = _Home();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeRepositoryProvider.overrideWithValue(home),
              feedRepositoryProvider.overrideWithValue(_Feed()),
            ],
            child: AppImageCacheScope(
              cache: cache,
              child: const MaterialApp(
                home: Scaffold(body: FeedScreen(channel: HomeChannel.bangumi)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(home.calls, ['推荐:1']);
        expect(calls, 1);
        expect(cache.bytes.hasCapacity, isFalse);

        ScrollPosition position() => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        Future<void> nextPage() async {
          position().jumpTo(position().maxScrollExtent - 100);
          await tester.pumpAndSettle();
        }

        await nextPage();
        expect(home.calls, ['推荐:1', '推荐:2']);
        final savedOffset = position().pixels;
        await tester.tap(find.text('番剧索引'));
        await tester.pumpAndSettle();
        expect(home.calls.last, '番剧索引:1');
        await nextPage();
        expect(home.calls.last, '番剧索引:2');
        expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
        expect(calls, 1);

        gate.complete(bytes);
        Future<void> loaded() async {
          for (var attempt = 0; attempt < 120; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            final images = tester
                .widgetList<RawImage>(find.byType(RawImage))
                .toList();
            final viewport = tester.getRect(find.byType(ListView)).inflate(160);
            final visibleCount = find
                .byType(AppNetworkImage)
                .evaluate()
                .where(
                  (element) => tester
                      .getRect(find.byWidget(element.widget))
                      .overlaps(viewport),
                )
                .length;
            if (images.length == visibleCount &&
                images.isNotEmpty &&
                images.every((image) => image.image != null)) {
              return;
            }
          }
          fail('Visible covers did not recover');
        }

        await loaded();
        expect(calls, lessThan(40));
        expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
        await tester.tap(find.text('推荐'));
        await tester.pumpAndSettle();
        await loaded();
        expect(position().pixels, closeTo(savedOffset, 1));
        expect(home.calls, ['推荐:1', '推荐:2', '番剧索引:1', '番剧索引:2']);
        expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await cache.close();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _Home implements HomeRepository {
  final calls = <String>[];
  @override
  String get accountScope => 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add('${query.section}:$page');
    return HomePage([
      for (var i = 0; i < 20; i++)
        HomeEntry(
          id: '${query.section}-$page-$i',
          title: '${query.section}-$page-$i',
          kind: HomeEntryKind.season,
          coverUrl: Uri.parse(
            'https://i0.hdslb.com/${query.section}-$page-$i.jpg',
          ),
        ),
    ], hasMore: page < 2);
  }
}

final class _Feed implements FeedRepository {
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
}
