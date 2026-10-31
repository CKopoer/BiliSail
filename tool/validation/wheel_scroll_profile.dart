// Offline Windows wheel-motion probe. Uses real pointer signals, not animateTo.
// flutter run -d windows --profile -t tool/validation/wheel_scroll_profile.dart
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'card_scroll_profile.dart' show CardScrollFeed;

const _label = String.fromEnvironment('WHEEL_LABEL', defaultValue: 'current');
final _content = ValueNotifier<Widget>(const SizedBox());
final _frames = <ui.FrameTiming>[];
final _motion = <({int time, double pixels})>[];
final _inputs = <int>[];
bool _collecting = false;
ScrollPosition? _scroll;
int _nativeEventCount = 0;
double _nativeDeltaTotal = 0;
bool _nativeTimestampsValid = true;

Widget _observeNative(Widget child) => const bool.fromEnvironment('WHEEL_SMOKE')
    ? Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _nativeEventCount++;
            _nativeDeltaTotal += event.scrollDelta.dy;
            _nativeTimestampsValid =
                _nativeTimestampsValid && event.timeStamp > Duration.zero;
          }
        },
        child: child,
      )
    : child;

void _walk(Element element, void Function(Element) visit) {
  visit(element);
  element.visitChildren((child) => _walk(child, visit));
}

