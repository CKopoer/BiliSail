// Offline Windows Profile probe; never used by normal application builds.
// flutter run -d windows --profile -t tool/validation/card_scroll_profile.dart
//   --dart-define=SCROLL_LABEL=baseline
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const _label = String.fromEnvironment('SCROLL_LABEL', defaultValue: 'current');
final _content = ValueNotifier<Widget>(const SizedBox());
final _frames = <ui.FrameTiming>[];
bool _collecting = false;

void _walk(Element element, void Function(Element) visit) {
  visit(element);
  element.visitChildren((child) => _walk(child, visit));
}

ScrollPosition _position() {
  ScrollPosition? position;
  _walk(WidgetsBinding.instance.rootElement!, (element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final candidate = (element.state as ScrollableState).position;
      if (candidate.axis == Axis.vertical && candidate.maxScrollExtent > 0) {
        position = candidate;
      }
    }
  });
  return position!;
}

Map<String, int> _mounted() {
  var cards = 0;
  var images = 0;
  var elements = 0;
  final columns = <int>{};
  _walk(WidgetsBinding.instance.rootElement!, (element) {
    elements++;
    if (element.widget is VideoCard) {
      cards++;
      final box = element.renderObject;
      if (box is RenderBox && box.hasSize) {
        columns.add(box.localToGlobal(Offset.zero).dx.round());
      }
    }
    if (element.widget is AppNetworkImage) images++;
  });
  return {
    'cards': cards,
    'columns': columns.length,
    'images': images,
    'elements': elements,
  };
}

double _percentile(List<int> sorted, double p) =>
    sorted[(p * (sorted.length - 1)).round()] / 1000;

Map<String, Object> _summary() {
  final build = _frames.map((f) => f.buildDuration.inMicroseconds).toList()
    ..sort();
  final raster = _frames.map((f) => f.rasterDuration.inMicroseconds).toList()
    ..sort();
  return {
    'frames': _frames.length,
    'uiP50Ms': _percentile(build, .5),
    'uiP95Ms': _percentile(build, .95),
    'uiP99Ms': _percentile(build, .99),
    'uiMaxMs': _percentile(build, 1),
    'uiTotalMs': build.fold(0, (a, b) => a + b) / 1000,
    'rasterP50Ms': _percentile(raster, .5),
    'rasterP95Ms': _percentile(raster, .95),
    'rasterP99Ms': _percentile(raster, .99),
    'rasterMaxMs': _percentile(raster, 1),
    'rasterTotalMs': raster.fold(0, (a, b) => a + b) / 1000,
    'over8_33ms': _frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 8333 ||
              f.rasterDuration.inMicroseconds > 8333,
        )
        .length,
    'over16_67ms': _frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 16667 ||
              f.rasterDuration.inMicroseconds > 16667,
        )
        .length,
  };
}

