import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/scroll_floating_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_dock_navi/liquid_dock_navi.dart';

/// The dock mounts /history as its own page while `sectionForLocation` still
/// resolves it to the 我的 section, so selection and re-tap guards can diverge.
GoRouter _router(
  String initialLocation,
  Widget Function(WorkspaceTab tab) page,
) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => BiliAppShell(
        location: state.uri.toString(),
        pageBuilder: (context, tab) => page(tab),
        child: child,
      ),
      routes: [
        for (final path in [
          '/',
          '/history',
          '/downloads',
          '/messages',
          '/me',
          '/settings',
        ])
          GoRoute(
            path: path,
            builder: (context, state) => const SizedBox.shrink(),
          ),
      ],
    ),
  ],
);

void _usePhoneWindow(WidgetTester tester, {double bottomInset = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  if (bottomInset > 0) {
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('every dock entry switches away from history', (tester) async {
    _usePhoneWindow(tester);
    final router = _router(
      '/history',
      (tab) => Text('page ${tab.location.path}'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    LiquidDockNavi dock() =>
        tester.widget<LiquidDockNavi>(find.byType(LiquidDockNavi));
    int indexFor(String label) =>
        dock().items.indexWhere((item) => item.label == label);
    Uri path() => router.routeInformationProvider.value.uri;

    expect(path().path, '/history');
    expect(dock().currentIndex, indexFor('历史'));

    // 历史 resolves to the 我的 section, so this tap used to be swallowed by
    // the section-equality guard and leave the workspace on the history page.
    await tester.tap(
      find.descendant(
        of: find.byType(LiquidDockNavi),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();
    expect(path().path, '/me');
    expect(dock().currentIndex, indexFor('我的'));

    for (final entry in ['首页', '动态', '历史', '下载', '设置']) {
      await tester.tap(
        find.descendant(
          of: find.byType(LiquidDockNavi),
          matching: find.text(entry),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        dock().currentIndex,
        indexFor(entry),
        reason: 'tapping $entry after 我的',
      );
    }
    expect(path().path, '/settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated history switches stay on the fixed root tab', (
    tester,
  ) async {
    _usePhoneWindow(tester);
    final router = _router(
      '/',
      (tab) => Text('page ${tab.id} ${tab.location.path}'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    Future<void> tapDock(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(LiquidDockNavi),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    String shownPage() => tester
        .widgetList<Text>(find.textContaining('page '))
        .map((widget) => widget.data!)
        .single;

    // 历史 used to activate a second tab (tab-1) while every other primary
    // entry rewrites the root one, so the page you saw depended on which tab
    // identity the last trip had left selected.
    for (var trip = 0; trip < 3; trip++) {
      await tapDock('历史');
      expect(shownPage(), 'page home /history', reason: 'trip $trip 历史');
      await tapDock('我的');
      expect(shownPage(), 'page home /me', reason: 'trip $trip 我的');
      await tapDock('下载');
      expect(shownPage(), 'page home /downloads', reason: 'trip $trip 下载');
    }
    await tapDock('历史');
    expect(shownPage(), 'page home /history');
    expect(
      tester.widget<LiquidDockNavi>(find.byType(LiquidDockNavi)).currentIndex,
      tester
          .widget<LiquidDockNavi>(find.byType(LiquidDockNavi))
          .items
          .indexWhere((item) => item.label == '历史'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating refresh and top buttons clear the dock band', (
    tester,
  ) async {
    // 24 px system inset plus the dock's own 52 + 8 band.
    _usePhoneWindow(tester, bottomInset: 24);
    final router = _router(
      '/',
      (tab) => PagedScrollViewport(
        key: ValueKey(tab.location),
        active: true,
        canLoadMore: false,
        contentVersion: tab.location,
        onLoadMore: () async {},
        onRefresh: () async {},
        builder: (controller) => CustomScrollView(
          controller: controller,
          physics: const ClampingScrollPhysics(),
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 3000))],
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final actions = find.byType(ScrollFloatingActions);
    expect(actions, findsOneWidget);
    // Scroll so the "top" button appears under the refresh button.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final dockTop = tester.getRect(find.byType(LiquidDockNavi)).top;
    final actionsRect = tester.getRect(actions);
    expect(
      actionsRect.bottom,
      lessThanOrEqualTo(dockTop),
      reason: 'floating column overlaps the glass dock band',
    );
    // The reserve must not shove the column arbitrarily high either.
    expect(actionsRect.bottom, greaterThan(dockTop - 40));
    expect(tester.takeException(), isNull);
  });
}
