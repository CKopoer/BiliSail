import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/account_overview.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_screen.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required NavigationBarMode mode,
    required String location,
    double width = 390,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AuthRepository()),
          accountOverviewProvider.overrideWith(
            (_) async =>
                const AccountOverview(level: 5, following: 12, followers: 34),
          ),
        ],
        child: MaterialApp(
          theme: BiliTheme.light().copyWith(platform: TargetPlatform.windows),
          home: BiliAppShell(
            location: location,
            navigationBarMode: mode,
            accountBuilder: (_) =>
                const CircleAvatar(key: ValueKey('home-avatar'), radius: 16),
            pageBuilder: (_, tab) => tab.location.path == '/me'
                ? AccountScreen(
                    onLogin: () {},
                    contentBuilder: (_, tab) => _list(tab.name),
                  )
                : _list('home'),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (mode, width, collapses) in [
    (NavigationBarMode.automatic, 390.0, true),
    (NavigationBarMode.bottom, 1280.0, true),
    (NavigationBarMode.sidebar, 1280.0, false),
  ]) {
    testWidgets('home tools follow scroll in $mode at $width', (tester) async {
      await mount(tester, mode: mode, location: '/', width: width);
      final channel = find.byKey(const ValueKey('home-channel-strip'));
      final originalTop = tester.getTopLeft(channel).dy;
      final content = tester.element(find.byKey(const ValueKey('list-home')));
      await tester.enterText(
        find.byKey(const ValueKey('workspace-search')),
        '保留搜索草稿',
      );
      await tester.drag(
        find.byKey(const ValueKey('list-home')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-avatar')).hitTestable(),
        collapses ? findsNothing : findsOneWidget,
      );
      expect(tester.getTopLeft(channel).dy, originalTop - (collapses ? 52 : 0));
      expect(channel.hitTestable(), findsOneWidget);
      expect(
        tester.element(find.byKey(const ValueKey('list-home'))),
        same(content),
      );
      await tester.drag(
        find.byKey(const ValueKey('list-home')),
        const Offset(0, 65),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-avatar')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('保留搜索草稿'), findsOneWidget);
      expect(tester.getTopLeft(channel).dy, originalTop);
      expect(tester.takeException(), isNull);
    });

    testWidgets('account profile follows scroll in $mode at $width', (
      tester,
    ) async {
      await mount(tester, mode: mode, location: '/me', width: width);
      final profile = find.byKey(const ValueKey('account-collapsing-profile'));
      final tabs = find.byKey(const ValueKey('account-tab-strip'));
      final height = tester.getSize(profile).height;
      final originalTop = tester.getTopLeft(tabs).dy;
      final history = find.byKey(const ValueKey('list-history'));
      final content = tester.element(history);
      await tester.drag(history, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(tester.getSize(profile).height, collapses ? 0 : height);
      expect(
        tester.getTopLeft(tabs).dy,
        originalTop - (collapses ? height : 0),
      );
      expect(
        find.byKey(const ValueKey('account-tab-history')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.element(history), same(content));
      await tester.tap(find.byKey(const ValueKey('account-tab-watchLater')));
      await tester.pumpAndSettle();
      expect(tester.getSize(profile).height, collapses ? 0 : height);
      await tester.drag(
        find.byKey(const ValueKey('list-watchLater')),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(profile).height, height);
      expect(find.text('测试账号').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _list(String name) => ListView.builder(
  key: ValueKey('list-$name'),
  itemCount: 100,
  itemExtent: 60,
  itemBuilder: (_, index) => Text('$name $index'),
);

class _AuthRepository implements AuthRepository {
  @override
  AuthState get current =>
      const AuthState(status: AuthStatus.signedIn, mid: '1', userName: '测试账号');
  @override
  Stream<AuthState> get changes => const Stream.empty();
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async {}
}