double _pixels(ScrollPosition position) =>
    HeaderScrollController.offsetFor(position)?.pixels ?? position.pixels;

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  return sorted[(percentile * (sorted.length - 1)).round()];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('BiliSail 连续滚轮诊断');
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
      _frames.addAll(batch);
      if (_frames.length > 4096) _frames.removeRange(0, _frames.length - 3072);
    }
  });
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    final position = _scroll;
    if (_collecting && position != null) {
      if (_motion.length == 4096) _motion.removeRange(0, 1024);
      _motion.add((
        time: SchedulerBinding
            .instance
            .currentSystemFrameTimeStamp
            .inMicroseconds,
        pixels: _pixels(position),
      ));
    }
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
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  await Directory('artifacts/wheel-scroll-2026-10-31').create(recursive: true);
  const gate = String.fromEnvironment('WHEEL_GATE');
  if (gate.isNotEmpty) {
    print('WHEEL WAITING $gate');
    while (!await File(gate).exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  final reports = <Map<String, Object?>>[];
  final widths = const bool.fromEnvironment('WHEEL_SMOKE')
      ? [1800.0]
      : [430.0, 1800.0];
  for (final width in widths) {
    await windowManager.setSize(Size(width, 900));
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('memory only'),
        loader: (_, _) async => png,
      ),
    );
    _content.value = ProviderScope(
      key: UniqueKey(),
      overrides: [feedRepositoryProvider.overrideWithValue(CardScrollFeed())],
      child: AppImageCacheScope(
        cache: cache,
        child: ScrollConfiguration(
          behavior: const SmoothScrollBehavior(),
          child: _observeNative(
            ScrollHeaderLayout(
              enabled: width < 600,
              header: SizedBox(height: width < 600 ? 96 : 0),
              child: const FeedScreen(),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    late ScrollPosition position;
    _walk(WidgetsBinding.instance.rootElement!, (element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final candidate = (element.state as ScrollableState).position;
        if (candidate.axis == Axis.vertical &&
            candidate.maxScrollExtent > 500) {
          position = candidate;
        }
      }
      if (element is StatefulElement &&
          element.state is NestedScrollViewState) {
        final outer = (element.state as NestedScrollViewState).outerController;
        outer.jumpTo(outer.position.maxScrollExtent);
      }
    });
    for (var offset = 500.0; offset <= 10000; offset += 500) {
      position.jumpTo(offset);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    final box =
        position.context.notificationContext!.findRenderObject()! as RenderBox;
    final pointer = box.localToGlobal(box.size.center(Offset.zero));
    if (const bool.fromEnvironment('WHEEL_SMOKE')) {
      position.jumpTo(1000);
      var start = _pixels(position);
      _scroll = position;
      _collecting = true;
      registerExtension('ext.bilisail.wheelSnapshot', (method, params) async {
        if (params['reset'] == 'true') {
          _nativeEventCount = 0;
          _nativeDeltaTotal = 0;
          _nativeTimestampsValid = true;
          _frames.clear();
          _motion.clear();
          start = _pixels(position);
        }
        return ServiceExtensionResponse.result(
          jsonEncode({
            'pixels': _pixels(position),
            'distance': _pixels(position) - start,
            'scrolling': position.isScrollingNotifier.value,
            'events': _nativeEventCount,
            'deltaTotal': _nativeDeltaTotal,
            'positiveTimestamps': _nativeTimestampsValid,
            'frames': _frames.length,
          }),
        );
      });
      print('WHEEL SMOKE READY');
      await Completer<void>().future;
    }
    for (final (intervalMs, count) in [(70, 32), (16, 64)]) {
      position.jumpTo(1000);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final start = _pixels(position);
      _scroll = position;
      _frames.clear();
      _motion.clear();
      _inputs.clear();
      _collecting = true;
      for (var event = 0; event < count; event++) {
        final stamp = Timeline.now;
        _inputs.add(stamp);
        GestureBinding.instance.handlePointerEvent(
          PointerScrollEvent(
            timeStamp: Duration(microseconds: stamp),
            kind: PointerDeviceKind.mouse,
            position: pointer,
            scrollDelta: const Offset(0, 120),
          ),
        );
        await Future<void>.delayed(Duration(milliseconds: intervalMs));
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      _collecting = false;
      _scroll = null;
      final response = SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: 1600,
          ratio: 1.3,
        ),
        0,
        120,
        0,
      );
      final errors = <double>[];
      final path = <Map<String, num>>[];
      for (final frame in _motion) {
        if (frame.time < _inputs.first || frame.time > _inputs.last) continue;
        var expected = start;
        for (final event in _inputs) {
          if (event <= frame.time) {
            expected += response.x((frame.time - event) / 1000000);
          }
        }
        final error = frame.pixels - expected;
        errors.add(error.abs());
        path.add({
          'atUs': frame.time - _inputs.first,
          'pixels': frame.pixels - start,
          'expected': expected - start,
          'error': error,
        });
      }
      if ((_pixels(position) - start - 120 * count).abs() > .01) {
        throw StateError('Wheel distance lost or reached a boundary');
      }
      final uiMs = _frames
          .map((f) => f.buildDuration.inMicroseconds / 1000)
          .toList();
      final rasterMs = _frames
          .map((f) => f.rasterDuration.inMicroseconds / 1000)
          .toList();
      reports.add({
        'label': _label,
        'width': width,
        'intervalMs': intervalMs,
        'notches': count,
        'distance': _pixels(position) - start,
        'frames': _frames.length,
        'motionFrames': errors.length,
        'errorP95Px': _percentile(errors, .95),
        'errorMaxPx': _percentile(errors, 1),
        'uiP95Ms': _percentile(uiMs, .95),
        'rasterP95Ms': _percentile(rasterMs, .95),
        'over16_67ms': _frames
            .where(
              (f) =>
                  f.buildDuration.inMicroseconds > 16667 ||
                  f.rasterDuration.inMicroseconds > 16667,
            )
            .length,
        'inputAtUs': [for (final t in _inputs) t - _inputs.first],
        'path': path,
      });
      print(
        'WHEEL ${jsonEncode({...reports.last}
          ..remove('path')
          ..remove('inputAtUs'))}',
      );
      await File('artifacts/wheel-scroll-2026-10-31/$_label.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
    }
    _content.value = const SizedBox();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await cache.close();
  }
  print('WHEEL DONE');
  exit(0);
}
