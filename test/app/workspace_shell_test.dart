import '../support/input_test_app.dart';

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/home_channel_swipe.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/playback_navigation.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_controller.dart'
    hide SearchController;
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final returnToPlayback = find.byKey(
    const ValueKey('workspace-return-to-playback'),
  );
  for (final mode in WorkspaceNavigationMode.values) {
    for (final caption in [false, true]) {
      _workspaceTestWidgets(
        'wide return to playback retains the page in $mode, caption=$caption',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 800);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final disposed = <String>[];
          final router = _router(
            (_, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
            navigationMode: mode,
            customCaption: caption,
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(returnToPlayback, findsOneWidget);
          expect(tester.widget<IconButton>(returnToPlayback).onPressed, isNull);
          await tester.tap(returnToPlayback);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          router.go('/video/BV1234567890');
          await tester.pumpAndSettle();
          final playback = tester.element(find.byType(_CounterPage));
          await tester.tap(find.text('count 0'));
          await tester.pump();
          expect(returnToPlayback, findsNothing);
          for (final section in ['home', 'dynamic', 'live']) {
            await tester.tap(find.byKey(ValueKey('workspace-nav-$section')));
            await tester.pumpAndSettle();
            expect(returnToPlayback, findsOneWidget);
            expect(
              tester.widget<IconButton>(returnToPlayback).onPressed,
              isNotNull,
            );
            expect(find.byTooltip('回到播放页'), findsOneWidget);
            expect(tester.getTopLeft(returnToPlayback).dy, lessThan(44));
            expect(find.byType(FloatingActionButton), findsNothing);
            await tester.tap(returnToPlayback);
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              '/video/BV1234567890',
            );
            expect(tester.element(find.byType(_CounterPage)), same(playback));
            expect(find.text('count 1'), findsOneWidget);
          }
          await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('workspace-sidebar-toggle')),
          );
          await tester.pumpAndSettle();
          expect(returnToPlayback.hitTestable(), findsOneWidget);
          tester.view.physicalSize = const Size(599, 800);
          await tester.pumpAndSettle();
          expect(returnToPlayback, findsNothing);
          tester.view.physicalSize = const Size(600, 800);
          await tester.pumpAndSettle();
          expect(returnToPlayback.hitTestable(), findsOneWidget);
          await tester.tap(returnToPlayback);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(_CounterPage)), same(playback));
          expect(disposed, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  _workspaceTestWidgets(
    'dual return keeps the floating entry when safe area makes the layout narrow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(620, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = _router(
        (_, tab) => Text('page ${tab.location.path}'),
        navigationMode: WorkspaceNavigationMode.dualTabs,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.symmetric(horizontal: 20)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/video/A');
      await tester.pumpAndSettle();
      router.go('/');
      await tester.pumpAndSettle();
      expect(returnToPlayback, findsNothing);
      expect(find.byTooltip('返回播放'), findsOneWidget);
      await tester.tap(find.byTooltip('返回播放'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(tester.takeException(), isNull);
    },
  );

  _workspaceTestWidgets(
    'wide return uses the latest surviving playback visit',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = _router((_, tab) => Text('page ${tab.location.path}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      for (final path in ['/video/A', '/pgc/42', '/live/12', '/offline/task']) {
        router.go(path);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      for (final entry in [
        ('tab-1', '/video/A'),
        ('tab-4', '/offline/task'),
        ('tab-3', '/live/12'),
        ('tab-2', '/pgc/42'),
      ]) {
        await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
        await tester.pumpAndSettle();
        await tester.tap(returnToPlayback);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, entry.$2);
        await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('close-workspace-tab-${entry.$1}')),
        );
        await tester.pumpAndSettle();
      }
      expect(returnToPlayback, findsOneWidget);
      expect(tester.widget<IconButton>(returnToPlayback).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'player Home follows $mode and releases only single-page media',
      (tester) async {
        final disposed = <String>[];
        final router = _router(
          (context, tab) => Column(
            children: [
              _CounterPage(tab: tab, onDispose: disposed.add),
              if (tab.isPlayback)
                TextButton(
                  onPressed: () => PlaybackNavigation.maybeOf(
                    tester.element(find.text('player Home')),
                  )?.onHome(),
                  child: const Text('player Home'),
                ),
            ],
          ),
          navigationMode: mode,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        router.go('/search?q=cat');
        await tester.pumpAndSettle();
        await tester.tap(find.text('count 0'));
        await tester.pump();
        router.go('/video/BV1234567890');
        await tester.pumpAndSettle();
        router.go('/video/BV0987654321');
        await tester.pumpAndSettle();
        await tester.tap(find.text('player Home'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          mode == WorkspaceNavigationMode.multipleTabs ? '/' : '/search',
        );
        if (mode == WorkspaceNavigationMode.singlePage) {
          expect(disposed, containsAll(['tab-2', 'tab-3']));
          expect(find.text('player Home', skipOffstage: false), findsNothing);
          expect(find.text('count 1'), findsOneWidget);
        } else {
          expect(disposed, isEmpty);
          expect(find.text('player Home', skipOffstage: false), findsWidgets);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  _workspaceTestWidgets(
    'single page shortcuts keep navigation and pop visits',
    (tester) async {
      final router = _router(
        (_, tab) => Text('page ${tab.location.path}'),
        navigationMode: WorkspaceNavigationMode.singlePage,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      router.go('/user/42');
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      await _shortcut(tester, LogicalKeyboardKey.tab);
      expect(router.routeInformationProvider.value.uri.path, '/user/42');
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/video/BV1234567890',
      );
      expect(find.text('page /user/42', skipOffstage: false), findsNothing);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(
        find.text('page /video/BV1234567890', skipOffstage: false),
        findsNothing,
      );
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'Android root Back requires explicit exit and modal dismissal wins in $mode',
      (tester) async {
        final platformCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            platformCalls.add(call);
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
          (_, tab) => Text('page ${tab.location.path}'),
          navigationMode: mode,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        int exits() => platformCalls
            .where((call) => call.method == 'SystemNavigator.pop')
            .length;
        for (final root in ['/', '/me', '/settings', '/downloads']) {
          router.go(root);
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('退出哔帆？'), findsOneWidget);
          expect(exits(), 0);
          expect(router.routeInformationProvider.value.uri.path, root);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(exits(), 0);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(exits(), 0);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('退出'));
        await tester.pumpAndSettle();
        expect(exits(), 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  _workspaceTestWidgets(
    'home strip follows paging before the channel route commits',
    (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = _router(
        (context, tab) => HomeChannelSwipe(
          channel:
              HomeChannel.values
                  .where(
                    (channel) =>
                        channel.name == tab.location.queryParameters['channel'],
                  )
                  .firstOrNull ??
              HomeChannel.recommended,
          onChanged: (channel) =>
              context.go('/?channel=${channel.name}&tab=${tab.id}'),
          pageBuilder: (_, channel, active) =>
              SizedBox.expand(key: ValueKey('home-page-${channel.name}')),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final outgoing = find.byKey(const ValueKey('channel-recommended'));
      final incoming = find.byKey(const ValueKey('channel-popular'));
      Color? color(Finder tab) =>
          tester.widget<TextButton>(tab).style?.foregroundColor?.resolve({});
      final selectedColor = color(outgoing);
      final inactiveColor = color(incoming);
      final sourceElement = tester.element(outgoing);
      final headerRect = tester.getRect(
        find.byKey(const ValueKey('home-channel-strip')),
      );
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('home-channel-swipe'))),
      );
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump();
      await tester.pump();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['channel'],
        isNull,
      );
      expect(color(outgoing), isNot(selectedColor));
      expect(color(incoming), isNot(inactiveColor));
      expect(tester.element(outgoing), same(sourceElement));
      expect(
        tester.getRect(find.byKey(const ValueKey('home-channel-strip'))),
        headerRect,
      );
      await drag.moveBy(const Offset(-140, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['channel'],
        'popular',
      );
      expect(color(incoming), selectedColor);
      expect(tester.element(outgoing), same(sourceElement));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    for (final mode in WorkspaceNavigationMode.values) {
      _workspaceTestWidgets('$platform workspace chrome in $mode', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final mobile =
            platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS;
        final dual = mode == WorkspaceNavigationMode.dualTabs;
        final single = mode == WorkspaceNavigationMode.singlePage;
        final router = _router(
          (_, tab) =>
              SizedBox.expand(key: ValueKey('body-${tab.location.path}')),
          navigationMode: mode,
          customCaption: true,
          accountBuilder: (_) => const SizedBox(width: 34, height: 34),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        var playbackCreated = false;
        for (final width in [420.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 850);
          for (final location in [
            '/',
            '/video/BV1234567890',
            '/user/123',
            '/search?q=test',
            '/settings',
            '/history',
          ]) {
            router.go(location);
            await tester.pumpAndSettle();
            final playback = location.startsWith('/video/');
            final profile = location.startsWith('/user/');
            final playbackHeader =
                dual &&
                mobile &&
                platform != TargetPlatform.android &&
                playback;
            final body = tester.element(
              find.byKey(ValueKey('body-${Uri.parse(location).path}')),
            );
            expect(
              PlaybackNavigation.maybeOf(body)?.showInPlayer,
              platform == TargetPlatform.android && (single || dual),
            );
            playbackCreated |= playback;
            expect(
              find.byKey(const ValueKey('workspace-tab-strip')),
              mode == WorkspaceNavigationMode.multipleTabs
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('dual-window-caption')),
              (dual || single) && !mobile ? findsOneWidget : findsNothing,
            );
            if ((dual || single) && !mobile) {
              expect(
                tester
                    .getSize(find.byKey(const ValueKey('dual-window-caption')))
                    .height,
                44,
              );
            }
            final hasBack =
                (dual || single) &&
                !const ['/', '/settings'].contains(location) &&
                (!mobile ||
                    !playback ||
                    (single && platform == TargetPlatform.iOS));
            expect(
              find.byKey(const ValueKey('workspace-back')),
              hasBack ? findsOneWidget : findsNothing,
              reason: '$location width=$width',
            );
            expect(
              find.byTooltip('返回上一视频'),
              playbackHeader ? findsOneWidget : findsNothing,
            );
            expect(
              find.byTooltip('关闭播放'),
              playbackHeader ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('workspace-playback-home')),
              (single || dual) && platform != TargetPlatform.android && playback
                  ? findsOneWidget
                  : findsNothing,
            );
            if (platform == TargetPlatform.android && playback) {
              expect(
                find.byKey(const ValueKey('workspace-playback-header')),
                findsNothing,
              );
            }
            expect(
              find.byTooltip('返回播放'),
              dual && playbackCreated && !playback && width < 600
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              returnToPlayback,
              !playback && width >= 600 ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('caption-controls')),
              mobile ? findsNothing : findsOneWidget,
            );
            if (location.startsWith('/video/') ||
                location.startsWith('/user/')) {
              final sidebarToolbar = find.byKey(
                const ValueKey('workspace-sidebar-toolbar'),
              );
              final sidebarToolbarHeight = sidebarToolbar.evaluate().isEmpty
                  ? 0
                  : tester.getSize(sidebarToolbar).height;
              expect(
                tester.getTopLeft(find.byKey(ValueKey('body-$location'))).dy,
                ((dual || single)
                        ? mobile
                              ? (playback
                                    ? (platform == TargetPlatform.android
                                          ? 0
                                          : 44)
                                    : profile
                                    ? 42
                                    : 0)
                              : 44
                        : !mobile
                        ? 44
                        : 42) +
                    sidebarToolbarHeight +
                    (width >= 600 ? 12 : 0),
              );
            }
            expect(tester.takeException(), isNull);
          }
        }
        router.go('/video/BV1234567890');
        await tester.pumpAndSettle();
        router.go('/user/123');
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          dual ? '/history' : '/video/BV1234567890',
        );
      }, variant: TargetPlatformVariant.only(platform));
    }
  }

  for (final mode in WorkspaceNavigationMode.values) {
    for (final (initial, entryWidth) in [
      ('/', 390.0),
      ('/', 1280.0),
      ('/?channel=dynamic', 390.0),
      ('/?channel=dynamic', 1280.0),
      ('/?channel=videoDynamic', 390.0),
      ('/?channel=videoDynamic', 1280.0),
    ]) {
      _workspaceTestWidgets(
        'dynamic entry preserves explicit and chosen channels from $initial at $entryWidth in $mode',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(entryWidth, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final disposed = <String>[];
          final navigationPrefix = entryWidth < 600
              ? 'workspace-bottom'
              : 'workspace-nav';
          final initialChannel =
              Uri.parse(initial).queryParameters['channel'] ?? 'dynamic';
          final chosenChannel = initialChannel == 'dynamic'
              ? 'videoDynamic'
              : 'dynamic';
          final router = _router(
            (_, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
            navigationMode: mode,
            initialLocation: initial,
            customCaption: true,
            accountBuilder: (_) => const Icon(Icons.account_circle),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          final root = tester.element(find.byType(_CounterPage));
          await tester.tap(find.text('count 0'));
          await tester.pump();
          if (initial != '/') {
            expect(
              router
                  .routeInformationProvider
                  .value
                  .uri
                  .queryParameters['channel'],
              initialChannel,
            );
            await tester.tap(find.byKey(ValueKey('$navigationPrefix-home')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(ValueKey('$navigationPrefix-dynamic')));
          await tester.pumpAndSettle();
          expect(
            router
                .routeInformationProvider
                .value
                .uri
                .queryParameters['channel'],
            initialChannel,
          );
          await tester.tap(find.byKey(ValueKey('channel-$chosenChannel')));
          await tester.pumpAndSettle();
          expect(
            router
                .routeInformationProvider
                .value
                .uri
                .queryParameters['channel'],
            chosenChannel,
          );
          await tester.tap(find.byKey(ValueKey('$navigationPrefix-home')));
          await tester.pumpAndSettle();
          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('workspace-bottom-dynamic')),
          );
          await tester.pumpAndSettle();
          expect(
            router
                .routeInformationProvider
                .value
                .uri
                .queryParameters['channel'],
            chosenChannel,
          );
          expect(find.byIcon(Icons.account_circle), findsNothing);
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          expect(tester.element(find.byType(_CounterPage)), same(root));
          expect(find.text('count 1'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-tab-tab-1')),
            findsNothing,
          );
          expect(disposed, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
    _workspaceTestWidgets(
      '$mode retains caption controls and drag navigation after resizing',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var windowDrags = 0;
        final router = _router(
          (_, tab) => SizedBox.expand(key: ValueKey('page-${tab.id}')),
          navigationMode: mode,
          customCaption: true,
          onWindowDrag: () => windowDrags++,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        final home = tester.element(find.byKey(const ValueKey('page-home')));
        for (final width in [420.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 850);
          router.go('/history');
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('caption-controls')),
            findsOneWidget,
          );
          expect(
            tester
                .getTopRight(find.byKey(const ValueKey('caption-controls')))
                .dx,
            width,
          );
          await tester.drag(
            find.byKey(const ValueKey('caption-drag-region')),
            const Offset(40, 0),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          await _back(tester);
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byKey(const ValueKey('page-home'))),
            same(home),
          );
          expect(tester.takeException(), isNull);
        }
        expect(windowDrags, 2);
      },
    );
  }

  _workspaceTestWidgets(
    'Android dual playback hides its header and closes through system back',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final disposed = <String>[];
      final router = _router(
        (_, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
        navigationMode: WorkspaceNavigationMode.dualTabs,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      await tester.pump();
      final browse = tester.element(find.byType(_CounterPage));
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
      expect(find.byTooltip('返回上一视频'), findsNothing);
      expect(find.byTooltip('关闭播放'), findsNothing);
      await tester.tap(find.text('count 0'));
      await tester.pump();
      final playback = tester.element(find.byType(_CounterPage));
      for (final size in const [
        Size(390, 844),
        Size(844, 390),
        Size(1080, 844),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.byType(_CounterPage), findsOneWidget);
        expect(
          find.byType(_CounterPage, skipOffstage: false),
          findsNWidgets(2),
        );
        expect(tester.element(find.byType(_CounterPage)), same(playback));
        expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
        expect(find.byTooltip('返回上一视频'), findsNothing);
        expect(find.byTooltip('关闭播放'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(390, 844);
      router.go('/');
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(_CounterPage)), same(browse));
      expect(find.text('count 1'), findsOneWidget);
      expect(find.byTooltip('返回上一视频'), findsNothing);
      await tester.tap(find.byTooltip('返回播放'));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(_CounterPage)), same(playback));
      expect(find.text('count 1'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(_CounterPage)), same(browse));
      expect(disposed, ['tab-1']);
      expect(find.byTooltip('返回播放'), findsNothing);
      expect(find.byTooltip('关闭播放'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  _workspaceTestWidgets(
    'window deactivation cancels repeats and requires fresh modifiers',
    (tester) async {
      final router = _router((_, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page home'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page home'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      // The Windows workaround clears modifiers on blur; a fresh press resumes
      // the shortcut instead of trusting the potentially stale framework cache.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
    },
  );
  _workspaceTestWidgets(
    'configured tab cycling repeats across page activation',
    (tester) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page home'), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    },
  );

  _workspaceTestWidgets(
    'Apple default tab commands dispatch in the workspace',
    (tester) async {
      final shortcuts = defaultShortcuts;
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: shortcuts,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(routerConfig: router, shortcuts: shortcuts),
      );
      await tester.pumpAndSettle();
      if (workspaceHeaderVisible) {
        expect(find.byTooltip('新建标签页（⌘ Command+T）'), findsOneWidget);
      }
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
      }
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      expect(find.text('page tab-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.iOS}),
  );
  for (final mode in [
    'custom',
    'master disabled',
    'action disabled',
    'unbound',
  ]) {
    _workspaceTestWidgets('tab cycling respects $mode configuration', (
      tester,
    ) async {
      var shortcuts = const ShortcutSettings.defaults().withKeys(
        ShortcutAction.nextTab,
        ['Alt+K'],
      );
      shortcuts = switch (mode) {
        'master disabled' => shortcuts.withEnabled(false),
        'action disabled' => shortcuts.withActionEnabled(
          ShortcutAction.nextTab,
          false,
        ),
        'unbound' => shortcuts.withKeys(ShortcutAction.nextTab, []),
        _ => shortcuts,
      };
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: shortcuts,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(routerConfig: router, shortcuts: shortcuts),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(
        find.text(mode == 'custom' ? 'page home' : 'page tab-1'),
        findsOneWidget,
      );
    });
  }

  _workspaceTestWidgets(
    'background page navigation updates its tab without selecting it',
    (tester) async {
      final navigation = <String, ValueChanged<Uri>>{};
      final router = _router(
        (_, tab) => Builder(
          builder: (context) {
            navigation[tab.id] = WorkspacePageNavigation.maybeOf(context)!
                .navigate;
            return Text('page ${tab.id} ${tab.location.path}');
          },
        ),
        initialLocation: '/video/BV1234567890?queue=fixture',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/search?q=still-reading');
      await tester.pumpAndSettle();
      navigation['tab-1']!(Uri.parse('/video/BV0987654321?queue=fixture'));
      await tester.pumpAndSettle();
      expect(find.text('page tab-2 /search'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/search');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['q'],
        'still-reading',
      );
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1 /video/BV0987654321'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.queryParameters['queue'],
        'fixture',
      );
      navigation['tab-1']!(Uri.parse('/video/BV1234567890?queue=fixture'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/video/BV1234567890',
      );
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _workspaceTestWidgets(
    'workspace back restores state without closing pages and handles system back',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
        navigationMode: WorkspaceNavigationMode.multipleTabs,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('workspace-search'))).dy,
        65,
      );
      expect(find.byKey(const ValueKey('new-workspace-tab')), findsOneWidget);
      await tester.tap(find.text('count 0'));
      router.go('/search?q=test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      await tester.pump();
      await tester.tap(find.text('count 1'));
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.text('count 2'), findsOneWidget);
      expect(disposed, isEmpty);
      expect(router.routeInformationProvider.value.uri.path, '/search');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
      expect(disposed, isEmpty);
      expect(find.byKey(const ValueKey('workspace-back')), findsNothing);
      expect(await router.routerDelegate.popRoute(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  _workspaceTestWidgets(
    'a dual deep link can close playback and modal back stays in the page',
    (tester) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        navigationMode: WorkspaceNavigationMode.dualTabs,
        initialLocation: '/video/BV1234567890',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('page tab-1'));
      final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('modal')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await dialog;
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    _workspaceTestWidgets(
      '$platform default mode is stable across window resizing',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(420, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final disposed = <String>[];
        final router = _router(
          (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
          navigationMode: null,
          customCaption: true,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.text('count 0'));
        router.go('/search?q=test');
        await tester.pumpAndSettle();
        await tester.tap(find.text('count 0'));
        await tester.pump();
        expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
        tester.view.physicalSize = const Size(1280, 850);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
        expect(find.text('count 1'), findsOneWidget);
        tester.view.physicalSize = const Size(420, 850);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
        expect(find.text('count 1'), findsOneWidget);
        expect(disposed, isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('count 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'live section header preserves the root and last section in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final disposed = <String>[];
        final router = _router(
          (_, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
          navigationMode: mode,
          initialLocation: '/?channel=live&section=我的关注',
          customCaption: true,
          accountBuilder: (_) => const Icon(Icons.account_circle),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        final root = tester.element(find.byType(_CounterPage));
        await tester.tap(find.text('count 0'));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('workspace-live-section-观看记录')),
        );
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.queryParameters['section'],
          '观看记录',
        );
        expect(
          router.routeInformationProvider.value.uri.queryParameters['tab'],
          'home',
        );
        expect(tester.element(find.byType(_CounterPage)), same(root));
        expect(find.byKey(const ValueKey('workspace-back')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-bottom-live')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('channel-live')));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.queryParameters['section'],
          '观看记录',
        );
        tester.view.physicalSize = const Size(1280, 844);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-live-section-观看记录')),
          findsOneWidget,
        );
        expect(tester.element(find.byType(_CounterPage)), same(root));
        expect(find.text('count 1'), findsOneWidget);
        expect(disposed, isEmpty);
        router.go('/?channel=live');
        await tester.pumpAndSettle();
        final recommended = find.byKey(
          const ValueKey('workspace-live-section-推荐直播'),
        );
        expect(
          tester
              .widget<TextButton>(recommended)
              .style
              ?.foregroundColor
              ?.resolve({}),
          Theme.of(tester.element(recommended)).colorScheme.primary,
        );
        await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-nav-live')));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.queryParameters['section'],
          '推荐直播',
        );
        expect(tester.element(find.byType(_CounterPage)), same(root));
        expect(tester.takeException(), isNull);
      },
    );
  }

  _workspaceTestWidgets(
    'multiple tabs can go back through visits without closing pages',
    (tester) async {
      final router = _router((_, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/search?q=test');
      await tester.pumpAndSettle();
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
      await tester.pumpAndSettle();
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.text('page tab-2'), findsOneWidget);
      await _back(tester);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [420.0, 1000.0]) {
    _workspaceTestWidgets(
      'home channel strip scrolls to its final tab using a mouse wheel at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final router = _router(
          (_, tab) =>
              Text('channel ${tab.location.queryParameters['channel']}'),
          navigationMode: WorkspaceNavigationMode.multipleTabs,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          InputTestApp.router(
            theme: ThemeData(platform: TargetPlatform.windows),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child ?? const SizedBox.shrink(),
            ),
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();
        final strip = find.byKey(const ValueKey('home-channel-strip'));
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(strip),
            scrollDelta: const Offset(0, 2000),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
        final favorites = find.byKey(const ValueKey('channel-categories'));
        expect(favorites.hitTestable(), findsOneWidget);
        await tester.tap(favorites);
        await tester.pumpAndSettle();
        expect(find.text('channel categories'), findsOneWidget);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(strip),
            scrollDelta: const Offset(0, -2000),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _workspaceTestWidgets(
    'keyboard closes tabs after a mouse click unfocuses search',
    (tester) async {
      final router = _router((context, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      for (var index = 0; index < 2; index++) {
        await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.focusNode.hasFocus, isTrue);
      await tester.tap(find.text('page tab-2'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(editor.focusNode.hasFocus, isFalse);

      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);
    },
  );

  for (final (name, settings) in [
    (
      'custom binding',
      const ShortcutSettings.defaults().withKeys(ShortcutAction.closeTab, [
        'Ctrl+Q',
      ]),
    ),
    (
      'disabled action',
      const ShortcutSettings.defaults().withActionEnabled(
        ShortcutAction.closeTab,
        false,
      ),
    ),
    (
      'disabled shortcuts',
      const ShortcutSettings.defaults().withEnabled(false),
    ),
    (
      'unbound action',
      const ShortcutSettings.defaults().withKeys(ShortcutAction.closeTab, []),
    ),
  ]) {
    _workspaceTestWidgets('unfocused workspace respects $name', (tester) async {
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        shortcuts: settings,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyQ);
      expect(
        find.text(
          settings.actionFor('Ctrl+Q') == ShortcutAction.closeTab
              ? 'page home'
              : 'page tab-1',
        ),
        findsOneWidget,
      );
    });
  }

  _workspaceTestWidgets(
    'new tabs respect editors and workspace commands respect modal routes',
    (tester) async {
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      await tester.tap(find.text('page tab-1'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      for (final requestFocus in [false, true]) {
        final context = tester.element(find.text('page tab-1'));
        final dialog = showDialog<void>(
          context: context,
          requestFocus: requestFocus,
          builder: (_) => const AlertDialog(content: Text('modal')),
        );
        await tester.pumpAndSettle();
        await _shortcut(tester, LogicalKeyboardKey.keyW);
        await _shortcut(tester, LogicalKeyboardKey.keyT);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        );
        await pointer.down(tester.getCenter(find.text('modal')));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-tab-tab-1')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
        Navigator.of(context, rootNavigator: true).pop();
        await dialog;
        await tester.pumpAndSettle();
      }
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);

      await tester.pumpWidget(const InputTestApp(home: Text('replacement')));
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('replacement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in WorkspaceNavigationMode.values) {
    for (final (key, button) in [
      ('MouseBack', kBackMouseButton),
      ('MouseForward', kForwardMouseButton),
    ]) {
      _workspaceTestWidgets('$key closes pages with editor focus in $mode', (
        tester,
      ) async {
        final router = _router(
          (_, tab) => Column(
            children: [
              Text('page ${tab.id}'),
              TextField(key: ValueKey('composer-${tab.id}')),
            ],
          ),
          navigationMode: mode,
          shortcuts: const ShortcutSettings.defaults().withKeys(
            ShortcutAction.closeTab,
            ['Ctrl+W', key],
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        router.go('/search?q=retained');
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('composer-tab-1')),
          'retained draft',
        );
        router.go('/history');
        await tester.pumpAndSettle();
        final composer = find.byKey(const ValueKey('composer-tab-2'));
        await tester.enterText(composer, 'current draft');
        await tester.pump();
        final editor = tester.widget<EditableText>(
          find.descendant(of: composer, matching: find.byType(EditableText)),
        );
        expect(editor.focusNode.hasFocus, isTrue);

        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: button,
        );
        await pointer.down(tester.getCenter(composer));
        await tester.pumpAndSettle();
        if (mode == WorkspaceNavigationMode.dualTabs) {
          // Closing the browsing slot is a no-op; explicit playback remains
          // closable using the same custom side-button binding.
          expect(find.text('page tab-2'), findsOneWidget);
          await pointer.up();
          router.go('/video/BV1234567890');
          await tester.pumpAndSettle();
          final playbackComposer = find.byKey(const ValueKey('composer-tab-3'));
          await tester.enterText(playbackComposer, 'video draft');
          await pointer.down(tester.getCenter(playbackComposer));
          await pointer.up();
          await tester.pumpAndSettle();
          expect(find.text('page tab-2'), findsOneWidget);
          expect(find.text('current draft'), findsOneWidget);
          expect(find.byKey(const ValueKey('composer-tab-3')), findsNothing);
          return;
        }
        expect(find.text('page tab-1'), findsOneWidget);
        expect(find.text('page tab-2'), findsNothing);
        expect(find.text('retained draft'), findsOneWidget);
        // Holding the side button across the rebuild must not close again.
        await pointer.moveTo(tester.getCenter(find.text('page tab-1')));
        await tester.pumpAndSettle();
        expect(find.text('page tab-1'), findsOneWidget);
        await pointer.up();

        final search = find.byKey(const ValueKey('workspace-search'));
        await tester.tap(search);
        await tester.pumpAndSettle();
        final searchEditor = tester.widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        );
        expect(searchEditor.focusNode.hasFocus, isTrue);
        await pointer.down(tester.getCenter(search));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(find.text('page home'), findsOneWidget);

        await pointer.down(tester.getCenter(find.text('page home')));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(find.text('page home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (action, key) in [
    (ShortcutAction.closeTab, 'W'),
    (ShortcutAction.closeTab, 'F8'),
    (ShortcutAction.newTab, 'MouseBack'),
  ]) {
    _workspaceTestWidgets('$action with $key still reserves editor input', (
      tester,
    ) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults()
            .withKeys(ShortcutAction.closeTab, ['Ctrl+W'])
            .withKeys(action, [key]),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('workspace-search'));
      await tester.enterText(search, 'draft');
      await tester.pump();
      if (key == 'MouseBack') {
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        );
        await pointer.down(tester.getCenter(search));
        await pointer.up();
      } else {
        await tester.sendKeyEvent(
          key == 'W' ? LogicalKeyboardKey.keyW : LogicalKeyboardKey.f8,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      expect(find.text('draft'), findsOneWidget);
    });
  }

  for (final enabled in [true, false]) {
    _workspaceTestWidgets(
      'mouse side key closes the active tab when enabled=$enabled',
      (tester) async {
        final router = _router(
          (context, tab) => Text('page ${tab.id}'),
          shortcuts: const ShortcutSettings.defaults().withActionEnabled(
            ShortcutAction.closeTab,
            enabled,
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('workspace-search'));
        await tester.tap(search);
        await tester.pumpAndSettle();
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        );
        await pointer.down(tester.getCenter(search));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(find.text(enabled ? 'page home' : 'page tab-1'), findsOneWidget);
        if (enabled) {
          await pointer.down(tester.getCenter(find.text('page home')));
          await pointer.up();
          await tester.pumpAndSettle();
          expect(find.text('page home'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'settings keep their category without tools or an extra tab in $mode',
      (tester) async {
        final router = _router(
          (context, tab) => Text(
            'page ${tab.id} ${tab.location.queryParameters['section'] ?? 'none'}',
          ),
          navigationMode: mode,
          accountBuilder: (_) => const Icon(Icons.account_circle),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        router.go('/settings');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('channel-recommended')), findsNothing);
        expect(
          find.byKey(const ValueKey('workspace-common-tools')),
          findsNothing,
        );
        expect(find.byIcon(Icons.account_circle), findsNothing);
        expect(
          find.byKey(const ValueKey('settings-category-strip')),
          findsNothing,
        );
        router.go('/settings?section=shortcuts');
        await tester.pumpAndSettle();
        expect(find.text('page home shortcuts'), findsOneWidget);
        expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('channel-recommended')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('workspace-nav-settings')));
        await tester.pumpAndSettle();
        expect(find.text('page home shortcuts'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workspace-common-tools')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
        router.go('/search?q=category-memory');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-nav-settings')));
        await tester.pumpAndSettle();
        expect(find.text('page home shortcuts'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workspace-common-tools')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    _workspaceTestWidgets(
      'root destinations select only their own entry and keep four narrow links in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final disposed = <String>[];
        final router = _router(
          (_, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
          navigationMode: mode,
          customCaption: true,
          accountBuilder: (_) => const Icon(Icons.account_circle),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        final root = tester.element(find.byType(_CounterPage));
        await tester.tap(find.text('count 0'));
        await tester.pump();
        for (final (path, selected) in [
          ('/messages', 'messages'),
          ('/downloads', 'downloads'),
          ('/settings', 'settings'),
          ('/me', 'mine'),
        ]) {
          tester.view.physicalSize = const Size(1280, 844);
          router.go(path);
          await tester.pumpAndSettle();
          for (final entry in [
            'home',
            'dynamic',
            'live',
            'mine',
            'messages',
            'downloads',
            'settings',
          ]) {
            final semantics = find.descendant(
              of: find.byKey(ValueKey('workspace-nav-$entry')),
              matching: find.byType(Semantics),
            );
            expect(
              tester
                  .widgetList<Semantics>(semantics)
                  .map((widget) => widget.properties.selected)
                  .whereType<bool>(),
              [entry == selected],
            );
          }
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          expect(find.byIcon(Icons.account_circle), findsNothing);
          expect(
            find.byKey(const ValueKey('workspace-tab-tab-1')),
            findsNothing,
          );
          expect(tester.element(find.byType(_CounterPage)), same(root));
          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpAndSettle();
          final bottom = find.byKey(
            const ValueKey('workspace-bottom-navigation'),
          );
          expect(tester.getSize(bottom).height, 52);
          if (selected == 'messages' || selected == 'downloads') {
            expect(find.byType(NavigationBar), findsNothing);
            final flags = tester
                .widgetList<Semantics>(
                  find.descendant(of: bottom, matching: find.byType(Semantics)),
                )
                .map((widget) => widget.properties.selected)
                .whereType<bool>();
            expect(flags, [false, false, false, false]);
          } else {
            expect(find.byType(NavigationBar), findsOneWidget);
          }
          expect(
            find.byKey(const ValueKey('workspace-bottom-live')),
            findsNothing,
          );
          for (final entry in ['home', 'dynamic', 'mine', 'settings']) {
            expect(
              find.byKey(ValueKey('workspace-bottom-$entry')).hitTestable(),
              findsOneWidget,
            );
          }
          expect(find.text('count 1'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: path);
        }
        expect(disposed, isEmpty);
      },
    );
  }
  _workspaceTestWidgets(
    'browse tabs preserve page state and dispose closed pages',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      expect(find.text('count 0'), findsOneWidget);
      await tester.tap(find.text('count 0'));
      await tester.pump();
      await tester.tap(find.text('count 1'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
      expect(disposed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('count 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
      expect(disposed, ['tab-1']);
      expect(
        find.byKey(const ValueKey('close-workspace-tab-home')),
        findsNothing,
      );
    },
  );

  _workspaceTestWidgets(
    'keyboard creates, cycles and closes tabs without closing home',
    (tester) async {
      final router = _router((context, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-2'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.tab);
      expect(find.text('page home'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.tab, shift: true);
      expect(find.text('page tab-2'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);
    },
  );

  _workspaceTestWidgets(
    'hidden video pages stay mounted until explicitly closed',
    (tester) async {
      final mounted = <String>{};
      final router = _router(
        (context, tab) => tab.isVideo
            ? _VideoOwner(id: tab.id, mountedOwners: mounted)
            : Text('page ${tab.id}'),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      expect(mounted, {'tab-1'});
      router.go('/video/BV0987654321');
      await tester.pumpAndSettle();
      expect(mounted, {'tab-1', 'tab-2'});
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(mounted, {'tab-1', 'tab-2'});
      await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
      await tester.pumpAndSettle();
      expect(mounted, {'tab-1', 'tab-2'});
      await tester.tap(find.byKey(const ValueKey('close-workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(mounted, {'tab-2'});
    },
  );

  _workspaceTestWidgets(
    'narrow caption controls and many tabs fit and selected tab is visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        customCaption: true,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 18; index++) {
        await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
        await tester.pumpAndSettle();
      }
      expect(find.text('page tab-15'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-tab-tab-15')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopRight(find.byKey(const ValueKey('caption-controls'))).dx,
        420,
      );
    },
  );
}

void _workspaceTestWidgets(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatformVariant? variant,
}) => testWidgets(
  description,
  callback,
  variant: variant ?? TargetPlatformVariant.only(TargetPlatform.windows),
);

GoRouter _router(
  WorkspacePageBuilder builder, {
  bool customCaption = false,
  WidgetBuilder? accountBuilder,
  VoidCallback? onWindowDrag,
  ShortcutSettings shortcuts = const ShortcutSettings.defaults(),
  WorkspaceNavigationMode? navigationMode =
      WorkspaceNavigationMode.multipleTabs,
  String initialLocation = '/',
}) => GoRouter(
  observers: [],
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      observers: [],
      builder: (context, state, child) => BiliAppShell(
        shortcuts: shortcuts,
        navigationMode: navigationMode,
        location: state.uri.toString(),
        accountBuilder: accountBuilder,
        pageBuilder: (context, tab) => tab.location.path == '/search'
            ? ProviderScope(
                overrides: [
                  searchRepositoryProvider.overrideWithValue(
                    _ShellSearchRepository(),
                  ),
                ],
                child: Builder(
                  builder: (context) =>
                      WorkspacePageHeader.wrap(context, builder(context, tab)),
                ),
              )
            : builder(context, tab),
        windowControlsBuilder: customCaption && workspaceHeaderVisible
            ? (_) => const SizedBox(
                key: ValueKey('caption-controls'),
                width: 138,
                height: 42,
              )
            : null,
        dragRegionBuilder: customCaption && workspaceHeaderVisible
            ? (_, child) => GestureDetector(
                key: const ValueKey('caption-drag-region'),
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => onWindowDrag?.call(),
                child: child,
              )
            : null,
        child: child,
      ),
      routes: [
        for (final path in [
          '/',
          '/video/:bvid',
          '/pgc/:id',
          '/live/:id',
          '/offline/:id',
          '/user/:mid',
          '/search',
          '/settings',
          '/history',
          '/messages',
          '/downloads',
          '/me',
        ])
          GoRoute(path: path, builder: (_, state) => const SizedBox.shrink()),
      ],
    ),
  ],
);

final class _ShellSearchRepository implements SearchRepository {
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) async => SearchPage(items: [], hasMore: false);
}

Future<void> _back(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('workspace-back'));
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
  } else {
    await tester.binding.handlePopRoute();
  }
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.tab, required this.onDispose});
  final WorkspaceTab tab;
  final ValueChanged<String> onDispose;
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int count = 0;
  @override
  void dispose() {
    widget.onDispose(widget.tab.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('count $count'),
    ),
  );
}

class _VideoOwner extends StatefulWidget {
  const _VideoOwner({required this.id, required this.mountedOwners});
  final String id;
  final Set<String> mountedOwners;
  @override
  State<_VideoOwner> createState() => _VideoOwnerState();
}

class _VideoOwnerState extends State<_VideoOwner> {
  @override
  void initState() {
    super.initState();
    widget.mountedOwners.add(widget.id);
  }

  @override
  void dispose() {
    widget.mountedOwners.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
