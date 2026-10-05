import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/app/theme.dart';
import 'package:bili_lite/features/auth/application/account_overview_controller.dart';
import 'package:bili_lite/features/auth/domain/account_overview.dart';
import 'package:bili_lite/features/auth/presentation/account_button.dart';
import 'package:bili_lite/features/auth/presentation/account_menu.dart';
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
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
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
    await tester.pumpAndSettle();
  }

  testWidgets(
    'UWP menu shows real metadata, destinations and closes before navigation',
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
  testWidgets('narrow menu scrolls to logout at double text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mount(tester, (_) {}, scale: 2);
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(auth.current.isSignedIn, false);
  });
  testWidgets('account menu visual preview', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mount(tester, (_) {});
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('WRITE_UI_PREVIEW')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final directory = Directory('artifacts/message-ui-preview')
            ..createSync(recursive: true);
          File('${directory.path}/account-menu.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
    }
  });
}
