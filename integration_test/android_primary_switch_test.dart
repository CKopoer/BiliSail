import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/primary_switch_app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile warm Android primary switches with cached covers', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 480, 270),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(480, 270), [
          Colors.blue,
          Colors.amber,
        ]),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 270);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final fixture = PrimarySwitchFixture(data!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    await tester.pumpWidget(fixture.app);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    // The liquid dock exposes no per-destination keys; locate tabs by label.
    const dockLabels = {
      'dynamic': '动态',
      'mine': '我的',
      'settings': '设置',
      'home': '首页',
    };
    Future<void> bottom(String name) async {
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('workspace-bottom-navigation')),
              matching: find.text(dockLabels[name]!),
            )
            .first,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
    }

    await bottom('dynamic');
    await tester.tap(find.byKey(const ValueKey('channel-videoDynamic')));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    await bottom('mine');
    await tester.tap(find.byKey(const ValueKey('account-tab-watchLater')));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    await bottom('settings');
    await bottom('home');
    final reads = Map.of(fixture.home.reads);
    final feedReads = fixture.feed.reads;
    final samples = <Map<String, Object>>[];
    final timings = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> frames) => timings.addAll(frames);
    binding.addTimingsCallback(collect);
    for (var round = 0; round < 8; round++) {
      for (final name in ['dynamic', 'mine', 'settings', 'home']) {
        timings.clear();
        await bottom(name);
        // FrameTiming arrives in batches; flush outside the animated interval.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        final frames = List.of(timings);
        samples.add({
          'target': name,
          'uiUs': frames.map((f) => f.buildDuration.inMicroseconds).toList(),
          'rasterUs': frames
              .map((f) => f.rasterDuration.inMicroseconds)
              .toList(),
        });
      }
    }
    binding.removeTimingsCallback(collect);
    final result = {
      'label': const String.fromEnvironment(
        'SWITCH_LABEL',
        defaultValue: 'current',
      ),
      'samples': samples,
      'feedReads': fixture.feed.reads,
      'homeReads': fixture.home.reads,
      'refreshRate':
          ui.PlatformDispatcher.instance.views.first.display.refreshRate,
    };
    binding.reportData = {'primarySwitch': result};
    for (final sample in samples) {
      debugPrint(
        'PRIMARY_SWITCH_SAMPLE ${jsonEncode(sample)}',
        wrapWidth: null,
      );
    }
    if (const String.fromEnvironment('SWITCH_LABEL') != 'baseline') {
      expect(fixture.home.reads, reads);
    }
    expect(fixture.feed.reads, feedReads);
    expect(samples.every((s) => (s['uiUs']! as List).isNotEmpty), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    await fixture.dispose();
  });
}
