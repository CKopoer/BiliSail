import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/detached_window_fake.dart';

void main() {
  testWidgets(
    'macOS browser swipe closes browsing pages and retains playback',
    (tester) async {
      final fixture = _WindowedWorkspace(
        tester,
        platform: TargetPlatform.macOS,
      );
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      fixture.router.go('/search');
      await tester.pumpAndSettle();
      final browsing = tester.element(_page('tab-1'));
      fixture.router.go('/user/42');
      await tester.pumpAndSettle();
      final profile = tester.element(_page('tab-2'));
      fixture.router.go('/video/A');
      await tester.pumpAndSettle();
      fixture.router.go('/pgc/42');
      await tester.pumpAndSettle();
      final player = tester.element(_page('tab-3'));

      Future<void> back(String id) async {
        final page = tester.element(_page(id));
        final view = View.of(page);
        final drag = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await drag.panZoomStart(tester.getCenter(_page(id)), view: view);
        await drag.moveBy(const Offset(150, 0), view: view);
        await drag.up(view: view);
        await tester.pumpAndSettle();
      }

      // The active route is playback, but this gesture belongs to the browser.
      await back('tab-2');
      expect(fixture.router.routeInformationProvider.value.uri.path, '/search');
      expect(profile.mounted, isFalse);
      expect(tester.element(_page('tab-1')), same(browsing));
      expect(tester.element(_page('tab-3')), same(player));
      await back('tab-1');
      expect(fixture.router.routeInformationProvider.value.uri.path, '/');
      expect(browsing.mounted, isFalse);
      await back('home');
      expect(fixture.router.routeInformationProvider.value.uri.path, '/');
      expect(tester.element(_page('tab-3')), same(player));
      expect(fixture.tab(tester, 'tab-3').location.path, '/pgc/42');
      // Browser gestures never consume the detached player's media history.
      await back('tab-3');
      expect(fixture.tab(tester, 'tab-3').location.path, '/video/A');
      expect(tester.element(_page('tab-3')), same(player));
      expect(fixture.windows.creationCount, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('macOS trackpad Back stays in its detached playback view', (
    tester,
  ) async {
    final fixture = _WindowedWorkspace(tester, platform: TargetPlatform.macOS);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app);
    await tester.pumpAndSettle();
    fixture.router.go('/video/A');
    await tester.pumpAndSettle();
    final player = tester.element(_page('tab-1'));
    final browser = tester.element(_page('home'));
    fixture.router.go('/pgc/42');
    await tester.pumpAndSettle();
    final view = View.of(player);
    Future<void> back({double distance = 150}) async {
      final drag = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      final origin = tester.getCenter(_page('tab-1'));
      await drag.panZoomStart(origin, view: view);
      await drag.moveBy(Offset(distance, 0), view: view);
      await drag.up(view: view);
      await tester.pumpAndSettle();
    }

    await back(distance: 50);
    expect(fixture.tab(tester, 'tab-1').location.path, '/pgc/42');
    await back();
    expect(fixture.tab(tester, 'tab-1').location.path, '/video/A');
    expect(tester.element(_page('tab-1')), same(player));
    expect(tester.element(_page('home')), same(browser));
    expect(fixture.windows.creationCount, 1);
    await back();
    expect(_page('tab-1'), findsNothing);
    expect(tester.element(_page('home')), same(browser));
    expect(fixture.disposedPages, contains('tab-1'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets(
      'wide return raises the retained detached playback window on $platform',
      (tester) async {
        final fixture = _WindowedWorkspace(tester);
        addTearDown(fixture.dispose);
        final returnToPlayback = find.byKey(
          const ValueKey('workspace-return-to-playback'),
        );
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();
        expect(returnToPlayback, findsOneWidget);
        expect(tester.widget<IconButton>(returnToPlayback).onPressed, isNull);
        fixture.router.go('/video/BV1234567890');
        await tester.pumpAndSettle();
        final playback = tester.element(_page('tab-1'));
        final view = View.of(playback);
        final window = fixture.windows.lastWindow!;
        // The browser can still show the return button while the route already
        // selects playback, so repeated presses must also raise its window.
        for (var index = 0; index < 2; index++) {
          final activations = window.activationCount;
          await tester.tap(returnToPlayback);
          await tester.pumpAndSettle();
          expect(window.activationCount, activations + 1);
        }
        await tester.tap(find.byKey(const ValueKey('workspace-nav-dynamic')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('workspace-sidebar-toggle')),
        );
        await tester.pumpAndSettle();
        final activations = window.activationCount;
        await tester.tap(returnToPlayback);
        await tester.pumpAndSettle();
        expect(window.activationCount, activations + 1);
        expect(fixture.windows.creationCount, 1);
        expect(tester.element(_page('tab-1')), same(playback));
        expect(View.of(playback), same(view));
        expect(fixture.disposedPages, isEmpty);
        window.requestClose();
        await tester.pumpAndSettle();
        expect(returnToPlayback, findsOneWidget);
        expect(tester.widget<IconButton>(returnToPlayback).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'player Home focuses the browser while preserving the detached playback view',
    (tester) async {
      final fixture = _WindowedWorkspace(tester);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      fixture.router.go('/user/123');
      await tester.pumpAndSettle();
      fixture.router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      final playback = tester.element(_page('tab-2'));
      final view = View.of(playback);
      final window = fixture.windows.lastWindow;
      await tester.tap(find.byKey(const ValueKey('test-window-home')));
      await tester.pumpAndSettle();
      expect(fixture.browserActivations, 1);
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/user/123',
      );
      expect(tester.element(_page('tab-2')), same(playback));
      expect(View.of(playback), same(view));
      expect(fixture.windows.lastWindow, same(window));
      expect(fixture.disposedPages, isEmpty);
      expect(WorkspaceActivity.isActive(playback), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'macOS unprepared engine keeps dual playback in the main window safely',
    (tester) async {
      final fixture = _WindowedWorkspace(
        tester,
        customCaption: false,
        checkWindowSupport: true,
      );
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('increment-home')));
      await tester.pump();
      final browser = tester.element(_page('home'));
      final browserScope = _scope(browser);

      fixture.router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      final playback = tester.element(_page('tab-1'));
      final playbackScope = _scope(playback);
      await tester.tap(find.byKey(const ValueKey('increment-tab-1')));
      await tester.pump();
      expect(View.of(playback).viewId, tester.view.viewId);
      expect(_page('home'), findsNothing);
      expect(tester.element(_page('home', skipOffstage: false)), same(browser));
      expect(WorkspaceActivity.isActive(browser), isFalse);

      fixture.router.go('/pgc/42');
      await tester.pumpAndSettle();
      expect(tester.element(_page('tab-1')), same(playback));
      expect(fixture.tab(tester, 'tab-1').location.path, '/pgc/42');
      await tester.tap(find.byTooltip('返回上一视频'));
      await tester.pumpAndSettle();
      expect(fixture.tab(tester, 'tab-1').location.path, '/video/BV1234567890');
      expect(tester.element(_page('tab-1')), same(playback));
      expect(_scope(playback), same(playbackScope));
      expect(playbackScope.read(_counterProvider), 1);

      await tester.tap(find.byTooltip('关闭播放'));
      await tester.pumpAndSettle();
      expect(tester.element(_page('home')), same(browser));
      expect(_scope(browser), same(browserScope));
      expect(browserScope.read(_counterProvider), 1);
      expect(fixture.disposedPages, ['tab-1']);
      expect(fixture.windows.creationCount, 0);
      expect(fixture.errors, isEmpty);
      _expectViews(tester, [tester.view.viewId]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'macOS dual profile retains a back entry without a custom caption',
    (tester) async {
      await _prepareMacOSWindowing(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = _WindowedWorkspace(
        tester,
        customCaption: false,
        checkWindowSupport: true,
      );
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      final browser = tester.element(_page('home'));
      fixture.router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      final playback = tester.element(_page('tab-1'));
      final window = fixture.windows.lastWindow!;
      for (final width in [390.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 844);
        fixture.router.go('/user/123');
        await tester.pumpAndSettle();
        final header = find.byKey(
          const ValueKey('workspace-profile-back-header'),
        );
        expect(header, findsOneWidget);
        expect(View.of(tester.element(header)).viewId, tester.view.viewId);
        expect(tester.getSize(header).height, 42);
        expect(
          find.byKey(const ValueKey('workspace-back')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
        expect(
          find.byKey(const ValueKey('workspace-common-tools')),
          findsNothing,
        );
        _expectViews(tester, [tester.view.viewId, window.viewId]);
        await tester.tap(find.byKey(const ValueKey('workspace-back')));
        await tester.pumpAndSettle();
        expect(tester.element(_page('home')), same(browser));
        expect(tester.element(_page('tab-1')), same(playback));
        expect(fixture.router.routeInformationProvider.value.uri.path, '/');
        expect(fixture.windows.creationCount, 1);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'desktop dual keeps browsing visible while every media kind reuses one view',
    (tester) async {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _prepareMacOSWindowing(tester);
      }
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = _WindowedWorkspace(tester, checkWindowSupport: true);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();

      final browser = tester.element(_page('home'));
      final browserScope = _scope(browser);
      await tester.tap(find.byKey(const ValueKey('increment-home')));
      await tester.pump();
      expect(browserScope.read(_counterProvider), 1);
      expect(
        fixture.tab(tester, 'home').location.queryParameters['channel'],
        'popular',
      );
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('dual-window-caption')))
            .height,
        44,
      );
      expect(find.byType(View), findsOneWidget);

      fixture.router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      final playback = tester.element(_page('tab-1'));
      final playbackScope = _scope(playback);
      final window = fixture.windows.lastWindow!;
      _expectViews(tester, [tester.view.viewId, window.viewId]);
      expect(View.of(browser).viewId, tester.view.viewId);
      expect(View.of(playback).viewId, window.viewId);
      expect(WorkspaceActivity.isActive(browser), isTrue);
      expect(WorkspaceActivity.isActive(playback), isTrue);
      expect(WorkspacePlaybackSelection.of(browser), 'tab-1');
      expect(tester.element(_page('home')), same(browser));
      expect(_scope(browser), same(browserScope));
      expect(
        fixture.tab(tester, 'home').location.queryParameters['channel'],
        'popular',
      );

      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: window.viewId,
          state: ViewFocusState.focused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/video/BV1234567890',
      );
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.focused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.router.routeInformationProvider.value.uri.path, '/');
      expect(tester.element(_page('tab-1')), same(playback));
      final activations = window.activationCount;
      fixture.router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      expect(window.activationCount, activations + 1);
      expect(fixture.windows.creationCount, 1);
      expect(tester.element(_page('tab-1')), same(playback));

      fixture.router.go('/search');
      await tester.pumpAndSettle();
      expect(fixture.tab(tester, 'tab-2').location.path, '/search');
      expect(
        View.of(tester.element(_page('tab-2'))).viewId,
        tester.view.viewId,
      );
      expect(fixture.tab(tester, 'tab-1').location.path, '/video/BV1234567890');
      expect(tester.element(_page('tab-1')), same(playback));
      await tester.tap(find.byKey(const ValueKey('workspace-nav-dynamic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('channel-videoDynamic')));
      await tester.pumpAndSettle();
      expect(tester.element(_page('home')), same(browser));
      expect(_scope(browser), same(browserScope));
      expect(browserScope.read(_counterProvider), 1);
      expect(
        fixture.tab(tester, 'home').location.queryParameters['channel'],
        'videoDynamic',
      );
      expect(
        find.byKey(const ValueKey('workspace-common-tools')),
        findsOneWidget,
      );
      expect(fixture.tab(tester, 'tab-1').location.path, '/video/BV1234567890');

      for (final location in ['/pgc/ep42', '/live/200', '/offline/task-1']) {
        fixture.router.go(location);
        await tester.pumpAndSettle();
        expect(fixture.windows.creationCount, 1);
        expect(fixture.windows.lastWindow, same(window));
        expect(window.disposed, isFalse);
        _expectViews(tester, [tester.view.viewId, window.viewId]);
        expect(tester.element(_page('tab-1')), same(playback));
        expect(_scope(playback), same(playbackScope));
        expect(fixture.tab(tester, 'tab-1').location.path, location);
        expect(tester.element(_page('home')), same(browser));
        expect(
          fixture.tab(tester, 'home').location.queryParameters['channel'],
          'videoDynamic',
        );
        expect(WorkspaceActivity.isActive(browser), isTrue);
        expect(tester.takeException(), isNull);
      }

      for (final previous in [
        '/live/200',
        '/pgc/ep42',
        '/video/BV1234567890',
      ]) {
        await tester.tap(find.byKey(const ValueKey('test-window-back')));
        await tester.pumpAndSettle();
        expect(fixture.tab(tester, 'tab-1').location.path, previous);
        expect(tester.element(_page('tab-1')), same(playback));
        expect(tester.element(_page('home')), same(browser));
        expect(fixture.windows.creationCount, 1);
      }
      await tester.tap(find.byKey(const ValueKey('test-window-back')));
      await tester.pumpAndSettle();
      expect(fixture.browserActivations, 1);
      expect(fixture.router.routeInformationProvider.value.uri.path, '/');
      expect(window.disposed, isTrue);
      expect(fixture.disposedPages, contains('tab-1'));
      expect(_page('tab-1', skipOffstage: false), findsNothing);
      _expectViews(tester, [tester.view.viewId]);
      expect(tester.element(_page('home')), same(browser));
      expect(_scope(browser), same(browserScope));
      expect(browserScope.read(_counterProvider), 1);
      expect(
        fixture.tab(tester, 'home').location.queryParameters['channel'],
        'videoDynamic',
      );
      expect(fixture.errors, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'mode switches move playback between views without replacing pages or provider scopes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = _WindowedWorkspace(tester);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('increment-home')));
      await tester.pump();
      final browser = tester.element(_page('home'));
      final browserScope = _scope(browser);
      fixture.router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('increment-tab-1')));
      await tester.pump();
      final playback = tester.element(_page('tab-1'));
      final playbackScope = _scope(playback);

      for (final mode in [
        WorkspaceNavigationMode.multipleTabs,
        WorkspaceNavigationMode.dualTabs,
        WorkspaceNavigationMode.multipleTabs,
        WorkspaceNavigationMode.dualTabs,
      ]) {
        final previousWindow = fixture.windows.lastWindow!;
        fixture.mode.value = mode;
        await tester.pumpAndSettle();
        expect(
          tester.element(_page('home', skipOffstage: false)),
          same(browser),
        );
        expect(tester.element(_page('tab-1')), same(playback));
        expect(_scope(browser), same(browserScope));
        expect(_scope(playback), same(playbackScope));
        expect(browserScope.read(_counterProvider), 1);
        expect(playbackScope.read(_counterProvider), 1);
        expect(fixture.disposedPages, isEmpty);
        if (mode == WorkspaceNavigationMode.dualTabs) {
          final window = fixture.windows.lastWindow!;
          expect(window.disposed, isFalse);
          _expectViews(tester, [tester.view.viewId, window.viewId]);
          expect(View.of(playback).viewId, window.viewId);
          expect(_page('home'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-tab-strip')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('dual-window-caption')),
            findsOneWidget,
          );
        } else {
          expect(previousWindow.disposed, isTrue);
          _expectViews(tester, [tester.view.viewId]);
          expect(View.of(playback).viewId, tester.view.viewId);
          expect(_page('home'), findsNothing);
          expect(
            find.byKey(const ValueKey('workspace-tab-strip')),
            mode == WorkspaceNavigationMode.multipleTabs
                ? findsOneWidget
                : findsNothing,
          );
        }
        expect(tester.takeException(), isNull, reason: '$mode');
      }
      expect(fixture.windows.creationCount, 3);
      expect(fixture.errors, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Finder _page(String id, {bool skipOffstage = true}) =>
    find.byKey(ValueKey('probe-$id'), skipOffstage: skipOffstage);

Future<void> _prepareMacOSWindowing(WidgetTester tester) async {
  const channel = MethodChannel('bilisail/application_window');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (_) async => true,
  );
  await DetachedPlaybackWindow.prepareMacOSWindowing();
  addTearDown(() async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => false,
    );
    await expectLater(
      DetachedPlaybackWindow.prepareMacOSWindowing(),
      throwsUnsupportedError,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
}

ProviderContainer _scope(Element element) =>
    ProviderScope.containerOf(element, listen: false);

void _expectViews(WidgetTester tester, List<int> ids) => expect(
  tester.widgetList<View>(find.byType(View)).map((view) => view.view.viewId),
  unorderedEquals(ids),
);

final _counterProvider = NotifierProvider<_ProbeCounter, int>(
  _ProbeCounter.new,
);

class _ProbeCounter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

class _WindowedWorkspace {
  _WindowedWorkspace(
    WidgetTester tester, {
    this.customCaption = true,
    this.checkWindowSupport = false,
    this.platform = TargetPlatform.windows,
  }) : windows = FakeDetachedWindowFactory(tester.view);

  final bool customCaption;
  final bool checkWindowSupport;
  final TargetPlatform platform;
  final FakeDetachedWindowFactory windows;
  final mode = ValueNotifier(WorkspaceNavigationMode.dualTabs);
  final disposedPages = <String>[];
  final errors = <Object>[];
  int browserActivations = 0;

  late final router = GoRouter(
    initialLocation: '/?channel=popular',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ValueListenableBuilder(
          valueListenable: mode,
          builder: (context, navigationMode, _) => BiliAppShell(
            location: state.uri.toString(),
            navigationMode: navigationMode,
            onActivateBrowser: () => browserActivations++,
            windowControlsBuilder: customCaption
                ? (_) => const SizedBox(
                    key: ValueKey('main-window-controls'),
                    width: 120,
                  )
                : null,
            pageBuilder: (_, tab) => ProviderScope(
              key: ValueKey('scope-${tab.id}'),
              overrides: [_counterProvider.overrideWith(_ProbeCounter.new)],
              child: _PageProbe(
                key: ValueKey('probe-${tab.id}'),
                tab: tab,
                onDispose: disposedPages.add,
              ),
            ),
            playbackWindowBuilder:
                checkWindowSupport && !DetachedPlaybackWindow.isSupported
                ? null
                : (
                    context, {
                    required child,
                    required playback,
                    required keepPlaybackMounted,
                    required activationToken,
                    required onClose,
                    required onBack,
                    required onHome,
                    required onError,
                  }) => DesktopPlaybackWindow(
                    keepPlaybackMounted: keepPlaybackMounted,
                    windowFactory: windows.call,
                    activationToken: activationToken,
                    onCloseRequested: onClose,
                    onError: (error) {
                      errors.add(error);
                      onError(error);
                    },
                    playback: playback == null
                        ? null
                        : MaterialApp(
                            theme: Theme.of(context),
                            home: Scaffold(
                              body: Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        key: const ValueKey('test-window-back'),
                                        onPressed: onBack,
                                        icon: const Icon(Icons.arrow_back),
                                      ),
                                      IconButton(
                                        key: const ValueKey('test-window-home'),
                                        onPressed: onHome,
                                        icon: const Icon(Icons.home_outlined),
                                      ),
                                      IconButton(
                                        key: const ValueKey(
                                          'test-window-close',
                                        ),
                                        onPressed: onClose,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                  Expanded(child: playback),
                                ],
                              ),
                            ),
                          ),
                    child: child,
                  ),
            child: child,
          ),
        ),
        routes: [
          for (final path in [
            '/',
            '/search',
            '/user/:id',
            '/video/:id',
            '/pgc/:id',
            '/live/:id',
            '/offline/:id',
          ])
            GoRoute(path: path, builder: (_, state) => const SizedBox.shrink()),
        ],
      ),
    ],
  );

  Widget get app => ProviderScope(
    child: MaterialApp.router(
      theme: ThemeData(platform: platform),
      routerConfig: router,
    ),
  );

  WorkspaceTab tab(WidgetTester tester, String id) =>
      tester.widget<_PageProbe>(_page(id, skipOffstage: false)).tab;

  void dispose() {
    router.dispose();
    mode.dispose();
  }
}

class _PageProbe extends ConsumerStatefulWidget {
  const _PageProbe({super.key, required this.tab, required this.onDispose});

  final WorkspaceTab tab;
  final ValueChanged<String> onDispose;

  @override
  ConsumerState<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends ConsumerState<_PageProbe> {
  @override
  void dispose() {
    widget.onDispose(widget.tab.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${widget.tab.id} ${widget.tab.location}'),
        Text('count ${ref.watch(_counterProvider)}'),
        ElevatedButton(
          key: ValueKey('increment-${widget.tab.id}'),
          onPressed: () => ref.read(_counterProvider.notifier).increment(),
          child: const Text('increment'),
        ),
      ],
    ),
  );
}
