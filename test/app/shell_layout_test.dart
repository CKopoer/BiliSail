import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_navigation.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in NavigationBarMode.values) {
    testWidgets(
      'mobile navigation uses the current unfolded display with $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.display.size = const Size(390, 844);
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.display.resetSize);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            theme: BiliTheme.light(),
            home: BiliAppShell(
              location: '/',
              navigationBarMode: mode,
              child: const SizedBox.expand(
                key: ValueKey('fold-retained-content'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final content = tester.element(
          find.byKey(const ValueKey('fold-retained-content')),
        );
        for (final (display, viewport, compact) in [
          (const Size(390, 844), const Size(390, 844), true),
          (const Size(844, 390), const Size(844, 390), true),
          (const Size(599, 900), const Size(599, 900), true),
          (const Size(600, 900), const Size(600, 900), false),
          (const Size(1200, 800), const Size(1200, 800), false),
          (const Size(1200, 800), const Size(599, 800), true),
          (const Size(800, 1200), const Size(800, 1200), false),
          (const Size(390, 844), const Size(390, 844), true),
        ]) {
          tester.view.display.size = display;
          tester.view.physicalSize = viewport;
          await tester.pumpAndSettle();
          final bottom = compact || mode == NavigationBarMode.bottom;
          expect(
            find.byKey(const ValueKey('workspace-bottom-navigation')),
            bottom ? findsOneWidget : findsNothing,
            reason: '$display $viewport',
          );
          expect(
            find.byKey(const ValueKey('workspace-nav-home')),
            bottom ? findsNothing : findsOneWidget,
            reason: '$display $viewport',
          );
          expect(
            find.byKey(const ValueKey('channel-live')),
            compact ? findsOneWidget : findsNothing,
          );
          expect(
            tester.element(find.byKey(const ValueKey('fold-retained-content'))),
            same(content),
          );
          expect(tester.takeException(), isNull);
        }
        tester.view.display.size = const Size(600, 900);
        tester.view.physicalSize = const Size(600, 900);
        tester.view.padding = const FakeViewPadding(left: 24, right: 24);
        addTearDown(tester.view.resetPadding);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-bottom-navigation')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('workspace-nav-home')), findsNothing);
        expect(find.byKey(const ValueKey('channel-live')), findsOneWidget);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'desktop navigation keeps responding to window width on a small display',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.display.size = const Size(844, 390);
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(
          home: BiliAppShell(location: '/', child: SizedBox.expand()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-bottom-navigation')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('workspace-nav-home')), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final dark in [false, true]) {
    testWidgets(
      'messages and downloads match normal bottom navigation in dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        for (final (width, scale, bottomPadding) in [
          (320.0, 1.0, 0.0),
          (390.0, 1.0, 34.0),
          (599.0, 2.0, 34.0),
        ]) {
          tester.view.physicalSize = Size(width, 844);
          tester.view.padding = FakeViewPadding(bottom: bottomPadding);
          tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
          Future<void> show(String location) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BiliTheme.dark() : BiliTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: BiliAppShell(
                  location: location,
                  navigationMode: WorkspaceNavigationMode.dualTabs,
                  child: const SizedBox.expand(),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          final bottom = find.byKey(
            const ValueKey('workspace-bottom-navigation'),
          );
          (Rect, Rect, TextStyle?) metrics(String section) {
            final destination = find.byKey(
              ValueKey('workspace-bottom-$section'),
            );
            final icon = find.descendant(
              of: destination,
              matching: find.byType(Icon),
            );
            final label = find.descendant(
              of: find.descendant(of: destination, matching: find.byType(Text)),
              matching: find.byType(RichText),
            );
            final origin = tester.getTopLeft(bottom);
            return (
              tester.getRect(icon).shift(-origin),
              tester.getRect(label).shift(-origin),
              tester.renderObject<RenderParagraph>(label).text.style,
            );
          }

          await show('/');
          final normalSize = tester.getSize(bottom);
          final normal = {
            for (final section in ['dynamic', 'mine', 'settings'])
              section: metrics(section),
          };
          await show('/settings');
          normal['home'] = metrics('home');
          for (final location in ['/messages', '/downloads']) {
            await show(location);
            expect(tester.getSize(bottom), normalSize);
            for (final entry in normal.entries) {
              final actual = metrics(entry.key);
              final expected = entry.value;
              final reason = '$location ${entry.key} width=$width scale=$scale';
              expect(actual.$1, expected.$1, reason: reason);
              expect(actual.$2, expected.$2, reason: reason);
              expect(actual.$3, expected.$3, reason: reason);
            }
            expect(tester.takeException(), isNull);
          }
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }),
    );
  }

  testWidgets(
    'narrow navigation has four destinations and wide keeps live separate',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: const BiliAppShell(
            navigationMode: WorkspaceNavigationMode.dualTabs,
            location: '/',
            child: SizedBox.expand(key: ValueKey('retained-content')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.element(
        find.byKey(const ValueKey('retained-content')),
      );
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        bar.destinations.whereType<NavigationDestination>().map(
          (item) => item.label,
        ),
        ['首页', '动态', '我的', '设置'],
      );
      expect(find.byKey(const ValueKey('channel-live')), findsOneWidget);
      // Reselecting the current destination is a no-op, even without a router.
      await tester.tap(find.byKey(const ValueKey('workspace-bottom-home')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final width in [599.0, 600.0, 960.0, 1440.0, 599.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byKey(const ValueKey('retained-content'))),
          same(content),
        );
        if (width < 600) {
          final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect(
            bar.destinations.whereType<NavigationDestination>().map(
              (item) => item.label,
            ),
            ['首页', '动态', '我的', '设置'],
          );
          expect(find.byKey(const ValueKey('channel-live')), findsOneWidget);
        } else {
          expect(find.byType(NavigationBar), findsNothing);
          expect(
            find.byKey(const ValueKey('workspace-nav-live')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('channel-live')), findsNothing);
        }
        expect(find.byKey(const ValueKey('channel-bangumi')), findsOneWidget);
        expect(find.byKey(const ValueKey('channel-cinema')), findsOneWidget);
        expect(find.text('媒体库'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant(TargetPlatform.values.toSet()),
  );
  testWidgets(
    'desktop utilities stay at the bottom while main navigation scrolls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: const BiliAppShell(
            navigationMode: WorkspaceNavigationMode.dualTabs,
            location: '/',
            child: SizedBox.expand(key: ValueKey('retained-content')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('workspace-brand-logo')),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/branding/app_icon.png',
      );
      final content = tester.element(
        find.byKey(const ValueKey('retained-content')),
      );
      for (final size in const [
        Size(1280, 844),
        Size(600, 844),
        Size(600, 320),
        Size(1280, 320),
        Size(720, 240),
        Size(1280, 240),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final side = tester.getRect(
          find.byKey(const ValueKey('workspace-side-navigation')),
        );
        final utilities = [
          for (final name in ['messages', 'downloads', 'settings'])
            find.byKey(ValueKey('workspace-nav-$name')),
        ];
        for (final utility in utilities) {
          expect(
            utility.hitTestable(),
            findsOneWidget,
            reason: '$size $utility',
          );
        }
        final before = utilities.map(tester.getRect).toList();
        expect(side.bottom - before.last.bottom, closeTo(15, 0.1));
        await tester.drag(
          find.byKey(const ValueKey('workspace-primary-navigation')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();
        expect(utilities.map(tester.getRect), before);
        expect(
          find.byKey(const ValueKey('workspace-nav-mine')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.element(find.byKey(const ValueKey('retained-content'))),
          same(content),
        );
        expect(tester.takeException(), isNull, reason: '$size');
      }
    },
  );

  testWidgets(
    'mine keeps channels without common tools',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final location in [
        '/?channel=watchLater',
        '/?channel=favorites',
        '/me',
        '/history',
        '/downloads',
        '/messages',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: BiliAppShell(
              key: ValueKey(location),
              location: location,
              navigationMode: WorkspaceNavigationMode.dualTabs,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(),
            ),
          ),
        );
        for (final width in [320.0, 390.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
            reason: '$location width=$width',
          );
          expect(find.byIcon(Icons.account_circle), findsNothing);
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          if (Uri.parse(location).queryParameters['channel']
              case final channel?) {
            expect(find.byKey(ValueKey('channel-$channel')), findsOneWidget);
          } else {
            expect(
              find.byKey(const ValueKey('home-channel-strip')),
              findsNothing,
            );
          }
          expect(
            find.byKey(const ValueKey('workspace-bottom-navigation')),
            width < 600 ? findsOneWidget : findsNothing,
          );
          final hasBack =
              location == '/history' ||
              (location == '/messages' &&
                  Theme.of(tester.element(find.byType(BiliAppShell)))
                          .platform ==
                      TargetPlatform.android);
          expect(
            find.byKey(const ValueKey('workspace-page-back-header')),
            hasBack ? findsOneWidget : findsNothing,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$location width=$width',
          );
        }
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'dynamic shows tools only on wide layouts and keeps a recognizable icon',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final channel in ['dynamic', 'videoDynamic']) {
        await tester.pumpWidget(
          MaterialApp(
            home: BiliAppShell(
              key: ValueKey(channel),
              location: '/?channel=$channel',
              navigationMode: WorkspaceNavigationMode.multipleTabs,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(),
            ),
          ),
        );
        for (final width in [320.0, 390.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpAndSettle();
          expect(
            find.byIcon(Icons.account_circle),
            width < 600 ? findsNothing : findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workspace-search')),
            width < 600 ? findsNothing : findsOneWidget,
          );
          expect(find.byKey(const ValueKey('channel-dynamic')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('channel-videoDynamic')),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  const ['观看历史', '下载', '设置'].contains(widget.tooltip),
            ),
            findsNothing,
          );
          final tabIcon = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const ValueKey('workspace-tab-home')),
              matching: find.byType(Icon),
            ),
          );
          expect(tabIcon.icon, Icons.rss_feed_rounded);
          if (width >= 600) {
            final icon = tester.widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('workspace-nav-dynamic')),
                matching: find.byType(Icon),
              ),
            );
            expect(icon.icon, Icons.rss_feed_rounded);
          } else {
            final bar = tester.widget<NavigationBar>(
              find.byType(NavigationBar),
            );
            final destination = bar.destinations
                .whereType<NavigationDestination>()
                .singleWhere((item) => item.label == '动态');
            expect((destination.icon as Icon).icon, Icons.rss_feed_rounded);
            expect(
              (destination.selectedIcon as Icon).icon,
              Icons.rss_feed_rounded,
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$channel width=$width',
          );
        }
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'compact dynamic tabs split the top safe area width with centered labels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final channel in ['dynamic', 'videoDynamic']) {
        for (final (width, scale) in [
          (320.0, 1.0),
          (390.0, 1.0),
          (599.0, 1.0),
          (320.0, 2.0),
        ]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpWidget(
            MaterialApp(
              theme: BiliTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 24),
                  textScaler: TextScaler.linear(scale),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
              home: BiliAppShell(
                key: ValueKey(channel),
                location: '/?channel=$channel',
                navigationMode: WorkspaceNavigationMode.dualTabs,
                accountBuilder: (_) => const Icon(Icons.account_circle),
                child: const SizedBox.expand(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('home-channel-strip')))
                .top,
            24,
          );
          for (final (index, name) in ['dynamic', 'videoDynamic'].indexed) {
            final tab = find.byKey(ValueKey('channel-$name'));
            final rect = tester.getRect(tab);
            expect(rect.width, closeTo(width / 2, .01));
            expect(rect.left, closeTo(index * width / 2, .01));
            final label = find.descendant(of: tab, matching: find.byType(Row));
            expect(tester.getCenter(label).dx, closeTo(rect.center.dx, .01));
            expect(
              find.descendant(of: label, matching: find.byType(Icon)),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: label,
                matching: find.text(index == 0 ? '动态' : '视频动态'),
              ),
              findsOneWidget,
            );
            expect(tab.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'home and search keep account and search without shortcut tools',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final location in ['/', '/search?q=cat']) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: BiliAppShell(
                key: ValueKey(location),
                location: location,
                navigationMode: WorkspaceNavigationMode.dualTabs,
                accountBuilder: (_) => const Icon(Icons.account_circle),
                pageBuilder: (_, tab) => tab.location.path == '/search'
                    ? Builder(
                        builder: (context) => WorkspacePageHeader.wrap(
                          context,
                          const SizedBox.expand(),
                        ),
                      )
                    : const SizedBox.expand(),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        for (final width in [320.0, 390.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.account_circle), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-search')),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  const ['观看历史', '下载', '设置'].contains(widget.tooltip),
            ),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('search-category-strip')),
            location == '/' ? findsNothing : findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$location width=$width',
          );
        }
      }
    },
  );

  testWidgets('live moves between home and its root while keeping content', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light(),
        home: BiliAppShell(
          location: '/?channel=live&section=我的关注',
          navigationMode: WorkspaceNavigationMode.multipleTabs,
          accountBuilder: (_) => const Icon(Icons.account_circle),
          child: const SizedBox.expand(key: ValueKey('live-content')),
        ),
      ),
    );
    Element? content;
    for (final width in [600.0, 960.0, 1440.0, 599.0, 390.0, 600.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      content ??= tester.element(find.byKey(const ValueKey('live-content')));
      expect(
        tester.element(find.byKey(const ValueKey('live-content'))),
        same(content),
      );
      expect(find.byIcon(Icons.account_circle), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-search')), findsOneWidget);
      expect(find.text('全部分区'), findsNothing);
      expect(find.byKey(const ValueKey('channel-ranking')), findsNothing);
      expect(find.byKey(const ValueKey('workspace-back')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-channel-strip')),
        width < 600 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('channel-live')),
        width < 600 ? findsOneWidget : findsNothing,
      );
      for (final section in ['推荐直播', '我的关注', '观看记录']) {
        expect(
          find.byKey(ValueKey('workspace-live-section-$section')),
          width < 600 ? findsNothing : findsOneWidget,
        );
      }
      if (width < 600) {
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(
          bar.destinations.whereType<NavigationDestination>().map(
            (item) => item.label,
          ),
          ['首页', '动态', '我的', '设置'],
        );
        expect(bar.selectedIndex, 0);
      }
      expect(tester.takeException(), isNull, reason: '$width');
    }
  }, variant: TargetPlatformVariant(TargetPlatform.values.toSet()));

  for (final mode in WorkspaceNavigationMode.values) {
    for (final location in ['/', '/search?q=cat']) {
      for (final width in [320.0, 390.0, 800.0]) {
        testWidgets(
          'keyboard hides only bottom navigation at $location in $mode at $width',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 844);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetViewInsets);
            var builds = 0;
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: BiliAppShell(
                    location: location,
                    navigationMode: mode,
                    pageBuilder: (_, tab) {
                      builds++;
                      final page = SizedBox.expand(
                        key: ValueKey('page-${tab.location.path}'),
                      );
                      return tab.location.path == '/search'
                          ? Builder(
                              builder: (context) =>
                                  WorkspacePageHeader.wrap(context, page),
                            )
                          : page;
                    },
                    child: const SizedBox.shrink(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final compact = width < 600;
            final navigation = find.byKey(
              const ValueKey('workspace-bottom-navigation'),
            );
            final search = find.byKey(const ValueKey('workspace-search'));
            final content = find.byKey(
              ValueKey('page-${Uri.parse(location).path}'),
            );
            final element = tester.element(content);
            final before = tester.getSize(content);
            final navigationHeight = compact
                ? tester.getSize(navigation).height
                : 0.0;
            await tester.enterText(search, '测试草稿');
            await tester.pumpAndSettle();
            builds = 0;
            for (final inset in [1.0, 100.0, 240.0, 320.0, 160.0, 0.0]) {
              tester.view.viewInsets = FakeViewPadding(bottom: inset);
              await tester.pumpAndSettle();
              expect(
                navigation,
                compact && inset == 0 ? findsOneWidget : findsNothing,
              );
              if (!compact) {
                expect(
                  find.byKey(const ValueKey('workspace-side-navigation')),
                  findsOneWidget,
                );
              }
              expect(builds, 0);
              expect(tester.element(content), same(element));
              expect(
                tester.getSize(content).height,
                before.height - inset + (inset > 0 ? navigationHeight : 0),
              );
              final field = tester.widget<TextField>(search);
              expect(field.controller?.text, '测试草稿');
              expect(
                tester
                    .widget<EditableText>(find.byType(EditableText))
                    .focusNode
                    .hasFocus,
                isTrue,
              );
              expect(tester.takeException(), isNull);
            }
          },
          variant: TargetPlatformVariant.only(TargetPlatform.android),
        );
      }
    }
  }

  for (final mode in WorkspaceNavigationMode.values) {
    for (final disableAnimations in [false, true]) {
      testWidgets(
        'bottom navigation reveals smoothly and hides immediately in $mode with disableAnimations=$disableAnimations',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: disableAnimations);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: BiliAppShell(
                location: '/',
                navigationMode: mode,
                child: const SizedBox.expand(key: ValueKey('retained-content')),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final navigation = find.byKey(
            const ValueKey('workspace-bottom-navigation'),
          );
          final content = find.byKey(const ValueKey('retained-content'));
          final search = find.byKey(const ValueKey('workspace-search'));
          final before = tester.getSize(content).height;
          final navigationHeight = tester.getSize(navigation).height;
          await tester.enterText(search, '保留草稿');
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pumpAndSettle();
          expect(navigation, findsNothing);

          tester.view.viewInsets = const FakeViewPadding();
          await tester.pump();
          if (disableAnimations) {
            expect(tester.getSize(content).height, before);
            expect(navigation.hitTestable(), findsOneWidget);
          } else {
            expect(tester.getSize(content).height, before + navigationHeight);
            await tester.pump(const Duration(milliseconds: 60));
            expect(
              tester.getSize(content).height,
              inExclusiveRange(before, before + navigationHeight),
            );
            expect(
              tester
                  .widget<Opacity>(
                    find
                        .ancestor(
                          of: navigation,
                          matching: find.byType(Opacity),
                        )
                        .first,
                  )
                  .opacity,
              inExclusiveRange(0.0, 1.0),
            );
            expect(navigation.hitTestable(), findsNothing);
          }

          // Reopening the keyboard must cancel even an unfinished reveal.
          tester.view.viewInsets = const FakeViewPadding(bottom: 160);
          await tester.pump();
          expect(navigation, findsNothing);
          expect(
            tester.getSize(content).height,
            before + navigationHeight - 160,
          );
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(tester.getSize(content).height, before);
          expect(navigation.hitTestable(), findsOneWidget);
          expect(tester.widget<TextField>(search).controller?.text, '保留草稿');
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  testWidgets('keyboard height changes retain active and hidden page widgets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BiliAppShell(
          location: '/video/BV1abc123456',
          navigationMode: WorkspaceNavigationMode.dualTabs,
          pageBuilder: (_, tab) {
            builds++;
            return SizedBox.expand(key: ValueKey('page-${tab.location.path}'));
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('page-/video/BV1abc123456'));
    final element = tester.element(active);
    final before = tester.getSize(active);
    builds = 0;
    for (final inset in [100.0, 200.0, 320.0, 160.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      expect(builds, 0);
      expect(tester.element(active), same(element));
      expect(tester.getSize(active).height, before.height - inset);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final dark in [false, true]) {
    testWidgets('home labels follow font changes in dark=$dark', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [375.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 800);
        Element? firstTab;
        for (final (font, family) in [
          (AppFontPreference.harmonyOsSans, ''),
          (AppFontPreference.installed, 'Microsoft YaHei'),
          (AppFontPreference.installed, 'Segoe UI'),
          (AppFontPreference.system, ''),
          (AppFontPreference.harmonyOsSans, ''),
        ]) {
          final theme = (dark ? BiliTheme.dark : BiliTheme.light)(
            font: font,
            systemFontFamily: family,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const BiliAppShell(location: '/', child: SizedBox.expand()),
            ),
          );
          await tester.pumpAndSettle();
          for (final channel in channelsForSection(
            WorkspaceSection.home,
            compact: width < 600,
          )) {
            final tab = find.byKey(ValueKey('channel-${channel.name}'));
            final label = find.descendant(
              of: find.descendant(of: tab, matching: find.text(channel.label)),
              matching: find.byType(RichText),
            );
            final style = tester
                .renderObject<RenderParagraph>(label)
                .text
                .style;
            expect(
              style?.fontFamily,
              theme.textTheme.labelLarge?.fontFamily,
              reason: '${channel.name} font=$font family=$family width=$width',
            );
            expect(style?.fontSize, 14);
            expect(style?.fontWeight, FontWeight.w500);
          }
          final element = tester.element(
            find.byKey(const ValueKey('channel-recommended')),
          );
          firstTab ??= element;
          expect(element, same(firstTab));
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets(
      'messages hide home navigation and common tools across resizing in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: BiliAppShell(
              location: '/messages',
              navigationMode: mode,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(key: ValueKey('message-content')),
            ),
          ),
        );
        for (final width in [320.0, 759.0, 760.0, 1200.0, 400.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('home-channel-strip')),
            findsNothing,
          );
          expect(find.byIcon(Icons.account_circle), findsNothing);
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          expect(find.byTooltip('观看历史'), findsNothing);
          expect(
            find.byKey(const ValueKey('workspace-bottom-navigation')),
            width < 600 ? findsOneWidget : findsNothing,
          );
          final tabs = find.byKey(const ValueKey('workspace-tab-strip'));
          final sidebarToolbar = find.byKey(
            const ValueKey('workspace-sidebar-toolbar'),
          );
          final headerBottom = tabs.evaluate().isNotEmpty
              ? tester.getBottomLeft(tabs).dy
              : sidebarToolbar.evaluate().isNotEmpty
              ? tester.getBottomLeft(sidebarToolbar).dy
              : 0;
          final pageBack = find.byKey(
            const ValueKey('workspace-page-back-header'),
          );
          final pageBackHeight = pageBack.evaluate().isEmpty
              ? 0
              : tester.getSize(pageBack).height;
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('message-content'))).dy,
            headerBottom + pageBackHeight + (width >= 600 ? 12 : 0),
          );
          expect(tester.takeException(), isNull, reason: 'window width $width');
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );
  }
  testWidgets('shell fits narrow and wide windows at double text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in [400.0, 720.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const BiliAppShell(location: '/', child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'window width $width');
      expect(find.byKey(const ValueKey('channel-recommended')), findsOneWidget);
    }
  });
}
