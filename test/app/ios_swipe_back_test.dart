import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/presentation/page_back_scope.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets('iOS edge Back follows workspace history in $mode', (
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
      final secondVideo = tester.element(find.text('page /video/B'));

      final drag = await tester.startGesture(const Offset(5, 350));
      await drag.moveBy(const Offset(500, 0));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/video/B');
      await drag.up();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(tester.element(find.text('page /video/A')), same(firstVideo));
      // Dual mode reuses its single playback slot when restoring media.
      expect(secondVideo.mounted, mode == WorkspaceNavigationMode.dualTabs);

      await _back(tester);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(firstVideo.mounted, isFalse);
      await _back(tester);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    });

    testWidgets('iOS page-local Back precedes navigation in $mode', (
      tester,
    ) async {
      var detail = true;
      final router = _router(
        mode: mode,
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
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in [
    WorkspaceNavigationMode.singlePage,
    WorkspaceNavigationMode.dualTabs,
  ]) {
    testWidgets('iOS returns from profile without recreating video in $mode', (
      tester,
    ) async {
      final router = _router(mode: mode);
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router));
      router.go('/video/A');
      await tester.pumpAndSettle();
      final video = tester.element(find.text('page /video/A'));
      router.go('/user/42');
      await tester.pumpAndSettle();
      await _back(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        mode == WorkspaceNavigationMode.singlePage ? '/video/A' : '/',
      );
      expect(
        tester.element(find.text('page /video/A', skipOffstage: false)),
        same(video),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('iOS modal and navigation changes cancel pending Back', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/video/A');
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(const Offset(5, 350));
    await drag.moveBy(const Offset(500, 0));
    await tester.pump();
    final dialog = showDialog<void>(
      context: tester.element(find.text('page /video/A')),
      builder: (_) => const AlertDialog(content: Text('modal')),
    );
    await tester.pumpAndSettle();
    await drag.up();
    await _back(tester);
    expect(find.text('modal'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/video/A');
    router.pop();
    await tester.pumpAndSettle();
    await dialog;

    final stale = await tester.startGesture(const Offset(5, 350));
    await stale.moveBy(const Offset(500, 0));
    router.go('/user/42');
    await tester.pumpAndSettle();
    await stale.up();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _back(WidgetTester tester) async {
  await tester.dragFrom(const Offset(5, 350), const Offset(500, 0));
  await tester.pumpAndSettle();
}

Widget _app(GoRouter router) => InputTestApp.router(
  routerConfig: router,
  theme: ThemeData(platform: TargetPlatform.iOS),
);

GoRouter _router({
  WorkspaceNavigationMode mode = WorkspaceNavigationMode.dualTabs,
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
        for (final path in ['/', '/video/:id', '/user/:id'])
          GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    ),
  ],
);
