import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/account_overview.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_screen.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _overview = AccountOverview(
  level: 5,
  currentExperience: 20500,
  levelExperience: 10800,
  nextExperience: 28800,
  following: 82,
  followers: 37,
  dynamics: 24,
  coins: 12.5,
  bCoins: 6.25,
  vipLabel: '年度大会员',
);

const _maxOverview = AccountOverview(
  level: 6,
  currentExperience: 43597,
  coins: 1029.2,
  bCoins: 25,
  following: 82,
  followers: 10,
  dynamics: 30,
);

void main() {
  late _AuthRepository auth;
  late _OverviewRepository overview;
  late ValueNotifier<bool> workspaceActive;
  late ValueNotifier<int> contentVersion;
  late Map<AccountContentTab, int> initializations;
  late Map<AccountContentTab, (bool, bool)> activities;
  late Map<AccountContentTab, BoxConstraints> constraints;

  setUpAll(() async {
    // Geometry assertions use the same font metrics as the shipped theme.
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    auth = _AuthRepository();
    overview = _OverviewRepository();
    workspaceActive = ValueNotifier(true);
    contentVersion = ValueNotifier(1);
    initializations = {};
    activities = {};
    constraints = {};
  });
  tearDown(() async {
    await auth.changesController.close();
    workspaceActive.dispose();
    contentVersion.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    ValueChanged<String>? onNavigate,
    VoidCallback? onLogin,
    double scale = 1,
    bool settle = true,
    NavigatorObserver? observer,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          accountOverviewRepositoryProvider.overrideWithValue(overview),
          accountMessageIndicatorProvider.overrideWith(
            (_) => throw StateError('the account page must not load messages'),
          ),
        ],
        child: RepaintBoundary(
          key: const ValueKey('account-preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? BiliTheme.dark() : BiliTheme.light(),
            navigatorObservers: [?observer],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: workspaceActive,
                builder: (context, active, _) => WorkspaceActivity(
                  active: active,
                  child: ValueListenableBuilder(
                    valueListenable: contentVersion,
                    builder: (context, version, _) => AccountScreen(
                      onNavigate: onNavigate,
                      onLogin: onLogin ?? () {},
                      contentBuilder: (context, tab) => _ContentProbe(
                        key: ValueKey('probe-${tab.name}'),
                        tab: tab,
                        version: version,
                        onInitialize: () => initializations.update(
                          tab,
                          (value) => value + 1,
                          ifAbsent: () => 1,
                        ),
                        onActivity: (active, ticking) =>
                            activities[tab] = (active, ticking),
                        onConstraints: (value) => constraints[tab] = value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> select(WidgetTester tester, AccountContentTab tab) async {
    final finder = find.byKey(ValueKey('account-tab-${tab.name}'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  _ContentProbeState probe(WidgetTester tester, AccountContentTab tab) =>
      tester.state<_ContentProbeState>(
        find.byKey(ValueKey('probe-${tab.name}'), skipOffstage: false),
      );

  void expectBalanceAlignment(WidgetTester tester) {
    Rect character(Finder finder) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      );
      final box = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .single;
      return Rect.fromPoints(
        paragraph.localToGlobal(Offset(box.left, box.top)),
        paragraph.localToGlobal(Offset(box.right, box.bottom)),
      );
    }

    expect(
      character(find.text('B')).left,
      closeTo(character(find.text('硬')).left, .5),
    );
    final suffixes = find.descendant(
      of: find.byKey(const ValueKey('account-balances')),
      matching: find.text('币'),
    );
    expect(suffixes, findsNWidgets(2));
    final coins = character(suffixes.at(0));
    final bCoins = character(suffixes.at(1));
    expect(bCoins.left, closeTo(coins.left, .5));
    expect(bCoins.right, closeTo(coins.right, .5));
    expect(tester.widget<Text>(find.text('硬')).semanticsLabel, '硬币');
    expect(tester.widget<Text>(find.text('B')).semanticsLabel, 'B币');
    expect(
      tester.getTopLeft(find.text('6.25')).dx,
      closeTo(tester.getTopLeft(find.text('12.5')).dx, .01),
    );
  }

  testWidgets(
    'compact profile and four tabs show content without route changes',
    (tester) async {
      viewport(tester, const Size(1200, 720));
      final routes = <String>[];
      await mount(tester, onNavigate: routes.add);
      expect(find.byType(NetworkAvatar), findsOneWidget);
      expect(find.text('测试账号'), findsOneWidget);
      expect(find.text('等级 5'), findsOneWidget);
      expect(find.text('经验 20500 / 28800'), findsOneWidget);
      expect(find.text('硬'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('12.5'), findsOneWidget);
      expect(find.text('6.25'), findsOneWidget);
      expectBalanceAlignment(tester);
      final balances = tester.getRect(
        find.byKey(const ValueKey('account-balances')),
      );
      final following = tester.getRect(
        find.byKey(const ValueKey('account-statistic-关注')),
      );
      expect(balances.height, closeTo(following.height, 1));
      expect(balances.center.dy, closeTo(following.center.dy, 1));
      expect(
        tester.getRect(find.text('6.25')).top,
        greaterThan(tester.getRect(find.text('12.5')).bottom),
      );
      for (final label in ['关注', '粉丝', '动态', '82', '37', '24']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('退出登录'), findsOneWidget);
      for (final label in ['我的消息', '直播关注']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('年度大会员'), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('account-profile-summary')))
            .height,
        lessThanOrEqualTo(100),
      );
      final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('account-experience-progress')),
      );
      expect(progress.value, closeTo((20500 - 10800) / (28800 - 10800), .0001));
      expect(progress.minHeight, 2);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('account-experience-progress')))
            .width,
        320,
      );
      for (final tab in AccountContentTab.values) {
        await select(tester, tab);
        expect(find.text('${tab.name} version 1 count 0'), findsOneWidget);
        expect(constraints[tab]?.hasBoundedHeight, isTrue);
        expect(constraints[tab]?.maxHeight, greaterThan(400));
      }
      expect(routes, isEmpty);
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'max-level summary uses the account values and exact statistic routes',
    (tester) async {
      viewport(tester, const Size(1200, 720));
      auth.state = const AuthState(
        status: AuthStatus.signedIn,
        mid: '42',
        userName: 'Kopoer',
      );
      overview.onLoad = (_) async => _maxOverview;
      final routes = <String>[];
      await mount(tester, onNavigate: routes.add);
      for (final label in [
        'Kopoer',
        '等级 6',
        '已满级 · 43597',
        '1029.2',
        '25',
        '82',
        '10',
        '30',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('account-experience-progress')),
            )
            .value,
        1,
      );
      await tester.tap(find.byType(NetworkAvatar));
      for (final label in ['关注', '粉丝', '动态']) {
        await tester.tap(find.byKey(ValueKey('account-statistic-$label')));
      }
      expect(routes, [
        '/user/42',
        '/user/42?section=following',
        '/user/42?section=followers',
        '/user/42?section=dynamics',
      ]);
      expect(find.byType(AccountScreen), findsOneWidget);
    },
  );

  testWidgets(
    'missing overview fields stay unknown with a static progress placeholder',
    (tester) async {
      overview.onLoad = (_) async => const AccountOverview();
      await mount(tester);
      expect(find.text('等级 —'), findsOneWidget);
      expect(find.text('经验 — / —'), findsOneWidget);
      expect(find.text('硬'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(5));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('account-experience-progress-unknown')),
        findsOneWidget,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('account-experience-progress-unknown')),
            )
            .width,
        lessThanOrEqualTo(320),
      );
    },
  );

  testWidgets('known zero balances and counts remain visible as zero', (
    tester,
  ) async {
    overview.onLoad = (_) async => const AccountOverview(
      level: 0,
      currentExperience: 0,
      levelExperience: 0,
      nextExperience: 100,
      coins: 0,
      bCoins: 0,
      following: 0,
      followers: 0,
      dynamics: 0,
    );
    await mount(tester);
    expect(find.text('等级 0'), findsOneWidget);
    expect(find.text('经验 0 / 100'), findsOneWidget);
    expect(find.text('硬'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(5));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('account-experience-progress')),
          )
          .value,
      0,
    );
  });

  testWidgets(
    'tabs initialize lazily and retain independent state and scroll',
    (tester) async {
      viewport(tester, const Size(1000, 720));
      await mount(tester);
      expect(initializations, {AccountContentTab.history: 1});
      final history = probe(tester, AccountContentTab.history);
      await tester.tap(find.byKey(const ValueKey('increment-history')));
      history.controller.jumpTo(520);
      await tester.pumpAndSettle();
      final historyOffset = history.controller.offset;
      await select(tester, AccountContentTab.downloads);
      expect(initializations, {
        AccountContentTab.history: 1,
        AccountContentTab.downloads: 1,
      });
      final downloads = probe(tester, AccountContentTab.downloads);
      expect(downloads.controller, isNot(same(history.controller)));
      downloads.controller.jumpTo(240);
      await tester.pumpAndSettle();
      final downloadOffset = downloads.controller.offset;
      await select(tester, AccountContentTab.history);
      expect(probe(tester, AccountContentTab.history), same(history));
      expect(find.text('history version 1 count 1'), findsOneWidget);
      expect(history.controller.offset, historyOffset);
      await select(tester, AccountContentTab.downloads);
      expect(downloads.controller.offset, downloadOffset);
      expect(initializations.values, everyElement(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden tabs stop activity, tickers and keyboard focus', (
    tester,
  ) async {
    await mount(tester);
    final history = probe(tester, AccountContentTab.history);
    history.focus.requestFocus();
    await tester.pump();
    expect(history.focus.hasFocus, isTrue);
    await select(tester, AccountContentTab.downloads);
    expect(activities[AccountContentTab.history], (false, false));
    expect(activities[AccountContentTab.downloads], (true, true));
    expect(history.focus.canRequestFocus, isFalse);
    expect(history.focus.hasFocus, isFalse);
    workspaceActive.value = false;
    await tester.pumpAndSettle();
    expect(activities[AccountContentTab.downloads], (false, false));
    expect(
      probe(tester, AccountContentTab.downloads).focus.canRequestFocus,
      isFalse,
    );
    workspaceActive.value = true;
    await tester.pumpAndSettle();
    expect(activities[AccountContentTab.downloads], (true, true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('updated content configuration reaches retained mounted tabs', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('increment-history')));
    final history = probe(tester, AccountContentTab.history);
    await select(tester, AccountContentTab.favorites);
    contentVersion.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('favorites version 2 count 0'), findsOneWidget);
    await select(tester, AccountContentTab.history);
    expect(probe(tester, AccountContentTab.history), same(history));
    expect(find.text('history version 2 count 1'), findsOneWidget);
    expect(initializations.values, everyElement(1));
  });

  testWidgets('guest downloads remain available through login and logout', (
    tester,
  ) async {
    auth.state = const AuthState();
    var logins = 0;
    final observer = _NavigationObserver();
    await mount(tester, onLogin: () => logins++, observer: observer);
    expect(overview.reads, isEmpty);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-balances')), findsNothing);
    await tester.tap(find.text('登录账号'));
    expect(logins, 1);
    await select(tester, AccountContentTab.downloads);
    final downloads = probe(tester, AccountContentTab.downloads);
    auth.emit(
      const AuthState(status: AuthStatus.signedIn, mid: '2', userName: '新账号'),
    );
    await tester.pumpAndSettle();
    expect(find.text('新账号'), findsOneWidget);
    expect(find.text('downloads version 1 count 0'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(auth.current.isSignedIn, isFalse);
    expect(find.byKey(const ValueKey('account-balances')), findsNothing);
    expect(find.text('登录账号'), findsOneWidget);
    expect(probe(tester, AccountContentTab.downloads), same(downloads));
    expect(find.text('downloads version 1 count 0'), findsOneWidget);
    expect(observer.pops, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar and name retain the personal profile destination', (
    tester,
  ) async {
    final routes = <String>[];
    await mount(tester, onNavigate: routes.add);
    await tester.tap(find.byType(NetworkAvatar));
    await tester.pump();
    expect(routes, ['/user/1']);
    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('retained profile actions use the latest navigation callback', (
    tester,
  ) async {
    final first = <String>[];
    final current = <String>[];
    await mount(tester, onNavigate: first.add);
    await mount(tester, onNavigate: current.add);
    await tester.tap(find.byType(NetworkAvatar));
    await tester.pump();
    expect(first, isEmpty);
    expect(current, ['/user/1']);
    await tester.tap(find.byKey(const ValueKey('account-statistic-关注')));
    await tester.pump();
    expect(current.last, '/user/1?section=following');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account change hides cached level and ignores a late old reply',
    (tester) async {
      final old = Completer<AccountOverview>();
      overview.onLoad = (_) => old.future;
      await mount(tester, settle: false);
      expect(find.text('等级 —'), findsOneWidget);
      final cancellation = overview.reads.single.$2;
      overview.onLoad = (_) async => const AccountOverview(level: 6);
      auth.emit(
        const AuthState(status: AuthStatus.signedIn, mid: '2', userName: '新账号'),
      );
      await tester.pumpAndSettle();
      expect(cancellation.isCancelled, isTrue);
      expect(find.text('等级 6'), findsOneWidget);
      old.complete(_overview);
      await tester.pumpAndSettle();
      expect(find.text('等级 6'), findsOneWidget);
      expect(find.text('等级 5'), findsNothing);
      expect(find.text('6.25'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      final next = Completer<AccountOverview>();
      overview.onLoad = (_) => next.future;
      auth.emit(
        const AuthState(
          status: AuthStatus.signedIn,
          mid: '3',
          userName: '第三个账号',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('等级 6'), findsNothing);
      expect(find.text('等级 —'), findsOneWidget);
      expect(find.text('硬'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(5));
      next.complete(const AccountOverview(level: 4));
      await tester.pumpAndSettle();
      expect(find.text('等级 4'), findsOneWidget);
    },
  );

  testWidgets('level failure retries locally while content remains usable', (
    tester,
  ) async {
    overview.onLoad = (_) async =>
        throw const AppFailure(AppFailureKind.network, '账号资料暂时不可用');
    await mount(tester);
    expect(find.text('等级 —'), findsOneWidget);
    final retry = find.byTooltip('账号资料暂时不可用，重试账号资料');
    expect(retry, findsOneWidget);
    await select(tester, AccountContentTab.downloads);
    expect(find.text('downloads version 1 count 0'), findsOneWidget);
    overview.onLoad = (_) async => _overview;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(overview.reads.length, 2);
    expect(find.text('等级 5'), findsOneWidget);
    expect(find.text('downloads version 1 count 0'), findsOneWidget);
  });

  testWidgets('touch swipe changes the displayed content tab', (tester) async {
    viewport(tester, const Size(600, 720));
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('account-content-pages')),
      const Offset(-440, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('watchLater version 1 count 0'), findsOneWidget);
    final tab = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('account-tab-watchLater')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(tab.properties.selected, isTrue);
  });

  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets(
      'complete profile stays compact at ordinary text width=$width',
      (tester) async {
        viewport(tester, Size(width, 720));
        await mount(tester);
        expectBalanceAlignment(tester);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('account-profile-summary')))
              .height,
          lessThanOrEqualTo(140),
        );
        for (final label in [
          '等级 5',
          '经验 20500 / 28800',
          '12.5',
          '6.25',
          '关注',
          '粉丝',
          '动态',
        ]) {
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(
          constraints[AccountContentTab.history]?.maxHeight,
          greaterThan(450),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(320, 568),
    const Size(320, 600),
    const Size(390, 600),
    const Size(600, 360),
    const Size(1200, 720),
  ]) {
    testWidgets('compact tabs keep bounded content at $size with double text', (
      tester,
    ) async {
      viewport(tester, size);
      auth.state = const AuthState(
        status: AuthStatus.signedIn,
        mid: '123456789012345678',
        userName: '很长很长的账号名称也应该保持清晰可读',
      );
      await mount(tester, scale: 2);
      expectBalanceAlignment(tester);
      expect(find.byTooltip(auth.current.userName ?? ''), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(auth.current.userName ?? '')).maxLines,
        1,
      );
      if (size.width == 320) {
        expect(
          tester
              .renderObject<RenderParagraph>(
                find.text(auth.current.userName ?? ''),
              )
              .didExceedMaxLines,
          isTrue,
        );
      }
      for (final label in [
        '等级 5',
        '经验 20500 / 28800',
        '12.5',
        '6.25',
        '关注',
        '粉丝',
        '动态',
      ]) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      for (final tab in AccountContentTab.values) {
        await select(tester, tab);
        expect(find.text('${tab.name} version 1 count 0'), findsOneWidget);
        expect(constraints[tab]?.hasBoundedHeight, isTrue);
        expect(constraints[tab]?.maxHeight, greaterThan(100));
      }
      expect(find.text('退出登录').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resizing preserves selection and list state', (tester) async {
    viewport(tester, const Size(1200, 720));
    await mount(tester);
    await select(tester, AccountContentTab.favorites);
    final favorites = probe(tester, AccountContentTab.favorites);
    await tester.tap(find.byKey(const ValueKey('increment-favorites')));
    for (final width in [320.0, 600.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpAndSettle();
      expect(probe(tester, AccountContentTab.favorites), same(favorites));
      expect(find.text('favorites version 1 count 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  for (final (size, dark, scale) in [
    (const Size(1200, 720), false, 1.0),
    (const Size(390, 844), false, 1.0),
    (const Size(1200, 720), true, 1.0),
    (const Size(320, 600), false, 2.0),
  ]) {
    testWidgets('tabbed account preview at $size dark=$dark scale=$scale', (
      tester,
    ) async {
      viewport(tester, size);
      auth.state = const AuthState(
        status: AuthStatus.signedIn,
        mid: '42',
        userName: 'Kopoer',
      );
      overview.onLoad = (_) async => _maxOverview;
      await mount(tester, dark: dark, scale: scale);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('WRITE_UI_PREVIEW')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('account-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            final directory = Directory('artifacts/account-tabs-preview')
              ..createSync(recursive: true);
            File(
              '${directory.path}/account-${size.width.toInt()}-${dark ? 'dark' : 'light'}${scale == 1 ? '' : '-2x'}.png',
            ).writeAsBytesSync(bytes.buffer.asUint8List());
          }
          image.dispose();
        });
      }
    });
  }
}

class _ContentProbe extends StatefulWidget {
  const _ContentProbe({
    super.key,
    required this.tab,
    required this.version,
    required this.onInitialize,
    required this.onActivity,
    required this.onConstraints,
  });

  final AccountContentTab tab;
  final int version;
  final VoidCallback onInitialize;
  final void Function(bool, bool) onActivity;
  final ValueChanged<BoxConstraints> onConstraints;

  @override
  State<_ContentProbe> createState() => _ContentProbeState();
}

class _ContentProbeState extends State<_ContentProbe> {
  final focus = FocusNode();
  int _count = 0;
  ScrollController get controller => PrimaryScrollController.of(context);

  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onActivity(
      WorkspaceActivity.isActive(context),
      TickerMode.valuesOf(context).enabled,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      widget.onConstraints(constraints);
      return Column(
        children: [
          Text('${widget.tab.name} version ${widget.version} count $_count'),
          TextButton(
            key: ValueKey('increment-${widget.tab.name}'),
            focusNode: focus,
            onPressed: () => setState(() => _count++),
            child: const Text('保存状态'),
          ),
          Expanded(
            child: ListView.builder(
              key: PageStorageKey('list-${widget.tab.name}'),
              primary: true,
              itemCount: 100,
              itemExtent: 52,
              itemBuilder: (context, index) =>
                  ListTile(title: Text('${widget.tab.label} · 内容 $index')),
            ),
          ),
        ],
      );
    },
  );

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }
}

class _AuthRepository implements AuthRepository {
  final changesController = StreamController<AuthState>.broadcast(sync: true);
  AuthState state = const AuthState(
    status: AuthStatus.signedIn,
    mid: '1',
    userName: '测试账号',
  );

  @override
  AuthState get current => state;
  @override
  Stream<AuthState> get changes => changesController.stream;

  void emit(AuthState next) {
    state = next;
    changesController.add(next);
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async => emit(const AuthState());
}

class _OverviewRepository implements AccountOverviewRepository {
  final reads = <(String, RequestCancellation)>[];
  Future<AccountOverview> Function(String) onLoad = (_) async => _overview;

  @override
  Future<AccountOverview> load(
    String mid, {
    required RequestCancellation cancellation,
  }) {
    reads.add((mid, cancellation));
    return onLoad(mid);
  }
}

class _NavigationObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}
