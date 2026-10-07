import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/domain/account_overview.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_button.dart';
import 'package:bilisail/features/auth/presentation/account_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('WRITE_UI_PREVIEW')) {
      await (FontLoader('HarmonyOS Sans')..addFont(
            rootBundle.load(
              'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  late AuthFake auth;
  setUp(() => auth = AuthFake());
  tearDown(() async => auth.stream.close());
  Future<void> mount(
    WidgetTester tester,
    ValueChanged<String> navigate, {
    double scale = 1,
    EdgeInsets safeArea = EdgeInsets.zero,
    bool settleOpen = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          accountOverviewProvider.overrideWith(
            (ref) async => const AccountOverview(
              level: 6,
              currentExperience: 43362,
              following: 80,
              followers: 10,
              dynamics: 29,
              coins: 9,
            ),
          ),
          accountMessageIndicatorProvider.overrideWithValue(
            const AccountMessageIndicator(count: 3),
          ),
        ],
        child: RepaintBoundary(
          key: const ValueKey('preview'),
          child: MaterialApp(
            theme: BiliTheme.light(),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: safeArea,
                viewPadding: safeArea,
              ),
              child: child ?? const SizedBox(),
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: AccountButton(onNavigate: navigate),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('我的账号'));
    if (settleOpen) await tester.pumpAndSettle();
  }

  testWidgets(
    'account panel shows metadata, destinations and closes before navigation',
    (tester) async {
      final routes = <String>[];
      await mount(tester, routes.add);
      expect(find.text('等级 6'), findsOneWidget);
      expect(find.text('已满级 · 43362'), findsOneWidget);
      for (final label in [
        '关注',
        '粉丝',
        '动态',
        '个人中心',
        '我的消息',
        '稍后再看',
        '我的收藏',
        '历史记录',
        '直播中心',
        '退出登录',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('我的消息'));
      await tester.pumpAndSettle();
      expect(routes, ['/messages']);
      expect(find.byType(AccountMenu), findsNothing);
    },
  );
  testWidgets('statistics navigate to corresponding profile sections', (
    tester,
  ) async {
    final routes = <String>[];
    await mount(tester, routes.add);
    await tester.tap(find.text('粉丝'));
    await tester.pumpAndSettle();
    expect(routes, ['/user/1?section=followers']);
  });
  testWidgets('narrow panel scrolls to logout at double text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mount(
      tester,
      (_) {},
      scale: 2,
      safeArea: const EdgeInsets.only(top: 24, bottom: 20),
    );
    final panel = tester.getRect(find.byType(Drawer));
    expect(panel, const Rect.fromLTWH(72, 0, 288, 600));
    expect(
      tester.getTopLeft(find.byTooltip('关闭')).dy,
      greaterThanOrEqualTo(24),
    );
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('退出登录')).dy, lessThanOrEqualTo(580));
    expect(find.byTooltip('关闭').hitTestable(), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(auth.current.isSignedIn, false);
  });
  testWidgets('account panel slides in from the right at full height', (
    tester,
  ) async {
    await mount(tester, (_) {}, settleOpen: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opening = tester.getTopLeft(find.byType(Drawer)).dx;
    expect(opening, greaterThan(440));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(Drawer)),
      const Rect.fromLTWH(440, 0, 360, 600),
    );
  });
  for (final action in ['close', 'barrier', 'escape', 'back']) {
    testWidgets('dismiss account panel using $action', (tester) async {
      final routes = <String>[];
      await mount(tester, routes.add);
      switch (action) {
        case 'close':
          await tester.tap(find.byTooltip('关闭'));
        case 'barrier':
          await tester.tapAt(const Offset(20, 300));
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'back':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byType(AccountMenu), findsNothing);
      expect(auth.current.isSignedIn, isTrue);
      expect(routes, isEmpty);
    });
  }
  for (final size in [const Size(320, 568), const Size(740, 360)]) {
    testWidgets('account panel fits $size at double text scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await mount(tester, (_) {}, scale: 2);
      await tester.ensureVisible(find.text('退出登录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('退出登录').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountMenu), findsNothing);
    });
  }
  testWidgets('account change dismisses panel', (tester) async {
    await mount(tester, (_) {});
    auth.emit(const AuthState());
    await tester.pumpAndSettle();
    expect(find.byType(AccountMenu), findsNothing);
    expect(find.byTooltip('登录'), findsOneWidget);
  });
  for (final size in [const Size(900, 720), const Size(390, 844)]) {
    testWidgets('account panel visual preview at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await mount(
        tester,
        (_) {},
        safeArea: size.width < 400
            ? const EdgeInsets.only(top: 24, bottom: 20)
            : EdgeInsets.zero,
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('WRITE_UI_PREVIEW')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            final directory = Directory('artifacts/account-panel-preview')
              ..createSync(recursive: true);
            File('${directory.path}/account-panel-${size.width.toInt()}.png')
                .writeAsBytesSync(bytes.buffer.asUint8List());
          }
          image.dispose();
        });
      }
    });
  }
}
