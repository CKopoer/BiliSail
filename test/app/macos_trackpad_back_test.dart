import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/presentation/page_back_scope.dart';
import 'package:bilisail/features/playback/presentation/playback_timeline_bar.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';

void main() {
  for (final mode in [
    WorkspaceNavigationMode.singlePage,
    WorkspaceNavigationMode.dualTabs,
  ]) {
    testWidgets('macOS back follows page and video history in $mode', (
      tester,
    ) async {
      final router = _router(mode: mode);
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      router.go('/video/A');
      await tester.pumpAndSettle();
      final firstVideo = tester.element(find.text('page /video/A'));
      router.go('/video/B');
      await tester.pumpAndSettle();
      final drag = await _drag(tester);
      await drag.moveBy(const Offset(150, 0));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/video/B');
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(tester.element(find.text('page /video/A')), same(firstVideo));

      router.go('/user/42');
      await tester.pumpAndSettle();
      await _back(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        mode == WorkspaceNavigationMode.dualTabs ? '/' : '/video/A',
      );
      expect(
        tester.element(find.text('page /video/A', skipOffstage: false)),
        same(firstVideo),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('multi-tab Back closes the current tab in tab order', (
    tester,
  ) async {
    final router = _router(mode: WorkspaceNavigationMode.multipleTabs);
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/video/A');
    await tester.pumpAndSettle();
    router.go('/video/B');
    await tester.pumpAndSettle();
    router.go('/user/42');
    await tester.pumpAndSettle();

    // Revisiting A changes the visit history but not the tab strip order.
    await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsOneWidget);

    // The fixed root is not closed even though other visits remain in history.
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const ValueKey('workspace-tab-home')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-3')));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/video/B');
    expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final path in ['/video/A', '/pgc/42', '/live/42', '/offline/42']) {
    for (final swipe in [false, true]) {
      testWidgets(
        'multi-tab ${swipe ? 'swipe' : 'close button'} releases $path',
        (tester) async {
          final router = _router(mode: WorkspaceNavigationMode.multipleTabs);
          addTearDown(router.dispose);
          await tester.pumpWidget(_app(router));
          router.go(path);
          await tester.pumpAndSettle();
          final player = tester.element(find.text('page $path'));
          router.go('/user/42');
          await tester.pumpAndSettle();
          final profile = tester.element(find.text('page /user/42'));
          await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
          await tester.pumpAndSettle();

          if (swipe) {
            await _back(tester);
          } else {
            await tester.tap(
              find.byKey(const ValueKey('close-workspace-tab-tab-1')),
            );
            await tester.pumpAndSettle();
          }
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(player.mounted, isFalse);
          expect(
            find.byKey(const ValueKey('workspace-tab-tab-1')),
            findsNothing,
          );
          expect(profile.mounted, isTrue);
          await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-2')));
          await tester.pumpAndSettle();
          expect(tester.element(find.text('page /user/42')), same(profile));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'single-page Back releases visits and restores the original page',
    (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router));
      router.go('/video/A');
      await tester.pumpAndSettle();
      final firstVideo = tester.element(find.text('page /video/A'));
      router.go('/user/42');
      await tester.pumpAndSettle();
      final profile = tester.element(find.text('page /user/42'));
      router.go('/video/B');
      await tester.pumpAndSettle();
      final secondVideo = tester.element(find.text('page /video/B'));

      await _back(tester);
      expect(router.routeInformationProvider.value.uri.path, '/user/42');
      expect(tester.element(find.text('page /user/42')), same(profile));
      expect(secondVideo.mounted, isFalse);
      await _back(tester);
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(tester.element(find.text('page /video/A')), same(firstVideo));
      expect(profile.mounted, isFalse);
      await _back(tester);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(firstVideo.mounted, isFalse);
      await _back(tester);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('multi-tab Back handles page detail before closing its tab', (
    tester,
  ) async {
    var detail = true;
    final router = _router(
      mode: WorkspaceNavigationMode.multipleTabs,
      builder: (_, tab) => StatefulBuilder(
        builder: (context, setState) => PageBackHandler(
          enabled: tab.isProfile && detail,
          onBack: () {
            setState(() => detail = false);
            return true;
          },
          child: Text('page ${tab.location.path}'),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/user/42');
    await tester.pumpAndSettle();
    await _back(tester);
    expect(detail, isFalse);
    expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsOneWidget);
    await _back(tester);
    expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('page-local Back wins before the workspace page changes', (
    tester,
  ) async {
    var detail = true;
    final router = _router(
      builder: (_, tab) => StatefulBuilder(
        builder: (context, setState) => PageBackHandler(
          enabled: tab.isProfile && detail,
          onBack: () {
            setState(() => detail = false);
            return true;
          },
          child: Text('page ${tab.location.path}'),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/user/42');
    await tester.pumpAndSettle();
    await _back(tester);
    expect(detail, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('empty root history and route changes do not navigate', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
    router.go('/video/A');
    await tester.pumpAndSettle();
    final drag = await _drag(tester);
    await drag.moveBy(const Offset(150, 0));
    await tester.pump();
    router.go('/user/42');
    await tester.pumpAndSettle();
    await drag.panZoomEnd();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    expect(tester.takeException(), isNull);
  });

  testWidgets('player timeline keeps mouse seek and blocks trackpad Back', (
    tester,
  ) async {
    final seeks = <Duration>[];
    final bounds = GlobalKey();
    final router = _router(
      builder: (_, tab) => tab.isPlayback
          ? SizedBox.expand(
              key: bounds,
              child: Center(
                child: PlaybackTimelineBar(
                  position: const Duration(seconds: 30),
                  duration: const Duration(minutes: 1),
                  buffered: const Duration(seconds: 50),
                  chapters: const [],
                  sourceGeneration: 1,
                  playerBoundsKey: bounds,
                  onSeek: (position) async => seeks.add(position),
                  onPreviewRequest: () {},
                ),
              ),
            )
          : const SizedBox.expand(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/video/A');
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('playback-timeline-slider'));
    final origin = tester.getCenter(slider);
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomStart(origin);
    await trackpad.moveBy(const Offset(60, 0));
    await trackpad.moveBy(const Offset(140, 0));
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/video/A');
    expect(seeks, isEmpty);
    final mouse = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(100, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(const Duration(seconds: 30)));
    expect(router.routeInformationProvider.value.uri.path, '/video/A');
    expect(tester.takeException(), isNull);
  });
}

Future<TestGesture> _drag(WidgetTester tester) async {
  final drag = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  // Start in page content, away from the shell's horizontal tab strips.
  await drag.panZoomStart(const Offset(400, 350));
  return drag;
}

Future<void> _back(WidgetTester tester) async {
  final drag = await _drag(tester);
  await drag.moveBy(const Offset(60, 0));
  await drag.moveBy(const Offset(90, 0));
  await drag.panZoomEnd();
  await tester.pumpAndSettle();
}

Widget _app(GoRouter router) => InputTestApp.router(
  routerConfig: router,
  theme: ThemeData(platform: TargetPlatform.macOS),
);

GoRouter _router({
  WorkspaceNavigationMode mode = WorkspaceNavigationMode.singlePage,
  WorkspacePageBuilder? builder,
}) => GoRouter(
  routes: [
    ShellRoute(
      observers: [],
      builder: (context, state, child) => BiliAppShell(
        location: state.uri.toString(),
        navigationMode: mode,
        pageBuilder: builder ?? (_, tab) => Text('page ${tab.location.path}'),
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
          GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    ),
  ],
);
