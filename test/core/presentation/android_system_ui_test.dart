import 'dart:ui' as ui;

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/android_system_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android bars follow theme across routes and app rebuilds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    final navigator = GlobalKey<NavigatorState>();
    final styles = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
          styles.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          navigatorKey: navigator,
          theme: BiliTheme.light(),
          darkTheme: BiliTheme.dark(),
          themeMode: value,
          builder: (context, child) => AndroidSystemUi(child: child!),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void expectStyle(ThemeData theme, Brightness icons, {Color? background}) {
      expect(
        styles.last['systemNavigationBarColor'],
        (background ?? theme.colorScheme.surface).toARGB32(),
      );
      expect(styles.last['systemNavigationBarIconBrightness'], '$icons');
      expect(styles.last['systemNavigationBarContrastEnforced'], false);
      expect(styles.last['systemNavigationBarDividerColor'], 0);
    }

    expectStyle(BiliTheme.light(), Brightness.dark);
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('详情')),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectStyle(BiliTheme.light(), Brightness.dark);
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expectStyle(BiliTheme.dark(), Brightness.light);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expectStyle(BiliTheme.dark(), Brightness.light);
    mode.value = ThemeMode.light;
    await tester.pumpAndSettle();
    expectStyle(BiliTheme.light(), Brightness.dark);
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const AndroidSystemUi(
          backgroundColor: Colors.black,
          brightness: Brightness.dark,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectStyle(BiliTheme.light(), Brightness.light, background: Colors.black);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expectStyle(BiliTheme.light(), Brightness.dark);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (size, dark) in [
    (const Size(390, 844), false),
    (const Size(390, 844), true),
    (const Size(900, 600), false),
    (const Size(900, 600), true),
  ]) {
    testWidgets(
      'Android gesture inset matches the surface at $size, dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.display.size = size;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.reset);
        addTearDown(tester.view.display.resetSize);
        final theme = dark ? BiliTheme.dark() : BiliTheme.light();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => AndroidSystemUi(child: child!),
              home: const BiliAppShell(
                location: '/',
                child: SizedBox.expand(key: ValueKey('content')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final navigation = find.byKey(
          const ValueKey('workspace-bottom-navigation'),
        );
        if (size.width < 600) {
          expect(tester.getRect(navigation).bottom, size.height - 24);
        } else {
          expect(navigation, findsNothing);
        }
        expect(
          tester.getRect(find.byKey(const ValueKey('content'))).bottom,
          lessThan(size.height - 24),
        );
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => render.toImage()))!;
        addTearDown(image.dispose);
        final pixels = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        Color pixel(int x, int y) {
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
        }

        final bottom = size.height.toInt() - 1;
        expect(pixel(1, bottom), theme.colorScheme.surface);
        expect(pixel(1, bottom), pixel(1, bottom - 24));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('other platforms keep their existing system UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light().copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => AndroidSystemUi(child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing);
  });
}
