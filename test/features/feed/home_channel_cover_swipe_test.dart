import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets(
      'visited video covers stay painted throughout a channel swipe with caching=$enabled',
      (tester) async {
        tester.view.physicalSize = const Size(375, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bytes = await tester.runAsync(_png);
        if (bytes == null) throw StateError('Missing PNG');
        var downloads = 0;
        final cache = AppImageCache(
          ImageByteCache(
            enabled: enabled,
            directory: () async => throw const FileSystemException('optional'),
            loader: (_, _) async {
              downloads++;
              return bytes;
            },
          ),
        );
        final repository = _Feed();
        final channel = ValueNotifier(HomeChannel.recommended);
        addTearDown(channel.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [feedRepositoryProvider.overrideWithValue(repository)],
            child: AppImageCacheScope(
              cache: cache,
              child: MaterialApp(
                theme: ThemeData(platform: TargetPlatform.android),
                home: Scaffold(
                  body: ValueListenableBuilder(
                    valueListenable: channel,
                    builder: (_, selected, _) => FeedScreen(
                      channel: selected,
                      onChannelChanged: (value) => channel.value = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _loaded(tester);
        channel.value = HomeChannel.popular;
        await tester.pumpAndSettle();
        await _loaded(tester);
        channel.value = HomeChannel.recommended;
        await tester.pumpAndSettle();
        await _loaded(tester);
        final initialDownloads = downloads;
        final surface = find.byKey(const ValueKey('home-channel-swipe'));

        final gesture = await tester.startGesture(tester.getCenter(surface));
        await gesture.moveBy(const Offset(-220, 0));
        await tester.pump();
        expect(channel.value, HomeChannel.recommended);
        _expectPaintedCovers(tester);
        await gesture.up();
        await tester.pump();
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          _expectPaintedCovers(tester);
        }
        await tester.pumpAndSettle();
        expect(channel.value, HomeChannel.popular);
        _expectPaintedCovers(tester);

        final back = await tester.startGesture(tester.getCenter(surface));
        await back.moveBy(const Offset(80, 0));
        await tester.pump();
        _expectPaintedCovers(tester);
        await back.cancel();
        await tester.pumpAndSettle();
        expect(channel.value, HomeChannel.popular);
        _expectPaintedCovers(tester);
        expect(downloads, initialDownloads);
        expect(repository.calls, ['recommended', 'popular']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await cache.close();
      },
    );
  }
}

Iterable<Finder> _visibleCovers(WidgetTester tester) sync* {
  final viewport = tester.getRect(
    find.byKey(const ValueKey('home-channel-swipe')),
  );
  for (final element in find.byType(AppCoverImage).evaluate()) {
    final finder = find.byElementPredicate(
      (value) => identical(value, element),
    );
    if (tester.getRect(finder).overlaps(viewport)) yield finder;
  }
}

void _expectPaintedCovers(WidgetTester tester) {
  final covers = _visibleCovers(tester).toList();
  expect(covers, isNotEmpty);
  for (final cover in covers) {
    final images = find.descendant(of: cover, matching: find.byType(RawImage));
    expect(images, findsOneWidget, reason: 'Visible cover lost its image');
    expect(tester.widget<RawImage>(images).image, isNotNull);
    expect(
      find.descendant(of: cover, matching: find.byIcon(Icons.image_outlined)),
      findsNothing,
    );
  }
}

Future<void> _loaded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final covers = _visibleCovers(tester).toList();
    if (covers.isNotEmpty &&
        covers.every((cover) {
          final images = tester.widgetList<RawImage>(
            find.descendant(of: cover, matching: find.byType(RawImage)),
          );
          return images.length == 1 && images.single.image != null;
        })) {
      return;
    }
  }
  fail('Visible covers did not load');
}

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

final class _Feed implements FeedRepository {
  final calls = <String>[];

  PageResult<VideoSummary> _page(String channel) {
    calls.add(channel);
    return PageResult(
      items: [
        for (var i = 0; i < 6; i++)
          VideoSummary(
            id: VideoId('BV${channel.substring(0, 3)}000000$i'),
            title: '$channel-$i',
            author: 'author',
            duration: const Duration(minutes: 1),
            coverUrl: 'https://i0.hdslb.com/$channel-$i.jpg',
          ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => _page('recommended');

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => _page('popular');
}
