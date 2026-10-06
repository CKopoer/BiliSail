import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/data/session_repository.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_dialog.dart';
import 'package:bilisail/features/auth/presentation/web_login_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ApiHttpResponse _nav({bool signedIn = true}) => ApiHttpResponse(
  200,
  Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'code': 0,
        'data': {'isLogin': signedIn, 'mid': 123, 'uname': 'Fixture user'},
      }),
    ),
  ),
  const {},
);

LoginCookie _cookie({
  String domain = 'bilibili.com',
  String path = '/',
  bool hostOnly = false,
  String value = 'fixture',
  DateTime? expires,
}) => LoginCookie(
  name: 'SESSDATA',
  value: value,
  domain: domain,
  path: path,
  hostOnly: hostOnly,
  secure: true,
  expires: expires,
);

final class _Credentials implements CredentialStore {
  String? value;
  int deletes = 0;
  bool failWrite = false;
  Future<void> Function()? afterWrite;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
    await afterWrite?.call();
    if (failWrite) throw StateError('fixture secure-store failure');
  }

  @override
  Future<void> delete() async {
    value = null;
    deletes++;
  }
}

final class _Transport implements ApiTransport {
  int calls = 0;
  Future<ApiHttpResponse> Function()? handler;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls++;
    expect(uri.path, '/x/web-interface/nav');
    expect(headers['Cookie'], contains('SESSDATA=fixture'));
    return handler == null ? _nav() : await handler!();
  }
}

SessionRepository _repository(
  _Transport transport,
  _Credentials credentials, {
  Future<void> Function(String)? cleanup,
  WidgetTester? tester,
}) {
  final requests = ApiRequests();
  final repository = SessionRepository(
    api: BiliApiClient(sessionProvider: requests),
    requests: requests,
    credentials: credentials,
    onSessionChanged: cleanup ?? (_) async {},
    loginClientFactory: () => BiliApiClient(transport: transport),
  );
  addTearDown(() async {
    if (tester != null) {
      await tester.pumpWidget(const SizedBox());
      final disposing = repository.dispose();
      await tester.pump();
      await disposing;
    } else {
      await repository.dispose();
    }
    repository.api.close();
  });
  return repository;
}

