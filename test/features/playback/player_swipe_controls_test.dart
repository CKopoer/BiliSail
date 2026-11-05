import 'dart:async';

import 'package:bilisail/core/platform/window_brightness_service.dart';
import 'package:bilisail/features/playback/presentation/player_swipe_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'center fullscreen gesture clears side feedback without changing volume',
    (tester) async {
      final volumes = <double>[];
      var fullscreenCalls = 0;
      await tester.pumpWidget(
        _app(volumes: volumes, onFullScreen: () => fullscreenCalls++),
      );
      await tester.dragFrom(const Offset(300, 100), const Offset(0, -40));
      await tester.pump();
      expect(find.text('音量 70%'), findsOneWidget);
      final writes = volumes.length;
      // Downwards in inline presentation deliberately does not enter fullscreen.
      await tester.dragFrom(const Offset(200, 100), const Offset(0, 50));
      await tester.pump();
      expect(fullscreenCalls, 0);
      expect(volumes.length, writes);
      expect(find.byKey(const ValueKey('player-swipe-feedback')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('quick swipe applies its final delta after the brightness read', (
    tester,
  ) async {
    final brightness = _Brightness()..readGate = Completer<double>();
    await tester.pumpWidget(_app(brightness: brightness));
    await tester.dragFrom(const Offset(100, 100), const Offset(0, -40));
    brightness.readGate!.complete(.4);
    await tester.pump();
    expect(brightness.values.last, closeTo(.6, .01));
    expect(find.text('亮度 60%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('right swipe adjusts volume from its initial value and clamps', (
    tester,
  ) async {
    final volumes = <double>[];
    await tester.pumpWidget(_app(volumes: volumes));
    final drag = await tester.startGesture(const Offset(300, 100));
    await drag.moveBy(const Offset(0, -50));
    await tester.pump();
    expect(volumes.last, closeTo(75, .01));
    expect(find.text('音量 75%'), findsOneWidget);
    // Crossing the middle keeps the action selected at pointer down.
    await drag.moveBy(const Offset(-240, -300));
    await tester.pump();
    expect(volumes.last, 100);
    await drag.moveBy(const Offset(0, 1000));
    await tester.pump();
    expect(volumes.last, 0);
    await drag.up();
    await tester.pump(const Duration(milliseconds: 801));
    expect(find.byKey(const ValueKey('player-swipe-feedback')), findsNothing);
  });

  testWidgets('left swipe dims only the picture and restores when disabled', (
    tester,
  ) async {
    final volumes = <double>[];
    await tester.pumpWidget(_app(volumes: volumes));
    await tester.dragFrom(const Offset(100, 100), const Offset(0, 100));
    await tester.pump();
    expect(find.text('亮度 50%'), findsOneWidget);
    final dimmer = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('player-brightness-dimmer')),
    );
    expect(dimmer.color.a, closeTo(.5, .01));
    expect(volumes, isEmpty);
    await tester.pumpWidget(_app(volumes: volumes, enabled: false));
    expect(
      find.byKey(const ValueKey('player-brightness-dimmer')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in ['disabled', 'mouse', 'horizontal']) {
    testWidgets('$action does not adjust volume or brightness', (tester) async {
      final volumes = <double>[];
      final brightness = _Brightness();
      await tester.pumpWidget(
        _app(
          volumes: volumes,
          brightness: brightness,
          enabled: action != 'disabled',
        ),
      );
      final drag = await tester.startGesture(
        const Offset(300, 100),
        kind: action == 'mouse'
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await drag.moveBy(
        action == 'horizontal' ? const Offset(60, 0) : const Offset(0, -60),
      );
      await drag.up();
      await tester.pump();
      expect(volumes, isEmpty);
      expect(brightness.values, isEmpty);
      expect(find.byKey(const ValueKey('player-swipe-feedback')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'native brightness starts at the current level and restores on exit',
    (tester) async {
      final brightness = _Brightness();
      await tester.pumpWidget(_app(brightness: brightness));
      final drag = await tester.startGesture(const Offset(100, 100));
      await drag.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(brightness.values.last, closeTo(.6, .01));
      expect(find.text('亮度 60%'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-brightness-dimmer')),
        findsNothing,
      );
      await drag.moveBy(const Offset(0, 1000));
      await tester.pump();
      expect(brightness.values.last, .01);
      await drag.up();
      await tester.pumpWidget(const SizedBox());
      expect(brightness.resets, 1);
    },
  );

  for (final action in [
    'disabled',
    'source',
    'background',
    'cancel',
    'dispose',
  ]) {
    testWidgets('$action discards a delayed brightness read', (tester) async {
      final brightness = _Brightness()..readGate = Completer<double>();
      await tester.pumpWidget(_app(brightness: brightness));
      final drag = await tester.startGesture(const Offset(100, 100));
      await drag.moveBy(const Offset(0, -40));
      await tester.pump();
      if (action == 'disabled' || action == 'source') {
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            enabled: action != 'disabled',
            generation: action == 'source' ? 2 : 1,
          ),
        );
      } else if (action == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
      } else if (action == 'cancel') {
        await drag.cancel();
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      brightness.readGate!.complete(.4);
      await tester.pump();
      expect(brightness.values, isEmpty);
      if (action != 'cancel') await drag.up();
      if (action == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pending brightness writes coalesce and reset after a background transition',
    (tester) async {
      final brightness = _Brightness()..writeGate = Completer<void>();
      await tester.pumpWidget(_app(brightness: brightness));
      final drag = await tester.startGesture(const Offset(100, 100));
      await drag.moveBy(const Offset(0, -40));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await drag.moveBy(const Offset(0, -1));
      }
      expect(brightness.values, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      brightness.writeGate!.complete();
      await tester.pump();
      expect(brightness.values, hasLength(1));
      expect(brightness.resets, 1);
      await drag.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('brightness failure reports feedback without unhandled errors', (
    tester,
  ) async {
    final brightness = _Brightness()..failRead = true;
    await tester.pumpWidget(_app(brightness: brightness));
    await tester.dragFrom(const Offset(100, 100), const Offset(0, -40));
    await tester.pump();
    expect(find.text('亮度调节失败'), findsOneWidget);
    expect(brightness.values, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _app({
  List<double>? volumes,
  _Brightness? brightness,
  bool enabled = true,
  int generation = 1,
  VoidCallback? onFullScreen,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 200,
        child: PlayerSwipeControls(
          enabled: enabled,
          sourceGeneration: generation,
          onFullScreen: onFullScreen,
          volume: 50,
          setVolume: (value) async {
            volumes?.add(value);
          },
          brightness: brightness ?? _Dimmer(),
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    ),
  ),
);

class _Dimmer extends WindowBrightnessService {
  @override
  bool get isNative => false;
}

class _Brightness extends WindowBrightnessService {
  final values = <double>[];
  int resets = 0;
  bool failRead = false;
  Completer<double>? readGate;
  Completer<void>? writeGate;
  @override
  bool get isNative => true;
  @override
  Future<double> read() async {
    if (failRead) throw StateError('unavailable');
    return readGate?.future ?? .4;
  }

  @override
  Future<void> set(double value) async {
    values.add(value);
    await writeGate?.future;
  }

  @override
  Future<void> reset() async {
    resets++;
  }
}
