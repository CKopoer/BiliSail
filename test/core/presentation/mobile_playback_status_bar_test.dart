import 'dart:ui' as ui;

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/android_system_ui.dart';
import 'package:bilisail/core/presentation/mobile_playback_status_bar.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'mobile playback paints black status area and restores browsing, dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.display.size = const Size(390, 844);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.reset);
        addTearDown(tester.view.display.resetSize);
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
        final router = GoRouter(
          routes: [
            ShellRoute(
              builder: (_, state, child) => BiliAppShell(
                location: state.uri.toString(),
                navigationMode: WorkspaceNavigationMode.singlePage,
                pageBuilder: (_, tab) => SizedBox.expand(
                  key: ValueKey('content-${tab.location.path}'),
                ),
                child: child,
              ),
              routes: [
                for (final path in [
                  '/',
                  '/video/:id',
                  '/pgc/:id',
                  '/live/:id',
                  '/offline/:id',
                  '/user/:id',
                ])
                  GoRoute(path: path, builder: (_, _) => const SizedBox()),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        final theme = dark ? BiliTheme.dark() : BiliTheme.light();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp.router(
              theme: theme,
              builder: (_, child) => AndroidSystemUi(child: child!),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<Color> topPixel() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = (await tester.runAsync(() => render.toImage()))!;
          try {
            final pixels = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;
            final offset = (12 * image.width + image.width ~/ 2) * 4;
            return Color.fromARGB(
              pixels.getUint8(offset + 3),
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            );
          } finally {
            image.dispose();
          }
        }

        expect(await topPixel(), theme.colorScheme.surface);
        for (final path in ['/video/1', '/pgc/1', '/live/1', '/offline/1']) {
          router.go(path);
          await tester.pumpAndSettle();
          expect(await topPixel(), Colors.black, reason: path);
          expect(styles.last['statusBarIconBrightness'], 'Brightness.light');
          expect(styles.last['statusBarBrightness'], 'Brightness.dark');
          expect(
            tester.getTopLeft(find.byKey(ValueKey('content-$path'))).dy,
            greaterThanOrEqualTo(24),
          );
          if (theme.platform == TargetPlatform.android) {
            expect(styles.last['systemNavigationBarColor'], 0);
            expect(
              styles.last['systemNavigationBarIconBrightness'],
              dark ? 'Brightness.light' : 'Brightness.dark',
            );
          }
        }
        tester.view.physicalSize = const Size(844, 390);
        tester.view.display.size = const Size(844, 390);
        await tester.pumpAndSettle();
        expect(await topPixel(), Colors.black);
        // Wide displays keep their theme, including a narrow split window.
        for (final size in [const Size(900, 600), const Size(390, 844)]) {
          tester.view.display.size = const Size(900, 600);
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final wideBrowseColor =
              theme.platform == TargetPlatform.android || size.width < 600
              ? theme.colorScheme.surface
              : theme.scaffoldBackgroundColor;
          expect(await topPixel(), wideBrowseColor);
        }
        tester.view.display.size = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(await topPixel(), Colors.black);
        // A retained player must not keep the status area black on its UP page.
        router.go('/user/1');
        await tester.pumpAndSettle();
        final browseColor = theme.colorScheme.surface;
        expect(await topPixel(), browseColor);
        router.go('/');
        await tester.pumpAndSettle();
        expect(await topPixel(), browseColor);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('desktop keeps its existing status area', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light().copyWith(platform: TargetPlatform.windows),
        home: MobilePlaybackStatusBar(
          enabled: true,
          builder: (_) => const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing);
  });
}
