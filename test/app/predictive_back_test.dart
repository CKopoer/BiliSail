import 'dart:async';

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/core/presentation/page_back_scope.dart';
import 'package:bilisail/core/presentation/predictive_back_region.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';
import '../support/system_back_gesture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final view = binding.platformDispatcher.views.single;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(390, 844);
    addTearDown(view.resetDevicePixelRatio);
    addTearDown(view.resetPhysicalSize);
  });

  for (final mode in WorkspaceNavigationMode.values) {
    for (final target in ['/video/A', '/user/42']) {
      testWidgets(
        'My keeps its own chrome through Back from $target in $mode',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final router = _router(
            mode: mode,
            accountBuilder: (_) =>
                const SizedBox(key: ValueKey('test-account-avatar')),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          router.go('/me');
          await tester.pumpAndSettle();
          final mine = tester.element(find.text('page /me'));
          final mineBounds = tester.getRect(find.text('page /me'));
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          router.go(target);
          await tester.pumpAndSettle();
          expect(await systemBackGesture(tester, 'startBackGesture'), isTrue);
          await systemBackGesture(
            tester,
            'updateBackGestureProgress',
            progress: 0.5,
          );
          await tester.pumpAndSettle();
          expect(tester.element(find.text('page /me')), same(mine));
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('test-account-avatar')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          await systemBackGesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/me');
          expect(tester.element(find.text('page /me')), same(mine));
          expect(tester.getRect(find.text('page /me')), mineBounds);
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  testWidgets('media history UI stays within the shared 16 page limit', (
    tester,
  ) async {
    final disposed = <String>[];
    final router = _router(
      builder: (_, tab) => _PageProbe(tab: tab, disposed: disposed),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final home = tester.element(find.text('page /'));
    for (var visit = 0; visit < 22; visit++) {
      router.go('/video/video-$visit');
      await tester.pumpAndSettle();
      expect(
        find.byType(_PageProbe, skipOffstage: false).evaluate().length,
        lessThanOrEqualTo(WorkspaceTabs.maximumTabs),
      );
      expect(home.mounted, isTrue);
    }
    await systemBackGesture(tester, 'startBackGesture');
    await tester.pump();
    expect(find.text('page /video/video-20'), findsOneWidget);
    await systemBackGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/video/video-21');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final mode in WorkspaceNavigationMode.values) {
    for (final (size, ratio, inset, enabled) in const [
      (Size(390, 844), 1.0, 0.0, true),
      (Size(599, 844), 2.0, 0.0, true),
      (Size(600, 844), 1.0, 0.0, false),
      (Size(844, 390), 1.0, 0.0, false),
      (Size(1280, 800), 2.0, 0.0, false),
      (Size(1600, 1000), 1.0, 0.0, false),
      (Size(630, 844), 2.0, 16.0, true),
      (Size(632, 844), 2.0, 16.0, false),
    ]) {
      for (final edge in SwipeEdge.values) {
        testWidgets(
          'predictive Back matches bottom navigation at $size DPR=$ratio '
          'inset=$inset in $mode from $edge',
          (tester) async {
            tester.view.devicePixelRatio = ratio;
            tester.view.physicalSize = size * ratio;
            tester.view.padding = FakeViewPadding(
              left: inset * ratio,
              right: inset * ratio,
            );
            addTearDown(tester.view.resetPadding);
            final router = _router(
              mode: mode,
              builder: (_, tab) => _PageProbe(tab: tab, disposed: []),
            );
            addTearDown(router.dispose);
            await tester.pumpWidget(InputTestApp.router(routerConfig: router));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('workspace-bottom-navigation')),
              enabled ? findsOneWidget : findsNothing,
            );
            router.go('/video/A');
            await tester.pumpAndSettle();
            final video = find.byKey(const ValueKey('page-surface-/video/A'));
            final original = tester.getRect(video);
            expect(
              await systemBackGesture(tester, 'startBackGesture', edge: edge),
              enabled,
            );
            await systemBackGesture(
              tester,
              'updateBackGestureProgress',
              progress: 0.5,
              edge: edge,
            );
            await tester.pump();
            expect(
              find.byKey(const ValueKey('page-surface-/')),
              enabled ? findsOneWidget : findsNothing,
            );
            expect(tester.getRect(video), enabled ? isNot(original) : original);
            await systemBackGesture(tester, 'cancelBackGesture');
            await tester.pumpAndSettle();
            expect(router.routeInformationProvider.value.uri.path, '/video/A');
            expect(tester.getRect(video), original);
            await systemBackGesture(tester, 'startBackGesture', edge: edge);
            await systemBackGesture(tester, 'commitBackGesture');
            await tester.pumpAndSettle();
            expect(router.routeInformationProvider.value.uri.path, '/');
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
          variant: TargetPlatformVariant.only(TargetPlatform.android),
        );
      }
    }
  }

  testWidgets('resizing disables a pending preview without replacing pages', (
    tester,
  ) async {
    final router = _router(
      builder: (_, tab) => _PageProbe(tab: tab, disposed: []),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/video/A');
    await tester.pumpAndSettle();
    final video = find.byKey(const ValueKey('page-surface-/video/A'));
    final element = tester.element(video);
    expect(await systemBackGesture(tester, 'startBackGesture'), isTrue);
    await systemBackGesture(tester, 'updateBackGestureProgress', progress: 0.5);
    await tester.pump();
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/video/A');
    expect(tester.element(video), same(element));
    expect(find.byKey(const ValueKey('page-surface-/')), findsNothing);
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'cancelBackGesture');
    tester.view.physicalSize = const Size(599, 844);
    await tester.pumpAndSettle();
    expect(tester.element(video), same(element));
    expect(await systemBackGesture(tester, 'startBackGesture'), isTrue);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final size in const [Size(390, 844), Size(599, 844), Size(599, 390)]) {
    for (final edge in SwipeEdge.values) {
      testWidgets(
        'video Back keeps two full-size pages adjacent at $size from $edge',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final disposed = <String>[];
          final router = _router(
            builder: (_, tab) => _PageProbe(tab: tab, disposed: disposed),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          router.go('/video/A');
          await tester.pumpAndSettle();
          final video = find.byKey(const ValueKey('page-surface-/video/A'));
          final previous = find.byKey(const ValueKey('page-surface-/'));
          final original = tester.getRect(video);
          Finder frame(Finder content) =>
              find.ancestor(of: content, matching: find.byType(Scaffold)).first;
          final frameBounds = tester.getRect(frame(video));
          expect(
            frameBounds,
            tester.getRect(find.byType(PredictiveBackRegion)),
          );
          final videoElement = tester.element(video);
          final direction = edge == SwipeEdge.left ? 1.0 : -1.0;
          await systemBackGesture(tester, 'startBackGesture', edge: edge);
          await tester.pump();
          for (final progress in [0.2, 0.5, 0.8, 0.3]) {
            await systemBackGesture(
              tester,
              'updateBackGestureProgress',
              progress: progress,
              edge: edge,
            );
            await tester.pump();
            final outgoing = tester.getRect(frame(video));
            final incoming = tester.getRect(frame(previous));
            for (final rect in [outgoing, incoming]) {
              expect(rect.width, closeTo(frameBounds.width, 0.001));
              expect(rect.height, closeTo(frameBounds.height, 0.001));
            }
            expect(outgoing.top, frameBounds.top);
            expect(incoming.top, frameBounds.top);
            expect(
              outgoing.left,
              closeTo(
                frameBounds.left + direction * frameBounds.width * progress,
                0.001,
              ),
            );
            if (edge == SwipeEdge.left) {
              expect(incoming.right, closeTo(outgoing.left, 0.001));
            } else {
              expect(incoming.left, closeTo(outgoing.right, 0.001));
            }
            expect(disposed, isEmpty);
            expect(router.routeInformationProvider.value.uri.path, '/video/A');
          }
          final clipping = find.ancestor(
            of: video,
            matching: find.byType(ClipRect),
          );
          expect(clipping, findsWidgets);
          expect(tester.getRect(clipping.last), frameBounds);
          await systemBackGesture(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(tester.element(video), same(videoElement));
          expect(tester.getRect(video), original);
          expect(previous, findsNothing);
          expect(disposed, isEmpty);
          await systemBackGesture(tester, 'startBackGesture', edge: edge);
          await systemBackGesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(disposed, ['tab-1']);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets('Android confirmed exit waits for cleanup in $mode', (
      tester,
    ) async {
      final cleanup = Completer<void>();
      var cleanupCalls = 0;
      var nativePops = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') nativePops++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final router = _router(
        mode: mode,
        onExitRequested: () {
          cleanupCalls++;
          return cleanup.future;
        },
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cleanupCalls, 0);
      expect(nativePops, 0);

      if (mode == WorkspaceNavigationMode.dualTabs) {
        router.go('/video/A');
        await tester.pumpAndSettle();
        router.go('/');
        await tester.pumpAndSettle();
        expect(find.text('page /video/A'), findsNothing);
        expect(find.text('page /video/A', skipOffstage: false), findsOneWidget);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();
      expect(cleanupCalls, 1);
      expect(nativePops, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('退出哔帆？'), findsNothing);
      expect(cleanupCalls, 1);
      cleanup.complete();
      await tester.pumpAndSettle();
      expect(nativePops, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final mode in WorkspaceNavigationMode.values) {
    for (final edge in SwipeEdge.values) {
      testWidgets(
        'predictive back cancels then commits once in $mode from $edge',
        (tester) async {
          final disposed = <String>[];
          final builds = <String, int>{};
          final router = _router(
            mode: mode,
            builder: (_, tab) => _PageProbe(
              key: ValueKey(tab.id),
              tab: tab,
              disposed: disposed,
              builds: builds,
            ),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          router.go('/search');
          await tester.pumpAndSettle();
          final current = tester.element(find.text('page /search'));
          final origin = tester.getTopLeft(find.text('page /search'));

          expect(
            await systemBackGesture(tester, 'startBackGesture', edge: edge),
            isTrue,
          );
          await tester.pump();
          expect(find.text('page /'), findsOneWidget);
          expect(
            WorkspaceActivity.isActive(tester.element(find.text('page /'))),
            isFalse,
          );
          final beforeTicks = Map.of(builds);
          for (final progress in [0.2, 0.4, 0.6]) {
            await systemBackGesture(
              tester,
              'updateBackGestureProgress',
              progress: progress,
              edge: edge,
            );
            await tester.pump();
          }
          expect(builds, beforeTicks);
          final moved = tester.getTopLeft(find.text('page /search'));
          expect(moved, isNot(origin));
          expect(router.routeInformationProvider.value.uri.path, '/search');
          expect(disposed, isEmpty);
          await systemBackGesture(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(tester.element(find.text('page /search')), same(current));
          expect(tester.getTopLeft(find.text('page /search')), origin);
          expect(find.text('page /'), findsNothing);
          expect(disposed, isEmpty);

          await systemBackGesture(tester, 'startBackGesture', edge: edge);
          await tester.pump();
          await systemBackGesture(
            tester,
            'updateBackGestureProgress',
            progress: 0.7,
            edge: edge,
          );
          await systemBackGesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(find.text('page /'), findsOneWidget);
          expect(
            disposed,
            mode != WorkspaceNavigationMode.multipleTabs ? ['tab-1'] : isEmpty,
          );
          expect(find.text('退出哔帆？'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  testWidgets(
    'media history preview does not replace the retained player before commit',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        builder: (_, tab) => _PageProbe(tab: tab, disposed: disposed),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/video/A');
      await tester.pumpAndSettle();
      final pageA = tester.element(find.text('page /video/A'));
      router.go('/video/B');
      await tester.pumpAndSettle();
      final player = tester.element(find.text('page /video/B'));
      await systemBackGesture(tester, 'startBackGesture');
      await tester.pump();
      expect(find.text('返回 A'), findsNothing);
      expect(tester.element(find.text('page /video/A')), same(pageA));
      expect(tester.element(find.text('page /video/B')), same(player));
      expect(disposed, isEmpty);
      await systemBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(tester.element(find.text('page /video/A')), same(pageA));
      expect(disposed, ['tab-1']);
      await systemBackGesture(tester, 'startBackGesture');
      await tester.pump();
      await systemBackGesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(disposed, ['tab-1']);
      await systemBackGesture(tester, 'startBackGesture');
      await systemBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(disposed, ['tab-1', 'tab-1']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('root exit, page-local Back and modals retain their priority', (
    tester,
  ) async {
    final localBack = ValueNotifier(true);
    addTearDown(localBack.dispose);
    final router = _router(
      builder: (_, tab) => ValueListenableBuilder(
        valueListenable: localBack,
        builder: (_, enabled, _) => PageBackHandler(
          enabled: !tab.isRoot && enabled,
          onBack: () {
            localBack.value = false;
            return true;
          },
          child: Text('page ${tab.location.path}'),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('退出哔帆？'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    router.go('/search');
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(localBack.value, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/search');
    final dialog = showAppDialog<void>(
      context: tester.element(find.text('page /search')),
      builder: (_) => const AlertDialog(content: Text('modal')),
    );
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    await dialog;
    expect(find.text('modal'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/search');
    final fullscreen = Navigator.of(tester.element(find.text('page /search')))
        .push<void>(
          RawDialogRoute<void>(
            barrierDismissible: false,
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                const Dialog.fullscreen(child: Text('fullscreen')),
          ),
        );
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    await fullscreen;
    expect(find.text('fullscreen'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/search');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final interrupt in ['route', 'modal', 'keyboard']) {
    testWidgets('$interrupt change invalidates a pending gesture', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/search');
      await tester.pumpAndSettle();
      await systemBackGesture(tester, 'startBackGesture');
      await tester.pump();
      await systemBackGesture(
        tester,
        'updateBackGestureProgress',
        progress: 0.5,
      );
      await tester.pump();
      if (interrupt == 'route') {
        router.go('/user/42');
      } else if (interrupt == 'modal') {
        showAppDialog<void>(
          context: tester.element(find.text('page /search')),
          builder: (_) => const AlertDialog(content: Text('new modal')),
        );
      } else {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
      }
      await tester.pumpAndSettle();
      await systemBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        interrupt == 'route' ? '/user/42' : '/search',
      );
      if (interrupt == 'modal') expect(find.text('new modal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
  testWidgets('reduced animation keeps geometry and commits Back', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/search');
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('page /search'));
    await systemBackGesture(tester, 'startBackGesture');
    await systemBackGesture(tester, 'updateBackGestureProgress', progress: 0.7);
    await tester.pump();
    expect(tester.getRect(find.text('page /search')), rect);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('navigation during completion discards the old commit', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/search');
    await tester.pumpAndSettle();
    await systemBackGesture(tester, 'startBackGesture');
    await tester.pump();
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pump(const Duration(milliseconds: 40));
    router.go('/user/42');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

GoRouter _router({
  WorkspaceNavigationMode mode = WorkspaceNavigationMode.dualTabs,
  WorkspacePageBuilder? builder,
  Future<void> Function()? onExitRequested,
  WidgetBuilder? accountBuilder,
}) => GoRouter(
  observers: [],
  routes: [
    ShellRoute(
      observers: [],
      builder: (context, state, child) => BiliAppShell(
        location: state.uri.toString(),
        navigationMode: mode,
        onExitRequested: onExitRequested,
        accountBuilder: accountBuilder,
        pageBuilder: builder ?? (_, tab) => Text('page ${tab.location.path}'),
        child: child,
      ),
      routes: [
        for (final path in [
          '/',
          '/me',
          '/search',
          '/user/:mid',
          '/video/:bvid',
        ])
          GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    ),
  ],
);

class _PageProbe extends StatefulWidget {
  const _PageProbe({
    super.key,
    required this.tab,
    required this.disposed,
    this.builds,
  });
  final WorkspaceTab tab;
  final List<String> disposed;
  final Map<String, int>? builds;

  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe> {
  @override
  Widget build(BuildContext context) {
    final builds = widget.builds;
    if (builds != null) {
      builds.update(widget.tab.id, (n) => n + 1, ifAbsent: () => 1);
    }
    return ColoredBox(
      key: ValueKey('page-surface-${widget.tab.location.path}'),
      color: Colors.white,
      child: Center(child: Text('page ${widget.tab.location.path}')),
    );
  }

  @override
  void dispose() {
    widget.disposed.add(widget.tab.id);
    super.dispose();
  }
}
