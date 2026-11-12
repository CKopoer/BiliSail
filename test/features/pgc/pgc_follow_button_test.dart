import 'dart:async';

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_follow_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_follow_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_follow_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pgc_follow_fake.dart';

const _id = PgcSeasonId('42');
const _button = ValueKey('pgc-follow-button');

void main() {
  for (final type in [1, 4, 2, 3, 5, 7]) {
    testWidgets('season type $type can follow and cancel in both themes', (
      tester,
    ) async {
      final repo = PgcFollowFake();
      final drama = const {2, 3, 5, 7}.contains(type);
      final label = drama ? '追剧' : '追番';
      await _mount(tester, repo, type: type, dark: drama);
      expect(find.text(label), findsOneWidget);
      expect(repo.writes, isEmpty);
      await tester.tap(find.byKey(_button));
      await tester.pumpAndSettle();
      expect(find.text('已$label'), findsOneWidget);
      expect(find.byTooltip('取消$label'), findsOneWidget);
      expect(repo.writes, [(_id, true)]);
      await tester.tap(find.byKey(_button));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(repo.writes, [(_id, true), (_id, false)]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('guest click opens login without account requests', (
    tester,
  ) async {
    final repo = PgcFollowFake();
    var logins = 0;
    await _mount(tester, repo, signedIn: false, onLogin: () => logins++);
    await tester.tap(find.byKey(_button));
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(repo.reads, isEmpty);
    expect(repo.writes, isEmpty);
  });

  testWidgets('initial loading and pending writes disable the action', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final repo = PgcFollowFake()..pendingRead = pending;
    await _mount(tester, repo, settle: false);
    expect(tester.widget<TextButton>(find.byKey(_button)).onPressed, isNull);
    pending.complete(false);
    await tester.pumpAndSettle();
    repo.pendingWrite = Completer<void>();
    await tester.tap(find.byKey(_button));
    await tester.pump();
    expect(tester.widget<TextButton>(find.byKey(_button)).onPressed, isNull);
    expect(find.text('处理中'), findsOneWidget);
    repo.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.text('已追番'), findsOneWidget);
    expect(repo.writes, hasLength(1));
  });

  testWidgets(
    'unknown result shows a read action and wraps in narrow large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repo = PgcFollowFake()
        ..writeFailure = const PgcFollowWriteUncertain();
      await _mount(tester, repo, dark: true, textScale: 2);
      await tester.tap(find.byKey(_button));
      await tester.pumpAndSettle();
      expect(find.text('刷新状态'), findsOneWidget);
      expect(find.text('追番结果暂时无法确认，请刷新状态后再操作'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repo.followed = true;
      await tester.tap(find.byKey(_button));
      await tester.pumpAndSettle();
      expect(find.text('已追番'), findsOneWidget);
      expect(repo.writes, hasLength(1));
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  PgcFollowFake repo, {
  int type = 1,
  bool dark = false,
  bool signedIn = true,
  bool settle = true,
  double textScale = 1,
  VoidCallback? onLogin,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(signedIn)),
        pgcFollowRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: dark ? BiliTheme.dark() : BiliTheme.light(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PgcFollowButton(
                seasonId: _id,
                seasonType: type,
                onLogin: onLogin,
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

class _Auth extends AuthController {
  _Auth(this.signedIn);
  final bool signedIn;
  @override
  AuthState build() => signedIn
      ? const AuthState(status: AuthStatus.signedIn, mid: '7')
      : const AuthState();
}
