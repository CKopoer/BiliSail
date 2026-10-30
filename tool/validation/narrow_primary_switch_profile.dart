// Windows diagnostic entry point, never used by a normal app build.
// Captures widget identities and frame timings without content or credentials.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/main.dart' as production;
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../test/support/primary_switch_app.dart';

final frames = <Map<String, int>>[];
final events = <Map<String, Object?>>[];
final reduceMotion = ValueNotifier<bool>(false);
final simulatedDpr = ValueNotifier<double>(1);
PrimarySwitchFixture? fixture;
void walk(Element element, void Function(Element) visit) {
  visit(element);
  element.visitChildren((child) => walk(child, visit));
}

Element? navigationElement() {
  Element? found;
  walk(WidgetsBinding.instance.rootElement!, (e) {
    if (e.widget is NavigationBar) found = e;
  });
  return found;
}

Map<String, Object?> snapshot() {
  final types = <String, int>{};
  final roots = <String, Map<String, Object?>>{};
  final cards = <String, List<int>>{};
  final scrolls = <String, Object?>{};
  walk(WidgetsBinding.instance.rootElement!, (e) {
    final type = e.widget.runtimeType.toString();
    types.update(type, (v) => v + 1, ifAbsent: () => 1);
    if (e.widget.key.toString().contains('workspace-root-')) {
      roots[e.widget.key.toString()] = {'element': identityHashCode(e)};
    }
    if (e.widget is VideoCard ||
        e.widget is AppNetworkImage ||
        e is StatefulElement && e.state is ScrollableState) {
      String root = 'outside';
      e.visitAncestorElements((p) {
        if (p.widget.key.toString().contains('workspace-root-')) {
          root = p.widget.key.toString();
          return false;
        }
        return true;
      });
      final active =
          e.getInheritedWidgetOfExactType<WorkspaceActivity>()?.active ?? true;
      final key = '$root/$type/${active ? 'active' : 'hidden'}';
      (cards[key] ??= []).add(identityHashCode(e));
      if (e is StatefulElement && e.state is ScrollableState) {
        final p = (e.state as ScrollableState).position;
        scrolls['${identityHashCode(e)}'] = {
          'root': root,
          'position': identityHashCode(p),
          'pixels': p.hasPixels ? p.pixels : null,
          'axis': p.axis.toString(),
        };
      }
    }
  });
  return {
    'types': types,
    'roots': roots,
    'elements': cards,
    'scrolls': scrolls,
    'feedReads': fixture?.feed.reads,
    'homeReads': fixture?.home.reads,
    'cacheEntries': fixture?.cache.decoded.currentSize,
    'cacheBytes': fixture?.cache.decoded.currentSizeBytes,
    'simulatedDpr': simulatedDpr.value,
    'viewport': [
      for (final v in ui.PlatformDispatcher.instance.views)
        [
          v.physicalSize.width / v.devicePixelRatio,
          v.physicalSize.height / v.devicePixelRatio,
        ],
    ],
  };
}

Future<void> main(List<String> arguments) async {
  const real = bool.fromEnvironment('REAL_APP');
  if (real) {
    await production.main(arguments);
  } else {
    BiliWidgetsBinding.ensureInitialized();
    await windowManager.ensureInitialized();
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
    image.dispose();
    picture.dispose();
    fixture = PrimarySwitchFixture(data!.buffer.asUint8List());
    runApp(
      ListenableBuilder(
        listenable: Listenable.merge([reduceMotion, simulatedDpr]),
        child: fixture!.app,
        builder: (context, child) => Align(
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: simulatedDpr.value,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              height: 844,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: const Size(390, 844),
                  devicePixelRatio: simulatedDpr.value,
                  disableAnimations: reduceMotion.value,
                ),
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
  }
  await windowManager.ensureInitialized();
  await windowManager.setTitle('BiliSail 窄屏性能诊断 ${real ? '真实页面' : '离线页面'}');
  await windowManager.show();
  if (!real) await windowManager.setSize(const Size(406, 883));
  WidgetsBinding.instance.addTimingsCallback((batch) {
    for (final f in batch) {
      frames.add({
        'start': f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
        'ui': f.buildDuration.inMicroseconds,
        'raster': f.rasterDuration.inMicroseconds,
        'total': f.totalSpan.inMicroseconds,
        'vsync': f.vsyncOverhead.inMicroseconds,
      });
    }
    if (frames.length > 5000) frames.removeRange(0, frames.length - 5000);
  });
  registerExtension('ext.bilisail.switchProbe', (method, params) async {
    final action = params['action'] ?? 'snapshot';
    Object? result;
    if (action == 'snapshot') result = snapshot();
    if (action == 'reset') {
      frames.clear();
      events.clear();
      result = true;
    }
    if (action == 'motion') {
      reduceMotion.value = params['reduced'] == 'true';
      result = true;
    }
    if (action == 'density') {
      if (real) throw StateError('Density stress requires the offline fixture');
      final ratio = double.parse(params['ratio']!);
      if (ratio < 1 || ratio > 3) throw ArgumentError('Density 1..3');
      // This increases Windows render load; it does not emulate a phone GPU.
      // Remove the native max-track constraint so the full surface is drawn.
      simulatedDpr.value = ratio;
      await windowManager.setMaximumSize(const Size(6000, 6000));
      await windowManager.setSize(Size(390 * ratio + 16, 844 * ratio + 39));
      result = true;
    }
    if (action == 'frames') result = {'frames': frames, 'events': events};
    if (action == 'resize') {
      await windowManager.setSize(
        Size(double.parse(params['width']!), double.parse(params['height']!)),
      );
      result = true;
    }
    if (action == 'go') {
      final e = navigationElement();
      if (e == null) throw StateError('Bottom navigation required');
      GoRouter.of(e).go(params['path']!);
      result = true;
    }
    if (action == 'switch') {
      final e = navigationElement();
      if (e == null) throw StateError('Bottom navigation required');
      final start = Timeline.now;
      final before = snapshot();
      (e.widget as NavigationBar).onDestinationSelected!(
        int.parse(params['index']!),
      );
      events.add({'index': params['index'], 'start': start});
      await Future<void>.delayed(const Duration(milliseconds: 900));
      result = {
        'start': start,
        'before': before,
        'after': snapshot(),
        'frames': frames.where((f) => f['start']! >= start).toList(),
      };
    }
    if (action == 'quit') {
      Timer(const Duration(milliseconds: 300), () => exit(0));
      result = true;
    }
    return ServiceExtensionResponse.result(jsonEncode({'result': result}));
  });
  print('SWITCH_PROBE_READY real=$real');
}
