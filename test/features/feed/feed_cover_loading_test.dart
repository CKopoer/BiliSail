import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:material_ui/material_ui.dart';
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
        var active = 0;
        var maximumActive = 0;
        final requests = <({Uri uri, ImageLoadRequest request})>[];
        final cache = AppImageCache(
          ImageByteCache(
            enabled: enabled,
            directory: () async => throw const FileSystemException('optional'),
            maxPending: 3,
            maxConcurrent: 1,
            loader: (uri, request) {
              calls++;
              requests.add((uri: uri, request: request));
              active++;
              if (active > maximumActive) maximumActive = active;
              final response = Completer<Uint8List>();
              request.onCancel(() {
                if (response.isCompleted) return;
                active--;
                response.completeError(const ImageLoadCancelled());
              });
              unawaited(
                gate.future.then((bytes) {
                  if (response.isCompleted) return;
                  active--;
                  response.complete(bytes);
                }),
              );
              return response.future;
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
        final initialRequest = requests.single.request;
        expect(cache.bytes.hasCapacity, isFalse);

        ScrollPosition position() => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(CustomScrollView),
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
        expect(initialRequest.cancelled, isTrue);
        final savedOffset = position().pixels;
        final departingRequest = requests.last.request;
        await tester.tap(find.text('番剧索引'));
        await tester.pumpAndSettle();
        expect(home.calls.last, '番剧索引:1');
        expect(departingRequest.cancelled, isTrue);
        await nextPage();
        expect(home.calls.last, '番剧索引:2');
        expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
        // Offscreen demand releases the old slot before the shared response
        // gate opens; only the current viewport's transfer may remain active.
        final currentRequests = requests
            .where((entry) => !entry.request.cancelled)
            .toList();
        expect(currentRequests, hasLength(1));
        expect(
          Uri.decodeComponent(currentRequests.single.uri.path),
          startsWith('/番剧索引-'),
        );
        expect(active, 1);
        expect(maximumActive, 1);

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
            final viewport = tester
                .getRect(find.byType(CustomScrollView))
                .inflate(160);
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
