import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../core/storage/credential_store.dart';
import '../../../domain/app_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/app_session_credentials.dart';

class SessionRepository
    implements WebAuthRepository, AppSessionCredentialsPort {
  SessionRepository({
    required this.api,
    required this.requests,
    required this.credentials,
    required this.onSessionChanged,
    BiliApiClient Function()? loginClientFactory,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 2),
    this.loadAppDevice,
  }) : _loginClientFactory = loginClientFactory ?? (() => BiliApiClient()),
       _clock = clock ?? DateTime.now;

  final BiliApiClient api;
  final ApiRequests requests;
  final CredentialStore credentials;
  final Future<void> Function(String oldScope) onSessionChanged;
  final BiliApiClient Function() _loginClientFactory;
  final Duration pollInterval;
  final DateTime Function() _clock;
  final Future<String> Function()? loadAppDevice;
  late final String _fallbackDevice =
      'XY${List.generate(35, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';
  AppSessionCredentials? _appCredentials;
  @override
  AppSessionCredentials? get appCredentials =>
      _current.isSignedIn ? _appCredentials : null;
  bool get _hasApp => switch (_appCredentials) {
    final value? when !value.invalid && value.expiresAt.isAfter(_clock()) =>
      true,
    _ => false,
  };
  final _changes = StreamController<AuthState>.broadcast();
  AuthState _current = const AuthState();
  String _scope = 'guest';
  int _generation = 0;
  ApiCancellation? _loginCancellation;
  Future<void> _credentialQueue = Future.value();
  bool _disposed = false;
  WebLoginAttempt? _webAttempt;

  String get accountScope => _scope;
  @override
  AuthState get current => _current;
  @override
  Stream<AuthState> get changes => _changes.stream;

  void _emit(AuthState state) {
    if (_disposed) return;
    _current = state;
    _changes.add(state);
  }

  Future<void> _credentialOperation(Future<void> Function() action) {
    final task = _credentialQueue.then((_) => action());
    _credentialQueue = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace stackTrace) {},
    );
    return task;
  }

  @override
  Future<void> restore() async {
    final generation = ++_generation;
    requests.advanceSession();
    api.cookieJar.clear();
    _appCredentials = null;
    _scope = 'guest';
    _emit(const AuthState(status: AuthStatus.restoring));
    try {
      final saved = await credentials.read();
      if (generation != _generation) return;
      if (saved == null) {
        _emit(const AuthState());
        return;
      }
      final Object? decoded = jsonDecode(saved);
      if (decoded is! Map<String, Object?> ||
          !const {1, 2}.contains(decoded['version']) ||
          decoded['cookies'] is! Map<String, Object?> ||
          decoded['mid'] is! String) {
        throw const FormatException('Invalid secure session');
      }
      api.cookieJar.restoreFromSecureStorage(
        decoded['cookies'] as Map<String, Object?>,
      );
      final app = decoded['app'];
      if (app != null) {
        if (app is! Map<String, Object?> ||
            app['mid'] != decoded['mid'] ||
            app['accessToken'] is! String ||
            (app['accessToken'] as String).isEmpty ||
            (app['accessToken'] as String).length > 4096 ||
            app['expiresAtMillis'] is! int ||
            (app['expiresAtMillis'] as int) < 0 ||
            (app['expiresAtMillis'] as int) > 8640000000000000 ||
            app['buvid'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{16,128}$')
                .hasMatch(app['buvid'] as String) ||
            (app['refreshToken'] != null &&
                (app['refreshToken'] is! String ||
                    (app['refreshToken'] as String).length > 4096))) {
          throw const FormatException('Invalid App session');
        }
        _appCredentials = AppSessionCredentials(
          mid: app['mid'] as String,
          accessToken: app['accessToken'] as String,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            app['expiresAtMillis'] as int,
          ),
          buvid: app['buvid'] as String,
          refreshToken: app['refreshToken'] as String?,
          invalid: app['invalid'] == true,
        );
      }
      final name = decoded['name'] is String
          ? decoded['name'] as String
          : '哔哩哔哩用户';
      try {
        final nav = await requests.run(
          (context) => api.getNav(context: context),
        );
        if (generation != _generation) return;
        if (!nav.isLogin || nav.mid == null || nav.mid != decoded['mid']) {
          _scope = 'user:${decoded['mid']}';
          await signOut();
          return;
        }
        _scope = 'user:${nav.mid}';
        _emit(
          AuthState(
            status: AuthStatus.signedIn,
            userName: nav.name ?? name,
            avatarUrl: nav.avatarUrl,
            mid: nav.mid,
            appSessionAvailable: _hasApp,
          ),
        );
      } on AppFailure catch (error) {
        if (generation != _generation) return;
        if (error.kind == AppFailureKind.authentication) {
          _scope = 'user:${decoded['mid']}';
          await signOut();
          return;
        }
        if (error.kind == AppFailureKind.network ||
            error.kind == AppFailureKind.timeout) {
          // Preserve encrypted credentials only when validation is unreachable.
          _scope = 'user:${decoded['mid']}';
          _emit(
            AuthState(
              status: AuthStatus.signedIn,
              userName: name,
              mid: decoded['mid'] as String,
              avatarUrl: decoded['avatarUrl'] is String
                  ? Uri.tryParse(decoded['avatarUrl'] as String)
                  : null,
              message: '已恢复本地会话，联网后将重新验证权限',
              appSessionAvailable: _hasApp,
            ),
          );
          return;
        }
        api.cookieJar.clear();
        _emit(const AuthState(message: '暂时无法验证本地会话，请稍后重试'));
      }
    } catch (_) {
      if (generation != _generation) return;
      api.cookieJar.clear();
      _scope = 'guest';
      _emit(const AuthState(message: '无法读取安全存储，已使用游客模式；登录信息未写入普通文件'));
    }
  }

  @override
  Future<void> signIn() async {
    if (_current.isSignedIn || _current.isBusy) return;
    cancelSignIn();
    final generation = ++_generation;
    final cancellation = ApiCancellation();
    _loginCancellation = cancellation;
    final client = _loginClientFactory();
    final deadline = _clock().add(const Duration(minutes: 3));
    final context = ApiRequestContext(
      cancellation: cancellation,
      deadline: deadline,
    );
    _emit(const AuthState(status: AuthStatus.creatingQr));
    try {
      final device = await loadAppDevice?.call() ?? _fallbackDevice;
      if (generation != _generation) return;
      final passport = AppPassportClient(client, clock: _clock);
      final qr = await passport.generate(buvid: device, context: context);
      if (generation != _generation) return;
      _emit(AuthState(status: AuthStatus.waitingScan, qrUri: qr.url));
      while (generation == _generation && _clock().isBefore(deadline)) {
        await Future.any([
          Future<void>.delayed(pollInterval),
          cancellation.whenCancelled,
        ]);
        if (generation != _generation || cancellation.isCancelled) return;
        final result = await passport.poll(
          buvid: device,
          authCode: qr.authCode,
          context: context,
        );
        if (generation != _generation) return;
        switch (result.status) {
          case ApiQrStatus.waitingScan:
            break;
          case ApiQrStatus.waitingConfirm:
            _emit(AuthState(status: AuthStatus.waitingConfirm, qrUri: qr.url));
          case ApiQrStatus.expired:
            _emit(
              const AuthState(
                status: AuthStatus.expired,
                message: '二维码已过期，请刷新',
              ),
            );
            return;
          case ApiQrStatus.confirmed:
            if (result.credentials == null || result.cookies.isEmpty) {
              throw const ApiFailure(
                ApiFailureCategory.protocol,
                'unified_login',
              );
            }
            client.cookieJar.restoreFromSecureStorage({
              'version': 1,
              'cookies': [
                for (final cookie in result.cookies)
                  {
                    'name': cookie.name,
                    'value': cookie.value,
                    'domain': cookie.domain,
                    'path': cookie.path,
                    'hostOnly': false,
                    'secure': cookie.secure,
                    'expiresUtc': cookie.expires?.toUtc().toIso8601String(),
                  },
              ],
            });
            await _completeLogin(
              client,
              context,
              generation,
              app: result.credentials,
              device: device,
            );
            return;
        }
      }
      if (generation == _generation) {
        _emit(
          const AuthState(status: AuthStatus.expired, message: '二维码已过期，请刷新'),
        );
      }
    } on ApiFailure catch (error) {
      if (generation == _generation &&
          error.category != ApiFailureCategory.cancelled) {
        _emit(
          AuthState(
            status: AuthStatus.failed,
            message: mapApiFailure(error).message,
          ),
        );
      }
    } catch (_) {
      if (generation == _generation) {
        _emit(
          const AuthState(
            status: AuthStatus.failed,
            message: '登录未完成，请重试；无法安全保存凭据时不会保留登录',
          ),
        );
      }
    } finally {
      cancellation.cancel();
      client.close();
      if (generation == _generation) _loginCancellation = null;
    }
  }

  Future<void> _completeLogin(
    BiliApiClient client,
    ApiRequestContext context,
    int generation, {
    ApiAppCredentials? app,
    String? device,
  }) async {
    final nav = await client.getNav(context: context);
    if (generation != _generation) return;
    if (!nav.isLogin ||
        nav.mid == null ||
        client.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')) ==
            null) {
      throw const ApiFailure(
        ApiFailureCategory.authentication,
        'login_validate',
      );
    }
    AppSessionCredentials? appCredentials;
    if (app != null) {
      if (app.mid != nav.mid || !app.expiresAt.isAfter(_clock())) {
        throw const ApiFailure(
          ApiFailureCategory.authentication,
          'unified_login',
        );
      }
      device ??= await loadAppDevice?.call() ?? _fallbackDevice;
      if (generation != _generation) return;
      appCredentials = AppSessionCredentials(
        mid: app.mid,
        accessToken: app.accessToken,
        refreshToken: app.refreshToken,
        expiresAt: app.expiresAt,
        buvid: device,
      );
    }
    final snapshot = client.cookieJar.exportForSecureStorage();
    // Keep secure write, account cleanup and promotion in one queue operation.
    // A cancelled cleanup must roll back before a newer login can write.
    await _credentialOperation(() async {
      if (generation != _generation) return;
      final oldSaved = _current.isSignedIn ? await credentials.read() : null;
      final oldScope = _scope;
      Future<void> rollback() async {
        if (oldSaved != null && _current.isSignedIn && _scope == oldScope) {
          await credentials.write(oldSaved);
        } else {
          await credentials.delete();
        }
      }

      if (generation != _generation) return;
      try {
        await credentials.write(
          jsonEncode({
            'version': 2,
            'mid': nav.mid,
            'name': nav.name,
            'avatarUrl': nav.avatarUrl?.toString(),
            'cookies': snapshot,
            if (appCredentials != null) 'app': _appSnapshot(appCredentials),
          }),
        );
        if (generation != _generation) {
          await rollback();
          return;
        }
        requests.advanceSession();
        await onSessionChanged(oldScope);
        if (generation != _generation) {
          await rollback();
          return;
        }
        api.cookieJar.restoreFromSecureStorage(snapshot);
        _scope = 'user:${nav.mid}';
        _appCredentials = appCredentials;
        _webAttempt = null;
        _emit(
          AuthState(
            status: AuthStatus.signedIn,
            userName: nav.name ?? '哔哩哔哩用户',
            avatarUrl: nav.avatarUrl,
            mid: nav.mid,
            appSessionAvailable: _hasApp,
          ),
        );
      } catch (_) {
        // A storage implementation may fail after a partial secure write.
        if (generation == _generation) {
          requests.advanceSession();
          api.cookieJar.clear();
          _scope = 'guest';
          _appCredentials = null;
        }
        await credentials.delete();
        rethrow;
      }
    });
  }

  Map<String, Object?> _appSnapshot(AppSessionCredentials value) => {
    'mid': value.mid,
    'accessToken': value.accessToken,
    'refreshToken': value.refreshToken,
    'expiresAtMillis': value.expiresAt.millisecondsSinceEpoch,
    'buvid': value.buvid,
    'invalid': value.invalid,
  };

  @override
  Future<void> invalidateAppCredentials(AppSessionCredentials expected) async {
    if (!identical(_appCredentials, expected)) return;
    final invalid = AppSessionCredentials(
      mid: expected.mid,
      accessToken: expected.accessToken,
      refreshToken: expected.refreshToken,
      expiresAt: expected.expiresAt,
      buvid: expected.buvid,
      invalid: true,
    );
    _appCredentials = invalid;
    final generation = _generation;
    _emit(
      AuthState(
        status: _current.status,
        mid: _current.mid,
        userName: _current.userName,
        avatarUrl: _current.avatarUrl,
      ),
    );
    await _credentialOperation(() async {
      if (generation != _generation ||
          !identical(_appCredentials, invalid) ||
          !_current.isSignedIn) {
        return;
      }
      await credentials.write(
        jsonEncode({
          'version': 2,
          'mid': _current.mid,
          'name': _current.userName,
          'avatarUrl': _current.avatarUrl?.toString(),
          'cookies': api.cookieJar.exportForSecureStorage(),
          'app': _appSnapshot(invalid),
        }),
      );
    });
  }

  @override
  WebLoginAttempt? beginWebLogin() {
    if (_disposed || _current.isSignedIn || _current.isBusy) return null;
    cancelSignIn();
    final attempt = WebLoginAttempt();
    _webAttempt = attempt;
    _emit(const AuthState(status: AuthStatus.waitingWeb));
    return attempt;
  }

  @override
  Future<void> completeWebLogin(
    WebLoginAttempt attempt,
    List<LoginCookie> cookies,
  ) async {
    if (_disposed || !identical(attempt, _webAttempt)) return;
    _webAttempt = null;
    final generation = ++_generation;
    final cancellation = ApiCancellation();
    _loginCancellation = cancellation;
    final client = _loginClientFactory();
    _emit(const AuthState(status: AuthStatus.authenticating));
    try {
      if (cookies.isEmpty ||
          cookies.length > 128 ||
          cookies.any(
            (cookie) =>
                cookie.name.isEmpty ||
                cookie.name.length > 256 ||
                cookie.value.length > 8192 ||
                RegExp(r'[\x00-\x20;,]').hasMatch(cookie.name) ||
                RegExp(r'[\r\n\x00;]').hasMatch(cookie.value),
          )) {
        throw const FormatException('Invalid browser session');
      }
      client.cookieJar.restoreFromSecureStorage({
        'version': 1,
        'cookies': [
          for (final cookie in cookies)
            {
              'name': cookie.name,
              'value': cookie.value,
              'domain': cookie.domain,
              'path': cookie.path,
              'hostOnly': cookie.hostOnly,
              'secure': cookie.secure,
              'expiresUtc': cookie.expires?.toUtc().toIso8601String(),
            },
        ],
      });
      final header = client.cookieJar.headerFor(
        Uri.https('api.bilibili.com', '/'),
      );
      if (header == null || !RegExp(r'(^|; )SESSDATA=[^;]+').hasMatch(header)) {
        throw const FormatException('No applicable browser session');
      }
      await _completeLogin(
        client,
        ApiRequestContext(
          cancellation: cancellation,
          deadline: _clock().add(const Duration(seconds: 25)),
        ),
        generation,
      );
    } on ApiFailure catch (error) {
      if (generation == _generation &&
          error.category != ApiFailureCategory.cancelled) {
        _emit(
          AuthState(
            status: AuthStatus.failed,
            message: mapApiFailure(error).message,
          ),
        );
      }
    } on FormatException {
      if (generation == _generation) {
        _emit(
          const AuthState(
            status: AuthStatus.failed,
            message: '未取得有效的网页登录会话，请重试或使用扫码登录',
          ),
        );
      }
    } catch (_) {
      if (generation == _generation) {
        _emit(
          const AuthState(
            status: AuthStatus.failed,
            message: '登录未完成，请重试；无法安全保存凭据时不会保留登录',
          ),
        );
      }
    } finally {
      cancellation.cancel();
      client.cookieJar.clear();
      client.close();
      if (generation == _generation) _loginCancellation = null;
    }
  }

  @override
  void cancelSignIn() {
    _generation++;
    _loginCancellation?.cancel();
    _loginCancellation = null;
    _webAttempt = null;
    if (!_current.isSignedIn) _emit(const AuthState());
  }

  @override
  Future<void> signOut() async {
    cancelSignIn();
    requests.advanceSession();
    final oldScope = _scope;
    _scope = 'guest';
    _appCredentials = null;
    api.cookieJar.clear();
    _emit(const AuthState());
    var cleanupFailed = false;
    try {
      await onSessionChanged(oldScope);
    } catch (_) {
      cleanupFailed = true;
    }
    try {
      await _credentialOperation(credentials.delete);
      if (cleanupFailed) {
        _emit(const AuthState(message: '已退出登录，但部分会话资源清理失败，请重试'));
      }
    } catch (_) {
      _emit(const AuthState(message: '本次会话已退出，但系统凭据删除失败，请重试退出后再关闭应用'));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    cancelSignIn();
    await _credentialQueue;
    await _changes.close();
  }
}
