import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final (width, barMode, prefix) in [
    (390.0, NavigationBarMode.automatic, 'workspace-bottom'),
    (1280.0, NavigationBarMode.bottom, 'workspace-bottom'),
    (1280.0, NavigationBarMode.automatic, 'workspace-nav'),
  ]) {
    for (final navigationMode in WorkspaceNavigationMode.values) {
      testWidgets(
        'primary destinations remain reachable from grouped routes at $width with $barMode in $navigationMode',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.display.size = Size(width, 900);
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.display.resetSize);
          addTearDown(tester.view.resetPhysicalSize);
          final router = GoRouter(
            initialLocation: '/history',
            routes: [
              ShellRoute(
                builder: (context, state, child) => BiliAppShell(
                  location: state.uri.toString(),
                  navigationMode: navigationMode,
                  navigationBarMode: barMode,
                  pageBuilder: (_, tab) => TextField(
                    key: ValueKey('draft-${tab.id}-${tab.location.path}'),
                  ),
                  child: child,
                ),
                routes: [
                  for (final path in [
                    '/',
                    '/me',
                    '/history',
                    '/search',
                    '/settings',
                  ])
                    GoRoute(path: path, builder: (_, _) => const SizedBox()),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            MaterialApp.router(theme: BiliTheme.light(), routerConfig: router),
          );
          await tester.pumpAndSettle();

          Future<void> select(String section) async {
            await tester.tap(find.byKey(ValueKey('$prefix-$section')));
            await tester.pumpAndSettle();
          }

          for (final location in [
            '/history',
            '/?channel=watchLater',
            '/?channel=favorites',
          ]) {
            router.go(location);
            await tester.pumpAndSettle();
            await select('mine');
            expect(
              router.routeInformationProvider.value.uri.path,
              '/me',
              reason: location,
            );
          }

          router.go('/search?q=cat');
          await tester.pumpAndSettle();
          await select('home');
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(
            router
                .routeInformationProvider
                .value
                .uri
                .queryParameters['channel'],
            'recommended',
          );

          if (prefix == 'workspace-bottom') {
            for (final (location, section) in [
              ('/me?section=favorites&tab=home', 'mine'),
              ('/?channel=popular&section=每周必看&tab=home', 'home'),
              ('/?channel=videoDynamic&tab=home', 'dynamic'),
              ('/settings?section=appearance&tab=home', 'settings'),
            ]) {
              router.go(location);
              await tester.pumpAndSettle();
              final draft = find.byKey(
                ValueKey('draft-home-${Uri.parse(location).path}'),
              );
              await tester.enterText(draft, 'retained draft');
              final element = tester.element(draft);
              final uri = router.routeInformationProvider.value.uri;
              var navigations = 0;
              void onNavigate() => navigations++;
              router.routeInformationProvider.addListener(onNavigate);
              await select(section);
              await select(section);
              router.routeInformationProvider.removeListener(onNavigate);
              expect(navigations, 0, reason: location);
              expect(router.routeInformationProvider.value.uri, uri);
              expect(tester.element(draft), same(element));
              expect(find.text('retained draft'), findsOneWidget);
            }
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.windows,
        }),
      );
    }
  }
}
