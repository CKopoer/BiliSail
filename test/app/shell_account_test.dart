import 'dart:async';

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/account_overview.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_button.dart';
import 'package:bilisail/features/auth/presentation/account_menu.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    for (final location in ['/', '/search?q=test']) {
      testWidgets('$mode $location opens login directly across resizing', (
        tester,
      ) async {
        final auth = _FakeAuthRepository();
        addTearDown(auth.dispose);
        _configureView(tester);
        await tester.pumpWidget(_app(auth, mode, location));

        for (final width in [1200.0, 760.0, 759.0, 400.0, 320.0, 1200.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(find.byTooltip('登录'), findsOneWidget);
          expect(find.byTooltip('账号'), findsNothing);
          await tester.tap(find.byTooltip('登录'));
          await tester.pumpAndSettle();
          expect(find.byType(AccountDialog), findsOneWidget);
          expect(find.text('登录哔哩哔哩'), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.byType(AccountMenu), findsNothing);
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          expect(find.byType(AccountDialog), findsNothing);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull, reason: 'width $width');
        }
      });

      testWidgets('$mode $location uses account state in a narrow toolbar', (
        tester,
      ) async {
        final auth = _FakeAuthRepository();
        addTearDown(auth.dispose);
        _configureView(tester);
        tester.view.physicalSize = const Size(320, 800);
        var refreshCalls = 0;
        await tester.pumpWidget(
          _app(
            auth,
            mode,
            location,
            textScale: 2,
            refresh: () => refreshCalls++,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('登录'), findsOneWidget);
        await tester.tap(find.byTooltip('登录'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountDialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();

        auth.emit(
          const AuthState(
            status: AuthStatus.signedIn,
            userName: '测试账号',
            mid: '123',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('登录'), findsNothing);
        expect(find.byTooltip('我的账号'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        await tester.tap(find.byTooltip('我的账号'));
        await tester.pumpAndSettle();
        expect(refreshCalls, 1);
        expect(find.byType(AccountMenu), findsOneWidget);
        expect(find.byType(AccountDialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);

        auth.emit(const AuthState());
        await tester.pumpAndSettle();
        expect(find.byType(AccountMenu), findsNothing);
        expect(find.byTooltip('登录'), findsOneWidget);
        await tester.tap(find.byTooltip('登录'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountDialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _configureView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  _FakeAuthRepository auth,
  WorkspaceNavigationMode mode,
  String location, {
  double textScale = 1,
  VoidCallback? refresh,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    accountOverviewProvider.overrideWith(
      (ref) async => const AccountOverview(level: 6),
    ),
    accountMessageIndicatorProvider.overrideWithValue(
      AccountMessageIndicator(count: 3, refresh: refresh),
    ),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child ?? const SizedBox(),
    ),
    home: BiliAppShell(
      location: location,
      navigationMode: mode,
      accountBuilder: (_) => const AccountButton(),
      pageBuilder: (_, tab) => tab.location.path == '/search'
          ? Builder(
              builder: (context) =>
                  WorkspacePageHeader.wrap(context, const SizedBox.expand()),
            )
          : const SizedBox.expand(),
      child: const SizedBox.expand(),
    ),
  ),
);

final class _FakeAuthRepository implements AuthRepository {
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  AuthState _current = const AuthState();

  @override
  AuthState get current => _current;
  @override
  Stream<AuthState> get changes => _changes.stream;

  void emit(AuthState state) {
    _current = state;
    _changes.add(state);
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async => emit(const AuthState());

  Future<void> dispose() => _changes.close();
}