Future<void> _saveCpu(int start, int end, String name) async {
  final info = await developer.Service.getInfo();
  final base = info.serverUri;
  if (base == null) return;
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      base
          .resolve('getCpuSamples')
          .replace(
            queryParameters: {
              'isolateId': developer.Service.getIsolateId(Isolate.current)!,
              'timeOriginMicros': '$start',
              'timeExtentMicros': '${end - start}',
            },
          ),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    await File('artifacts/card-scroll-2026-10-31/$_label-$name-cpu.json')
        .writeAsString(body);
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('BiliSail 离线滚动性能诊断');
  await windowManager.setMaximumSize(const Size(2400, 1600));
  await windowManager.show();
  runApp(
    MaterialApp(
      theme: BiliTheme.light(),
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: _content,
          builder: (_, child, _) => child,
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addTimingsCallback((batch) {
    if (_collecting) _frames.addAll(batch);
  });
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 640, 360),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(640, 360), [
        Colors.blue,
        Colors.amber,
      ]),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 360);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final png = data!.buffer.asUint8List();
  picture.dispose();
  image.dispose();
  await Directory('artifacts/card-scroll-2026-10-31').create(recursive: true);
  final reports = <Map<String, Object?>>[];
  const gate = String.fromEnvironment('SCROLL_GATE');
  if (gate.isNotEmpty) {
    print('SCROLL WAITING $gate');
    while (!await File(gate).exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  for (final width in [430.0, 1800.0]) {
    await windowManager.setSize(Size(width, 900));
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('memory only'),
        loader: (_, _) async => png,
      ),
    );
    _content.value = ProviderScope(
      key: ValueKey(width),
      overrides: [feedRepositoryProvider.overrideWithValue(CardScrollFeed())],
      child: AppImageCacheScope(
        cache: cache,
        child: ScrollHeaderRegion(
          enabled: width < 600,
          child: ScrollHeaderLayout(
            enabled: width < 600,
            header: SizedBox(height: width < 600 ? 96 : 0),
            child: const FeedScreen(),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final position = _position();
    _walk(WidgetsBinding.instance.rootElement!, (element) {
      if (element is StatefulElement &&
          element.state is NestedScrollViewState) {
        final outer = (element.state as NestedScrollViewState).outerController;
        outer.jumpTo(outer.position.maxScrollExtent);
      }
    });
    if (const bool.fromEnvironment('SCROLL_SMOKE')) {
      print('SCROLL SMOKE READY');
      await Completer<void>().future;
    }
    // Jumping leaves the scroll activity idle so real decoded covers, rather
    // than fast-scroll placeholders, are warmed before the timed traversals.
    for (var offset = 0.0; offset <= 12000; offset += 500) {
      position.jumpTo(offset);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    position.jumpTo(0);
    // Cross many sliver cache boundaries, then revisit the same cards.
    for (var warm = 0; warm < 2; warm++) {
      await position.animateTo(
        12000,
        duration: const Duration(seconds: 2),
        curve: Curves.linear,
      );
      await position.animateTo(
        0,
        duration: const Duration(seconds: 2),
        curve: Curves.linear,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (var round = 0; round < 3; round++) {
      final startMounted = _mounted();
      _frames.clear();
      _collecting = true;
      final start = developer.Timeline.now;
      await position.animateTo(
        12000,
        duration: const Duration(seconds: 4),
        curve: Curves.linear,
      );
      final endMounted = _mounted();
      await position.animateTo(
        0,
        duration: const Duration(seconds: 4),
        curve: Curves.linear,
      );
      final end = developer.Timeline.now;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _collecting = false;
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      reports.add({
        'label': _label,
        'round': round,
        'width': width,
        'viewportWidth': view.physicalSize.width / view.devicePixelRatio,
        'viewportHeight': view.physicalSize.height / view.devicePixelRatio,
        'dpr': view.devicePixelRatio,
        'startMounted': startMounted,
        'deepMounted': endMounted,
        'endMounted': _mounted(),
        'decodedCount': cache.decoded.currentSize,
        'decodedBytes': cache.decoded.currentSizeBytes,
        ..._summary(),
      });
      print('SCROLL ${jsonEncode(reports.last)}');
      await File('artifacts/card-scroll-2026-10-31/$_label.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
      if (round == 2 && const bool.fromEnvironment('SCROLL_CPU')) {
        await _saveCpu(start, end, '${width.toInt()}');
      }
    }
    _content.value = const SizedBox();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await cache.close();
  }
  print('SCROLL DONE');
  exit(0);
}

class CardScrollFeed implements FeedRepository {
  final items = List.generate(
    500,
    (i) => VideoSummary(
      id: VideoId('BV1abc${i.toString().padLeft(6, '0')}'),
      title: '推荐视频 $i：反复向下向上滚动时的卡片生命周期与性能分析',
      author: '测试作者 $i',
      coverUrl: 'https://i0.hdslb.com/card-scroll-$i.png',
      duration: Duration(minutes: 3 + i % 20, seconds: i % 60),
      playCount: 120000 + i * 10,
      danmakuCount: 1000 + i,
      recommendationReason: '热门推荐',
    ),
  );
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => PageResult(items: items, hasMore: false);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);
}
