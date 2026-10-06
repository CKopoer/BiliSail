import 'dart:async';
import 'dart:convert';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../core/storage/credential_store.dart';
import '../../../domain/app_failure.dart';
import '../domain/auth_repository.dart';

class SessionRepository implements WebAuthRepository {
  SessionRepository({
    required this.api,
    required this.requests,
    required this.credentials,
    required this.onSessionChanged,
    BiliApiClient Function()? loginClientFactory,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 2),
  }) : _loginClientFactory = loginClientFactory ?? (() => BiliApiClient()),
       _clock = clock ?? DateTime.now;

  final BiliApiClient api;
  final ApiRequests requests;
  final CredentialStore credentials;
  final Future<void> Function(String oldScope) onSessionChanged;
  final BiliApiClient Function() _loginClientFactory;
  final Duration pollInterval;
  final DateTime Function() _clock;
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
          decoded['version'] != 1 ||
          decoded['cookies'] is! Map<String, Object?> ||
          decoded['mid'] is! String) {
        throw const FormatException('Invalid secure session');
      }
      api.cookieJar.restoreFromSecureStorage(
        decoded['cookies'] as Map<String, Object?>,
      );
      final name = decoded['name'] is String
          ? decoded['name'] as String
          : '哔哩哔哩用户';
      try {
        final nav = await requests.run(
          (context) => api.getNav(context: context),
        );
        if (generation != _generation) return;
        if (!nav.isLogin || nav.mid == null) {
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
      final qr = await client.generateQr(context: context);
      if (generation != _generation) return;
      _emit(AuthState(status: AuthStatus.waitingScan, qrUri: qr.url));
      while (generation == _generation && _clock().isBefore(deadline)) {
        await Future.any([
          Future<void>.delayed(pollInterval),
          cancellation.whenCancelled,
        ]);
        if (generation != _generation || cancellation.isCancelled) return;
        final result = await client.pollQr(qr.key, context: context);
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
            await _completeLogin(client, context, generation);
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
    int generation,
  ) async {
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
    final snapshot = client.cookieJar.exportForSecureStorage();
    // Keep secure write, account cleanup and promotion in one queue operation.
    // A cancelled cleanup must roll back before a newer login can write.
    await _credentialOperation(() async {
      if (generation != _generation) return;
      try {
        await credentials.write(
          jsonEncode({
            'version': 1,
            'mid': nav.mid,
            'name': nav.name,
            'avatarUrl': nav.avatarUrl?.toString(),
            'cookies': snapshot,
          }),
        );
        if (generation != _generation) {
          await credentials.delete();
          return;
        }
        final oldScope = _scope;
        requests.advanceSession();
        await onSessionChanged(oldScope);
        if (generation != _generation) {
          await credentials.delete();
          return;
        }
        api.cookieJar.restoreFromSecureStorage(snapshot);
        _scope = 'user:${nav.mid}';
        _webAttempt = null;
        _emit(
          AuthState(
            status: AuthStatus.signedIn,
            userName: nav.name ?? '哔哩哔哩用户',
            avatarUrl: nav.avatarUrl,
            mid: nav.mid,
          ),
        );
      } catch (_) {
        // A storage implementation may fail after a partial secure write.
        if (generation == _generation) {
          requests.advanceSession();
          api.cookieJar.clear();
          _scope = 'guest';
        }
        await credentials.delete();
        rethrow;
      }
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
