import 'package:bilisail/domain/user.dart';

import 'dart:async';

import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_button.dart';
import 'package:bilisail/features/auth/presentation/account_menu.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/domain/account_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('signed in account opens own profile and closes dialog', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    repository._current = const AuthState(
      status: AuthStatus.signedIn,
      userName: '本人',
      mid: '123',
    );
    final opened = <UserId>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          accountOverviewProvider.overrideWith(
            (ref) async => const AccountOverview(level: 6),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: AccountButton(onOpenUser: opened.add)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('我的账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人中心'));
    await tester.pumpAndSettle();
    expect(opened, [const UserId('123')]);
    expect(find.byType(AccountDialog), findsNothing);
    expect(find.byType(AccountMenu), findsNothing);
  });
  testWidgets('closing an active QR dialog cancels sign in', (tester) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository));
    await tester.tap(find.byTooltip('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取登录二维码'));
    await tester.pumpAndSettle();
    expect(find.text('使用哔哩哔哩手机客户端扫一扫'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDialog), findsNothing);
    expect(repository.cancelCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('force-unmounting an active dialog cancels sign in', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository));
    await tester.tap(find.byTooltip('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取登录二维码'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();
    expect(repository.cancelCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('QR dialog fits a narrow window at double text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository, textScale: 2));
    await tester.tap(find.byTooltip('登录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('获取登录二维码'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_FakeAuthRepository repository, {double textScale = 1}) =>
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox(),
        ),
        home: const Scaffold(body: Center(child: AccountButton())),
      ),
    );

final class _FakeAuthRepository implements AuthRepository {
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  AuthState _current = const AuthState();
  int cancelCalls = 0;

  @override
  AuthState get current => _current;

  @override
  Stream<AuthState> get changes => _changes.stream;

  @override
  Future<void> restore() async {}

  @override
  Future<void> signIn() async {
    _current = AuthState(
      status: AuthStatus.waitingScan,
      qrUri: Uri.parse('https://example.test/qr'),
    );
    _changes.add(_current);
  }

  @override
  void cancelSignIn() => cancelCalls++;

  @override
  Future<void> signOut() async {}

  Future<void> dispose() => _changes.close();
}
