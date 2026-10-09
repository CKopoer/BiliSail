import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/dynamic_post.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (enabled, width, source, target) in [
    for (final enabled in [true, false])
      for (final width in [375.0, 1000.0])
        for (final (source, target) in [
          (HomeChannel.recommended, HomeChannel.popular),
          (HomeChannel.dynamic, HomeChannel.videoDynamic),
          (HomeChannel.bangumi, HomeChannel.guochuang),
          (HomeChannel.live, HomeChannel.cinema),
        ])
          (enabled, width, source, target),
  ]) {
    testWidgets(
      '$source / $target covers stay painted throughout repeated swipes at width=$width with caching=$enabled',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
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
        final home = _Home();
        final channel = ValueNotifier(source);
        addTearDown(channel.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              feedRepositoryProvider.overrideWithValue(repository),
              homeRepositoryProvider.overrideWithValue(home),
            ],
            child: AppImageCacheScope(
              cache: cache,
              child: MaterialApp(
                theme: ThemeData(platform: TargetPlatform.android),
                home: Scaffold(
                  body: ValueListenableBuilder(
                    valueListenable: channel,
                    builder: (_, selected, _) => FeedScreen(
                      channel: selected,
                      isSignedIn: true,
                      onChannelChanged: (value) => channel.value = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _loaded(tester);
        channel.value = target;
        await tester.pumpAndSettle();
        await _loaded(tester);
        channel.value = source;
        await tester.pumpAndSettle();
        await _loaded(tester);
        final initialDownloads = downloads;
        final surface = find.byKey(const ValueKey('home-channel-swipe'));

        final gesture = await tester.startGesture(tester.getCenter(surface));
        await gesture.moveBy(Offset(-width * .75, 0));
        await tester.pump();
        expect(channel.value, source);
        _expectPaintedCovers(tester);
        await gesture.up();
        await tester.pump();
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          _expectPaintedCovers(tester);
        }
        await tester.pumpAndSettle();
        expect(channel.value, target);
        _expectPaintedCovers(tester);

        final reverse = await tester.startGesture(tester.getCenter(surface));
        await reverse.moveBy(Offset(width * .75, 0));
        await tester.pump();
        _expectPaintedCovers(tester);
        await reverse.up();
        await tester.pump();
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          _expectPaintedCovers(tester);
        }
        await tester.pumpAndSettle();
        expect(channel.value, source);
        _expectPaintedCovers(tester);

        final back = await tester.startGesture(tester.getCenter(surface));
        await back.moveBy(Offset(-width * .75, 0));
        await tester.pump();
        _expectPaintedCovers(tester);
        await back.moveBy(Offset(width * .5, 0));
        await tester.pump();
        _expectPaintedCovers(tester);
        await back.cancel();
        await tester.pumpAndSettle();
        expect(channel.value, source);
        _expectPaintedCovers(tester);
        expect(downloads, initialDownloads);
        expect(source.hasVideoFeed ? repository.calls : home.calls, [
          source.name,
          if (source == HomeChannel.live) source.name,
          target.name,
        ]);
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
  for (final element in find.byType(AppNetworkImage).evaluate()) {
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
    expect(
      images,
      findsOneWidget,
      reason:
          'Visible cover lost its image: ${tester.widget<AppNetworkImage>(cover).url} at ${tester.getRect(cover)}',
    );
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

final class _Home implements HomeRepository {
  final calls = <String>[];

  @override
  String get accountScope => 'user:1';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add(query.channel.name);
    final kind = switch (query.channel) {
      HomeChannel.dynamic => HomeEntryKind.dynamic,
      HomeChannel.videoDynamic => HomeEntryKind.video,
      HomeChannel.live => HomeEntryKind.live,
      _ => HomeEntryKind.season,
    };
    return HomePage([
      for (var i = 0; i < 6; i++)
        HomeEntry(
          id: '${query.channel.name}-$i',
          title: '${query.channel.name}-$i',
          kind: kind,
          bvid: 'BV000000000$i',
          coverUrl: Uri.parse(
            'https://i0.hdslb.com/${query.channel.name}-$i.jpg',
          ),
          dynamicPost: kind == HomeEntryKind.dynamic
              ? DynamicPost(
                  id: '$i',
                  authorName: 'author',
                  video: VideoSummary(
                    id: VideoId('BV000000000$i'),
                    title: 'dynamic-$i',
                    author: 'author',
                    coverUrl: 'https://i0.hdslb.com/dynamic-$i.jpg',
                    duration: const Duration(minutes: 1),
                  ),
                )
              : null,
        ),
    ], hasMore: false);
  }
}