void main() {
  test(
    'browser session preserves scope and expiry after nav and secure write',
    () async {
      final transport = _Transport();
      final credentials = _Credentials();
      final repository = _repository(transport, credentials);
      final expiry = DateTime.now().toUtc().add(const Duration(days: 1));
      final attempt = repository.beginWebLogin();
      expect(repository.current.status, AuthStatus.waitingWeb);
      await repository.completeWebLogin(attempt!, [_cookie(expires: expiry)]);
      expect(repository.current.isSignedIn, isTrue);
      expect(repository.accountScope, 'user:123');
      expect(transport.calls, 1);
      final saved = jsonDecode(credentials.value!) as Map<String, Object?>;
      final jar = ApiCookieJar()
        ..restoreFromSecureStorage(saved['cookies'] as Map<String, Object?>);
      expect(
        jar.headerFor(Uri.https('api.live.bilibili.com', '/')),
        'SESSDATA=fixture',
      );
      expect(
        jar.headerFor(Uri.https('api.bilibili.com', '/'), now: expiry),
        isNull,
      );
      expect(jar.headerFor(Uri.https('example.com', '/')), isNull);
    },
  );

  for (final cookie in [
    _cookie(domain: 'example.com'),
    _cookie(path: '/private'),
    _cookie(domain: 'passport.bilibili.com', hostOnly: true),
    _cookie(expires: DateTime(2020)),
    _cookie(value: 'fixture; injection'),
  ]) {
    test(
      'invalid or inapplicable browser cookie cannot reach nav: ${cookie.domain} ${cookie.path} ${cookie.expires}',
      () async {
        final transport = _Transport();
        final credentials = _Credentials();
        final repository = _repository(transport, credentials);
        await repository.completeWebLogin(repository.beginWebLogin()!, [
          cookie,
        ]);
        expect(transport.calls, 0);
        expect(credentials.value, isNull);
        expect(repository.current.status, AuthStatus.failed);
      },
    );
  }

  test('cancelled and forged attempts cannot import browser cookies', () async {
    final transport = _Transport();
    final credentials = _Credentials();
    final repository = _repository(transport, credentials);
    final first = repository.beginWebLogin()!;
    repository.cancelSignIn();
    final second = repository.beginWebLogin()!;
    await repository.completeWebLogin(first, [_cookie()]);
    await repository.completeWebLogin(WebLoginAttempt(), [_cookie()]);
    expect(transport.calls, 0);
    await repository.completeWebLogin(second, [_cookie()]);
    expect(repository.current.isSignedIn, isTrue);
  });

  test('late nav cannot promote a cancelled browser login', () async {
    final transport = _Transport();
    final response = Completer<ApiHttpResponse>();
    transport.handler = () => response.future;
    final credentials = _Credentials();
    final repository = _repository(transport, credentials);
    final login = repository.completeWebLogin(repository.beginWebLogin()!, [
      _cookie(),
    ]);
    await Future<void>.delayed(Duration.zero);
    repository.cancelSignIn();
    response.complete(_nav());
    await login;
    expect(repository.current.status, AuthStatus.guest);
    expect(credentials.value, isNull);
  });

  test(
    'rejected nav and partial secure write never retain a browser session',
    () async {
      for (final failWrite in [false, true]) {
        final transport = _Transport()
          ..handler = () async => _nav(signedIn: failWrite);
        final credentials = _Credentials()..failWrite = failWrite;
        final repository = _repository(transport, credentials);
        await repository.completeWebLogin(repository.beginWebLogin()!, [
          _cookie(),
        ]);
        expect(repository.current.status, AuthStatus.failed);
        expect(credentials.value, isNull);
        expect(
          repository.api.cookieJar.headerFor(
            Uri.https('api.bilibili.com', '/'),
          ),
          isNull,
        );
      }
    },
  );

  test('logout during secure write rolls back browser session', () async {
    final credentials = _Credentials();
    final started = Completer<void>();
    final gate = Completer<void>();
    credentials.afterWrite = () async {
      started.complete();
      await gate.future;
    };
    final repository = _repository(_Transport(), credentials);
    final login = repository.completeWebLogin(repository.beginWebLogin()!, [
      _cookie(),
    ]);
    await started.future;
    final logout = repository.signOut();
    gate.complete();
    await Future.wait([login, logout]);
    expect(credentials.value, isNull);
    expect(repository.current.isSignedIn, isFalse);
  });

  for (final startNext in [false, true]) {
    test(
      'cancelled account cleanup rolls back before next browser login: $startNext',
      () async {
        final started = Completer<void>();
        final gate = Completer<void>();
        var cleanups = 0;
        final credentials = _Credentials();
        final repository = _repository(
          _Transport(),
          credentials,
          cleanup: (_) async {
            if (++cleanups == 1) {
              started.complete();
              await gate.future;
            }
          },
        );
        final first = repository.completeWebLogin(repository.beginWebLogin()!, [
          _cookie(),
        ]);
        await started.future;
        repository.cancelSignIn();
        Future<void>? next;
        if (startNext) {
          next = repository.completeWebLogin(repository.beginWebLogin()!, [
            _cookie(),
          ]);
        }
        gate.complete();
        await first;
        if (next != null) await next;
        expect(credentials.deletes, 1);
        expect(repository.current.isSignedIn, startNext);
        expect(credentials.value, startNext ? isNotNull : isNull);
      },
    );
  }

  testWidgets('official page result goes through the existing session commit', (
    tester,
  ) async {
    final credentials = _Credentials();
    final repository = _repository(_Transport(), credentials, tester: tester);
    await tester.pumpWidget(_app(repository, (_) async => [_cookie()]));
    await tester.tap(find.text('密码 / 短信登录'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(repository.current.isSignedIn, isTrue);
    expect(credentials.value, isNotNull);
  });

  testWidgets('closing or unmounting the owner rejects a late browser result', (
    tester,
  ) async {
    final credentials = _Credentials();
    final repository = _repository(_Transport(), credentials, tester: tester);
    final result = Completer<List<LoginCookie>?>();
    await tester.pumpWidget(_app(repository, (_) => result.future));
    await tester.tap(find.text('密码 / 短信登录'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    result.complete([_cookie()]);
    await tester.pumpAndSettle();
    expect(credentials.value, isNull);
    expect(repository.current.isSignedIn, isFalse);
  });

  testWidgets(
    'failed browser validation remains visible after the page closes',
    (tester) async {
      final repository = _repository(
        _Transport(),
        _Credentials(),
        tester: tester,
      );
      await tester.pumpWidget(
        _app(repository, (_) async => [_cookie(domain: 'example.com')]),
      );
      await tester.tap(find.text('密码 / 短信登录'));
      await tester.pumpAndSettle();
      expect(repository.current.status, AuthStatus.failed);
      expect(find.text('未取得有效的网页登录会话，请重试或使用扫码登录'), findsOneWidget);
      expect(find.text('密码 / 短信登录'), findsOneWidget);
    },
  );

  testWidgets('official SMS page may resume after reading messages', (
    tester,
  ) async {
    final repository = _repository(
      _Transport(),
      _Credentials(),
      tester: tester,
    );
    final result = Completer<List<LoginCookie>?>();
    await tester.pumpWidget(_app(repository, (_) => result.future));
    await tester.tap(find.text('密码 / 短信登录'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(repository.current.status, AuthStatus.waitingWeb);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    result.complete([_cookie()]);
    await tester.pumpAndSettle();
    expect(repository.current.isSignedIn, isTrue);
  });

  testWidgets('backgrounding account validation restores login actions', (
    tester,
  ) async {
    final transport = _Transport();
    final response = Completer<ApiHttpResponse>();
    transport.handler = () => response.future;
    final credentials = _Credentials();
    final repository = _repository(transport, credentials, tester: tester);
    await tester.pumpWidget(_app(repository, (_) async => [_cookie()]));
    await tester.tap(find.text('密码 / 短信登录'));
    await tester.pump();
    expect(repository.current.status, AuthStatus.authenticating);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    response.complete(_nav());
    await tester.pumpAndSettle();
    expect(repository.current.status, AuthStatus.guest);
    expect(credentials.value, isNull);
    expect(find.text('密码 / 短信登录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final size in [const Size(320, 568), const Size(640, 360)]) {
    for (final keyboard in [0.0, 220.0]) {
      testWidgets(
        'login actions remain reachable at $size, keyboard $keyboard, double text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = _repository(
            _Transport(),
            _Credentials(),
            tester: tester,
          );
          await tester.pumpWidget(
            _app(
              repository,
              (_) async => null,
              keyboard: keyboard,
              textScale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('密码 / 短信登录'));
          await tester.tap(find.text('密码 / 短信登录'));
          await tester.pumpAndSettle();
          expect(repository.current.status, AuthStatus.guest);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Widget _app(
  SessionRepository repository,
  WebLoginPresenter presenter, {
  double keyboard = 0,
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    webLoginPresenterProvider.overrideWithValue(presenter),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewInsets: EdgeInsets.only(bottom: keyboard),
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: const Scaffold(body: AccountDialog()),
  ),
);
