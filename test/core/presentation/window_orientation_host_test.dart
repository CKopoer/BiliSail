import 'dart:async';

import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/window_orientation_host.dart';
import 'package:bilisail/domain/app_orientation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<Object?> orientations;
  setUp(() {
    orientations = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
        }
        return null;
      },
    );
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  testWidgets(
    'desktop direction constrains layout and preserves the subtree',
    (tester) async {
      _display(tester, const Size(1600, 1000));
      tester.view.physicalSize = const Size(1000, 700);
      final sizes = <Size>[];
      final window = WindowService.forView(
        viewId: 72,
        setFullScreen: (_) async {},
        activate: () async {},
        resize: (size) async {
          sizes.add(size);
          return false; // A maximized window can keep its native rectangle.
        },
      );
      final child = GlobalKey();
      late Size mediaSize;
      Future<void> show(AppOrientationPreference orientation) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, content) => WindowOrientationHost(
              window: window,
              orientation: orientation,
              child: content!,
            ),
            home: Builder(
              builder: (context) {
                mediaSize = MediaQuery.sizeOf(context);
                return SizedBox.expand(key: child);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(AppOrientationPreference.automatic);
      final original = child.currentContext;
      expect(mediaSize, const Size(1000, 700));
      expect(sizes, isEmpty);
      await show(AppOrientationPreference.portrait);
      expect(mediaSize.width, lessThan(mediaSize.height));
      expect(tester.getSize(find.byKey(child)), mediaSize);
      expect(window.keepsBrowsePortrait, isTrue);
      expect(sizes.single.width, lessThan(sizes.single.height));
      await window.setFullScreen(
        true,
        orientation: FullScreenOrientation.landscape,
      );
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      expect(mediaSize, const Size(1600, 1000));
      expect(sizes, hasLength(1));
      await show(AppOrientationPreference.landscape);
      expect(mediaSize, const Size(1600, 1000));
      tester.view.physicalSize = const Size(700, 1000);
      await tester.pumpAndSettle();
      expect(mediaSize.width, greaterThan(mediaSize.height));
      await window.setFullScreen(
        true,
        orientation: FullScreenOrientation.portrait,
      );
      await tester.pumpAndSettle();
      expect(mediaSize, const Size(700, 1000));
      await window.setFullScreen(false);
      await tester.pumpAndSettle();
      expect(mediaSize.width, greaterThan(mediaSize.height));
      await show(AppOrientationPreference.automatic);
      expect(mediaSize, const Size(700, 1000));
      expect(child.currentContext, same(original));
      expect(window.allowsAutomaticRotation, isTrue);
      expect(orientations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets('desktop normal windows resize once and cancel stale choices', (
    tester,
  ) async {
    _display(tester, const Size(1600, 1000));
    tester.view.physicalSize = const Size(1000, 700);
    final resized = <Size>[];
    var available = true;
    final window = WindowService.forView(
      viewId: 73,
      setFullScreen: (_) async {},
      activate: () async {},
      isAvailable: () => available,
      resize: (size) async {
        resized.add(size);
        return true;
      },
    );
    Future<void> update(
      AppOrientationPreference orientation, {
      Size size = const Size(1000, 700),
    }) async {
      final pending = window.updateDisplaySize(
        const Size(1600, 1000),
        orientation: orientation,
        logicalWindowSize: size,
      );
      await tester.pumpAndSettle();
      await pending;
    }

    await update(AppOrientationPreference.portrait);
    expect(resized.single.width, lessThan(resized.single.height));
    expect(resized.single.height, lessThanOrEqualTo(900));
    await update(AppOrientationPreference.portrait);
    expect(resized, hasLength(1));
    await update(
      AppOrientationPreference.landscape,
      size: const Size(700, 900),
    );
    expect(resized.last, const Size(900, 700));
    final stale = window.updateDisplaySize(
      const Size(1600, 1000),
      orientation: AppOrientationPreference.portrait,
      logicalWindowSize: const Size(1000, 700),
    );
    final latest = window.updateDisplaySize(
      const Size(1600, 1000),
      logicalWindowSize: const Size(1000, 700),
    );
    await tester.pumpAndSettle();
    await Future.wait([stale, latest]);
    expect(resized, hasLength(2));
    available = false;
    await update(AppOrientationPreference.portrait);
    expect(resized, hasLength(2));
    await window.clearDisplayOrientationPolicy();
  });

  for (final size in [const Size(400, 900), const Size(800, 1200)]) {
    testWidgets(
      'video fullscreen overrides browse direction and restores it: $size',
      (tester) async {
        _display(tester, size);
        final window = _MobileWindow();
        final child = GlobalKey();
        Future<void> show(AppOrientationPreference orientation) async {
          await tester.pumpWidget(
            MaterialApp(
              home: WindowOrientationHost(
                window: window,
                orientation: orientation,
                child: SizedBox.expand(key: child),
              ),
            ),
          );
          await tester.pump();
        }

        await show(AppOrientationPreference.landscape);
        final originalChild = child.currentContext;
        expect(window.allowsAutomaticRotation, isFalse);
        expect(window.keepsBrowsePortrait, isFalse);
        expect(orientations.single, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
        await window.setFullScreen(
          true,
          orientation: FullScreenOrientation.portrait,
        );
        expect(orientations.last, ['DeviceOrientation.portraitUp']);
        await window.setFullScreen(false);
        expect(orientations.last, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
        tester.view.display.size = const Size(1200, 800);
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pump();
        expect(orientations, hasLength(3));
        await show(AppOrientationPreference.portrait);
        expect(window.keepsBrowsePortrait, isTrue);
        expect(orientations.last, ['DeviceOrientation.portraitUp']);
        await window.setFullScreen(
          true,
          orientation: FullScreenOrientation.landscape,
        );
        expect(orientations, hasLength(5));
        await show(AppOrientationPreference.automatic);
        expect(window.allowsAutomaticRotation, isTrue);
        expect(orientations.last, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
        expect(child.currentContext, same(originalChild));
        tester.view.display.size = const Size(400, 900);
        tester.view.physicalSize = const Size(400, 900);
        await tester.pump();
        expect(orientations.last, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
        await window.setFullScreen(false);
        expect(orientations.last, ['DeviceOrientation.portraitUp']);
        await show(AppOrientationPreference.landscape);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(orientations.last, isEmpty);
      },
    );
  }

  testWidgets('a delayed direction command converges to the latest choice', (
    tester,
  ) async {
    final window = _MobileWindow();
    final gate = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
          if (orientations.length == 1) await gate.future;
        }
        return null;
      },
    );
    final first = window.updateDisplaySize(
      const Size(400, 900),
      orientation: AppOrientationPreference.landscape,
    );
    await tester.pump();
    final second = window.updateDisplaySize(
      const Size(800, 1200),
      orientation: AppOrientationPreference.portrait,
    );
    final third = window.updateDisplaySize(const Size(800, 1200));
    gate.complete();
    await Future.wait([first, second, third]);
    expect(orientations, [
      ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      <String>[],
    ]);
    await window.clearDisplayOrientationPolicy();
  });

  testWidgets(
    'phone browsing stays portrait and fullscreen restores that policy',
    (tester) async {
      _display(tester, const Size(400, 900));
      final window = _MobileWindow();
      await tester.pumpWidget(
        MaterialApp(
          home: WindowOrientationHost(
            window: window,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      expect(orientations, [
        ['DeviceOrientation.portraitUp'],
      ]);
      expect(window.keepsBrowsePortrait, isTrue);
      await window.setFullScreen(
        true,
        orientation: FullScreenOrientation.landscape,
      );
      expect(orientations.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      tester.view.physicalSize = const Size(900, 400);
      await tester.pump();
      expect(orientations, hasLength(2));
      await window.setFullScreen(false);
      expect(orientations.last, ['DeviceOrientation.portraitUp']);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(orientations, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(orientations.last, isEmpty);
    },
  );

  testWidgets(
    'folding and unfolding re-evaluate the complete display at 600 dp',
    (tester) async {
      _display(tester, const Size(599, 900), ratio: 3);
      final window = _MobileWindow();
      await tester.pumpWidget(
        MaterialApp(
          home: WindowOrientationHost(
            window: window,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      expect(orientations, [
        ['DeviceOrientation.portraitUp'],
      ]);
      // The viewport stays narrow while the physical display unfolds. It must
      // still release portrait to escape Android's compatibility letterbox.
      tester.view.display.size = const Size(600, 900) * 3;
      await tester.pump();
      expect(window.keepsBrowsePortrait, isFalse);
      expect(orientations.last, isEmpty);
      final calls = orientations.length;
      tester.view.physicalSize = const Size(500, 900) * 3;
      await tester.pump();
      await window.setFullScreen(true);
      await window.setFullScreen(false);
      expect(orientations, hasLength(calls));
      tester.view.display.size = const Size(399, 900) * 3;
      tester.view.physicalSize = const Size(399, 900) * 3;
      await tester.pump();
      expect(orientations.last, ['DeviceOrientation.portraitUp']);
      final beforeDensityChange = orientations.length;
      tester.view.devicePixelRatio = 1;
      tester.view.display.size = const Size(399, 900);
      tester.view.physicalSize = const Size(399, 900);
      await tester.pump();
      expect(orientations, hasLength(beforeDensityChange));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('unfolding keeps video fullscreen until exit releases the lock', (
    tester,
  ) async {
    final window = _MobileWindow();
    final gate = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
          if ((call.arguments as List<Object?>).contains(
            'DeviceOrientation.landscapeLeft',
          )) {
            await gate.future;
          }
        }
        return null;
      },
    );
    await window.updateDisplaySize(const Size(400, 900));
    final entering = window.setFullScreen(
      true,
      orientation: FullScreenOrientation.landscape,
    );
    await tester.pump();
    final unfold = window.updateDisplaySize(const Size(900, 1200));
    gate.complete();
    await entering;
    await unfold;
    expect(orientations.last, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    // Video dimensions still own fullscreen on an unfolded display.
    await window.setFullScreen(
      true,
      orientation: FullScreenOrientation.portrait,
    );
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
    await window.setFullScreen(false);
    expect(orientations.last, isEmpty);
    await window.clearDisplayOrientationPolicy();
  });

  testWidgets(
    'large displays and desktop hosts never install a portrait lock',
    (tester) async {
      _display(tester, const Size(800, 1200));
      final window = _MobileWindow();
      await tester.pumpWidget(
        MaterialApp(
          home: WindowOrientationHost(
            window: window,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      expect(orientations, isEmpty);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      expect(orientations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final desktop = WindowService.forView(
        viewId: 72,
        setFullScreen: (_) async {},
        activate: () async {},
      );
      await desktop.updateDisplaySize(const Size(400, 900));
      expect(orientations, isEmpty);
    },
  );
}

void _display(WidgetTester tester, Size size, {double ratio = 1}) {
  tester.view.devicePixelRatio = ratio;
  tester.view.display.size = size * ratio;
  tester.view.physicalSize = size * ratio;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.display.resetSize);
  addTearDown(tester.view.resetPhysicalSize);
}

class _MobileWindow extends WindowService {
  @override
  bool get hasDesktopWindow => false;
}
