// Offline probe: flutter run -d windows --profile
//   -t tool/validation/scroll_to_top_profile.dart
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/text_measurement_cache.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

final _content = ValueNotifier<Widget>(const SizedBox());
final _frames = <ui.FrameTiming>[];
bool _collecting = false;
int _startMicros = 0;
int _endMicros = 0x7fffffffffffffff;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('BiliSail 离线回顶性能诊断');
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
    if (_collecting) {
      _frames.addAll(
        batch.where((frame) {
          final start = frame.timestampInMicroseconds(ui.FramePhase.buildStart);
          return start >= _startMicros && start <= _endMicros;
        }),
      );
    }
  });
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 640, 360), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final cover = await picture.toImage(640, 360);
  final png = (await cover.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  picture.dispose();
  cover.dispose();
  final reports = <Map<String, Object?>>[];
  await Directory('artifacts/scroll-to-top').create(recursive: true);
  for (final width in [430.0, 1800.0]) {
    await windowManager.setSize(Size(width, 900));
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('memory only'),
        loader: (_, _) async => png,
      ),
    );
    // Alternate within the same process, keeping card appearance, images,
    // theme, fonts, viewport and the original 250ms animation identical.
    final modes = const bool.fromEnvironment('TOP_SMOKE')
        ? [true]
        : [false, true, true, false];
    for (final optimized in modes) {
      var builds = 0;
      late ScrollController controller;
      final videos = List.generate(
        2000,
        (index) => VideoSummary(
          id: VideoId('BV1abc${index.toString().padLeft(6, '0')}'),
          title: '推荐视频 $index：长列表回到顶部的布局与卡片生命周期',
          author: '测试作者 $index',
          coverUrl: 'https://i0.hdslb.com/top-probe.png',
          duration: const Duration(minutes: 12, seconds: 34),
          playCount: 123456,
          danmakuCount: 2345,
        ),
      );
      Widget card(BuildContext context, int index) {
        builds++;
        return VideoCard(video: videos[index], onTap: () {});
      }

      final grid = optimized
          ? SliverResponsiveCardGrid(
              itemCount: videos.length,
              itemBuilder: card,
            )
          : _ReferenceGrid(itemCount: videos.length, itemBuilder: card);
      _content.value = AppImageCacheScope(
        key: UniqueKey(),
        cache: cache,
        child: ScrollHeaderLayout(
          enabled: width < 600,
          header: SizedBox(height: width < 600 ? 96 : 0),
          child: PagedScrollViewport(
            active: true,
            canLoadMore: false,
            contentVersion: 1,
            onLoadMore: () async {},
            onRefresh: () async {},
            builder: (value) {
              controller = value;
              return CustomScrollView(controller: value, slivers: [grid]);
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (const bool.fromEnvironment('TOP_SMOKE')) {
        print('TOP SMOKE READY');
        await Completer<void>().future;
      }
      // Idle jumps warm decoded covers at every region used by the animation.
      for (var offset = 0.0; offset <= 40000; offset += 700) {
        controller.position.jumpTo(offset);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      for (var round = 0; round < 4; round++) {
        controller.position.jumpTo(40000);
        await Future<void>.delayed(const Duration(milliseconds: 180));
        builds = 0;
        _frames.clear();
        _startMicros = developer.Timeline.now;
        _endMicros = 0x7fffffffffffffff;
        _collecting = true;
        await controller.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
        await WidgetsBinding.instance.endOfFrame;
        _endMicros = developer.Timeline.now;
        // Engine timings arrive in batches after the frame was submitted.
        await Future<void>.delayed(const Duration(milliseconds: 180));
        _collecting = false;
        if (round == 0) continue;
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        reports.add({
          'width': width,
          'actualWidth': view.physicalSize.width / view.devicePixelRatio,
          'actualHeight': view.physicalSize.height / view.devicePixelRatio,
          'dpr': view.devicePixelRatio,
          'optimized': optimized,
          'round': round,
          'cardsBuilt': builds,
          'endOffset': controller.offset,
          'decodedCount': cache.decoded.currentSize,
          'decodedBytes': cache.decoded.currentSizeBytes,
          ..._summary(),
        });
        print('TOP ${jsonEncode(reports.last)}');
      }
      _content.value = const SizedBox();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await cache.close();
  }
  await File('artifacts/scroll-to-top/profile.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
  print('TOP DONE');
  exit(0);
}

Map<String, Object> _summary() {
  final builds = _frames.map((f) => f.buildDuration.inMicroseconds).toList()
    ..sort();
  final rasters = _frames.map((f) => f.rasterDuration.inMicroseconds).toList()
    ..sort();
  double percentile(List<int> values, double p) =>
      values.isEmpty ? 0 : values[((values.length - 1) * p).round()] / 1000;
  return {
    'frames': _frames.length,
    'uiP95Ms': percentile(builds, .95),
    'uiMaxMs': percentile(builds, 1),
    'uiTotalMs': builds.fold(0, (a, b) => a + b) / 1000,
    'rasterP95Ms': percentile(rasters, .95),
    'rasterMaxMs': percentile(rasters, 1),
    'over16_67ms': _frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 16667 ||
              f.rasterDuration.inMicroseconds > 16667,
        )
        .length,
  };
}

// The previous grid's natural-height SliverList, with exactly the same rows,
// repaint boundaries and bounded text measurements as the optimized fixture.
class _ReferenceGrid extends StatefulWidget {
  const _ReferenceGrid({required this.itemCount, required this.itemBuilder});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_ReferenceGrid> createState() => _ReferenceGridState();
}

class _ReferenceGridState extends State<_ReferenceGrid> {
  Widget? _rows;
  double? _extent;

  @override
  Widget build(BuildContext context) => TextMeasurementCacheScope(
    child: SliverLayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.crossAxisExtent;
        if (_extent == extent && _rows != null) return _rows!;
        _extent = extent;
        final columns = extent < 600 ? 2 : 6;
        final spacing = extent < 600 ? 6.0 : 20.0;
        final runSpacing = extent < 600 ? 16.0 : 24.0;
        final width = (extent - (columns - 1) * spacing) / columns;
        return _rows = SliverList.builder(
          itemCount: (widget.itemCount / columns).ceil(),
          itemBuilder: (context, row) => Padding(
            padding: EdgeInsets.only(bottom: runSpacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: spacing,
              children: [
                for (var column = 0; column < columns; column++)
                  if (row * columns + column < widget.itemCount)
                    SizedBox(
                      width: width,
                      child: RepaintBoundary(
                        child: widget.itemBuilder(
                          context,
                          row * columns + column,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
