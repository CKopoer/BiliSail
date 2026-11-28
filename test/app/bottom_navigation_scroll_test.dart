import 'dart:async';

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/featured_bottom_navigation_scope.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

const _barKey = ValueKey('workspace-bottom-navigation');
const _contentKey = ValueKey('workspace-primary-content');
const _sidebarKey = ValueKey('workspace-side-navigation');
const _listKey = ValueKey('scroll-test-list');

void main() {
  for (final location in ['/', '/?channel=dynamic', '/me']) {
    testWidgets('vertical scrolling hides and restores the bar at $location', (
      tester,
    ) async {
      _size(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pumpShell(tester, location, body: (_) => _list(scroll));

      final bar = find.byKey(_barKey);
      final content = find.byKey(_contentKey);
      final height = tester.getSize(content).height;
      final barHeight = tester.getSize(bar).height;
      final safeBottom = tester.getBottomLeft(bar).dy;
      final list = find.byKey(_listKey);
      final retained = tester.element(list);
      expect(safeBottom, 776);

      await tester.drag(list, const Offset(140, -10));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);

      unawaited(
        scroll.animateTo(
          480,
          duration: const Duration(milliseconds: 120),
          curve: Curves.linear,
        ),
      );
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);

      await tester.fling(list, const Offset(0, -180), 1000);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      expect(tester.getSize(content).height, height + barHeight);
      expect(tester.getBottomLeft(content).dy, safeBottom);
      expect(tester.element(list), same(retained));
      expect(scroll.offset, greaterThan(480));

      await tester.drag(list, const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(bar.hitTestable(), findsOneWidget);
      expect(tester.getSize(content).height, height);
      expect(tester.element(list), same(retained));
    });
  }

  testWidgets('keyboard, routes, and sidebar changes restore navigation', (
    tester,
  ) async {
    _size(tester);
    final router = await _pumpShell(tester, '/', body: (_) => _list(null));
    final bar = find.byKey(_barKey);
    final list = find.byKey(_listKey);

    Future<void> hide() async {
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    }

    await hide();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();
    expect(bar, findsNothing);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(bar.hitTestable(), findsOneWidget);

    await hide();
    router.go('/me');
    await tester.pumpAndSettle();
    expect(bar.hitTestable(), findsOneWidget);

    await hide();
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(_sidebarKey), findsOneWidget);
    expect(bar, findsNothing);
    await tester.drag(list, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.byKey(_sidebarKey), findsOneWidget);

    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    expect(bar.hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-bottom-home')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'plain vertical wheel scrolls content and can reveal at the top',
    (tester) async {
      _size(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pumpShell(tester, '/me', body: (_) => _list(scroll));
      final bar = find.byKey(_barKey);
      final list = find.byKey(_listKey);

      await _wheel(tester, list, const Offset(120, 10));
      expect(bar.hitTestable(), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _wheel(tester, list, const Offset(0, 120));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(bar.hitTestable(), findsOneWidget);

      await _wheel(tester, list, const Offset(0, 120));
      expect(bar, findsNothing);
      expect(scroll.offset, greaterThan(0));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      await _wheel(tester, list, const Offset(0, -120));
      expect(bar.hitTestable(), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'featured reserves navigation space only on manual toggles',
    (tester) async {
      _size(tester);
      final pages = PageController();
      addTearDown(pages.dispose);
      final router = await _pumpShell(
        tester,
        '/featured',
        body: (location) => location.path != '/featured'
            ? _list(null)
            : PageView.builder(
                controller: pages,
                scrollDirection: Axis.vertical,
                itemCount: 3,
                itemBuilder: (_, index) => Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent ||
                        event.scrollDelta.dy == 0) {
                      return;
                    }
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (_) {
                        final target =
                            pages.page!.round() +
                            event.scrollDelta.dy.sign.toInt();
                        if (target < 0 || target >= 3) return;
                        unawaited(
                          pages.animateToPage(
                            target,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                          ),
                        );
                      },
                    );
                  },
                  child: Material(
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(child: Text('第 $index 条')),
                        const Align(
                          alignment: Alignment.bottomRight,
                          child: FeaturedBottomNavigationToggle(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      );
      final bar = find.byKey(_barKey);
      final pager = find.byType(PageView);
      final viewport = pages.position.viewportDimension;
      final barHeight = tester.getSize(bar).height;
      final barTop = tester.getTopLeft(bar).dy;
      final gesture = await tester.startGesture(tester.getCenter(pager));
      await gesture.moveBy(const Offset(0, -380));
      await tester.pump(const Duration(milliseconds: 72));
      expect(pages.page, inExclusiveRange(0.0, 1.0));
      expect(pages.position.viewportDimension, viewport);
      expect(bar.hitTestable(), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(bar.hitTestable(), findsOneWidget);
      expect(pages.position.viewportDimension, viewport);

      await _wheel(tester, pager, const Offset(0, -120), settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(pages.page, inExclusiveRange(0.0, 1.0));
      expect(bar.hitTestable(), findsOneWidget);
      expect(pages.position.viewportDimension, viewport);
      await tester.pumpAndSettle();
      expect(pages.page, 0);

      await tester.tap(find.byTooltip('收起底栏'));
      await tester.pump();
      expect(pages.position.viewportDimension, viewport + barHeight);
      expect(tester.getTopLeft(bar).dy, barTop);
      await tester.pump(const Duration(milliseconds: 70));
      expect(
        tester.getTopLeft(bar).dy,
        inExclusiveRange(barTop, barTop + barHeight),
      );
      expect(bar.hitTestable(), findsNothing);
      expect(pages.position.viewportDimension, viewport + barHeight);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);

      await _wheel(tester, pager, const Offset(0, 120));
      expect(pages.page, 1);
      expect(bar, findsNothing);
      await tester.drag(pager, const Offset(0, 430));
      await tester.pumpAndSettle();
      expect(pages.page, 0);
      expect(bar, findsNothing);
      expect(pages.position.viewportDimension, viewport + barHeight);

      await tester.tap(find.byTooltip('展开底栏'));
      await tester.pump();
      expect(pages.position.viewportDimension, viewport);
      await tester.pump(const Duration(milliseconds: 70));
      expect(
        tester.getTopLeft(bar).dy,
        inExclusiveRange(barTop, barTop + barHeight),
      );
      expect(bar.hitTestable(), findsNothing);
      expect(pages.position.viewportDimension, viewport);
      await tester.pumpAndSettle();
      expect(bar.hitTestable(), findsOneWidget);

      await tester.tap(find.byTooltip('收起底栏'));
      await tester.pumpAndSettle();
      router.go('/me');
      await tester.pumpAndSettle();
      expect(bar.hitTestable(), findsOneWidget);
      router.go('/featured');
      await tester.pumpAndSettle();
      expect(bar.hitTestable(), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );
}

void _size(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 800);
  tester.view.display.size = const Size(390, 800);
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.reset);
  addTearDown(tester.view.display.resetSize);
}

Widget _list(ScrollController? scroll) => ListView.builder(
  key: _listKey,
  controller: scroll,
  itemCount: 80,
  itemExtent: 48,
  itemBuilder: (_, index) => Center(child: Text('第 $index 项')),
);

Future<GoRouter> _pumpShell(
  WidgetTester tester,
  String location, {
  required Widget Function(Uri) body,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, state, child) => BiliAppShell(
          location: state.uri.toString(),
          navigationMode: WorkspaceNavigationMode.singlePage,
          pageBuilder: (_, tab) => body(tab.location),
          child: child,
        ),
        routes: [
          for (final path in ['/', '/me', '/featured'])
            GoRoute(path: path, builder: (_, _) => const SizedBox()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      scrollBehavior: const SmoothScrollBehavior(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _wheel(
  WidgetTester tester,
  Finder area,
  Offset delta, {
  bool settle = true,
}) async {
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(area),
      scrollDelta: delta,
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
