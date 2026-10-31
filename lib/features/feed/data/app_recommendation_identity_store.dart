import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/credential_store.dart';
import '../../../domain/app_failure.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/domain/app_session_credentials.dart';
import '../domain/app_recommendation_identity_repository.dart';

/// Device preference and compatibility reader. New tokens belong to SessionRepository.
final class AppRecommendationIdentityStore
    implements AppRecommendationIdentityRepository {
  AppRecommendationIdentityStore({
    required this.database,
    required this.credentials,
    required this.accountScope,
    required Stream<AuthState> accountChanges,
    this.sessionCredentials,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _subscription = accountChanges.listen((state) {
      if (state.status != AuthStatus.guest &&
          state.status != AuthStatus.signedIn) {
        return;
      }
      final scope = accountScope();
      final changed = _observedScope != null && _observedScope != scope;
      _observedScope = scope;
      _revision++;
      if (state.status == AuthStatus.guest ||
          changed ||
          _legacy != null && _legacy?.mid != state.mid ||
          sessionCredentials?.appCredentials != null) {
        _legacy = null;
        _discarded = true;
        unawaited(
          _queue(_deleteLegacy).catchError((Object _) {
            _storageFailure = true;
            _emit();
          }),
        );
      }
      _emit();
    });
  }
  final AppDatabase database;
  final CredentialStore credentials;
  final String Function() accountScope;
  final AppSessionCredentialsPort? sessionCredentials;
  final DateTime Function() _clock;
  late final StreamSubscription<AuthState> _subscription;
  final _changes = StreamController<int>.broadcast();
  Future<void>? _loaded;
  Future<void>? _deviceLoaded;
  Future<void> _writes = Future.value();
  AppSessionCredentials? _legacy;
  String _buvid = '';
  String? _observedScope;
  int _revision = 0;
  bool _discarded = false, _closed = false, _storageFailure = false;
  @override
  int get revision => _revision;
  @override
  Stream<int> get changes => _changes.stream;
  void _emit() {
    if (!_closed) _changes.add(_revision);
  }

  Future<void> _queue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _ensureLoaded() =>
      _loaded ??= _read().catchError((Object error, StackTrace stack) {
        _loaded = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void> _read() async {
    await _ensureDevice();
    await _readLegacy();
  }

  Future<void> _ensureDevice() => _deviceLoaded ??= _readDevice().catchError((
    Object error,
    StackTrace stack,
  ) {
    _deviceLoaded = null;
    Error.throwWithStackTrace(error, stack);
  });
  Future<void> _readDevice() async {
    final saved = await database.readSetting('app-recommendation-device.v1');
    _buvid = saved != null && AppRecommendationIdentity.validBuvid(saved)
        ? saved
        : _generate();
    if (_buvid != saved) {
      await database.writeSetting('app-recommendation-device.v1', _buvid);
    }
  }

  Future<void> _readLegacy() async {
    if (_discarded || sessionCredentials?.appCredentials != null) return;
    final revoked = await database.readSetting(
      'app-recommendation-authorization-revoked.v1',
    );
    if (revoked == 'true') return;
    final raw = await credentials.read();
    if (raw == null || _discarded || _closed) return;
    try {
      final Object? value = jsonDecode(raw);
      if (value is! Map<String, Object?> ||
          value['mid'] is! String ||
          value['accessToken'] is! String ||
          (value['accessToken'] as String).isEmpty ||
          (value['accessToken'] as String).length > 4096 ||
          value['expiresAtMillis'] is! int ||
          (value['expiresAtMillis'] as int) < 0 ||
          (value['expiresAtMillis'] as int) > 8640000000000000) {
        throw const FormatException('Invalid legacy session');
      }
      if (accountScope().startsWith('user:') &&
          accountScope() != 'user:${value['mid']}') {
        return;
      }
      _legacy = AppSessionCredentials(
        mid: value['mid'] as String,
        accessToken: value['accessToken'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          value['expiresAtMillis'] as int,
        ),
        buvid: _buvid,
        invalid: value['invalid'] == true,
      );
    } on FormatException {
      throw const AppFailure(
        AppFailureKind.authentication,
        '旧登录信息无效，请在账号菜单重新登录',
      );
    }
  }

  static String _generate() {
    final random = Random.secure();
    final body = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();
    // Preserve the App device format's three check characters before its body.
    return 'XY${body[2]}${body[12]}${body[22]}$body';
  }

  Future<String> deviceId() async {
    await _ensureDevice();
    return _buvid;
  }

  AppSessionCredentials? get _current {
    final value = sessionCredentials?.appCredentials ?? _legacy;
    return accountScope() == 'user:${value?.mid}' ? value : null;
  }

  bool _expired(AppSessionCredentials value) =>
      value.invalid ||
      value.buvid != _buvid ||
      !value.expiresAt.isAfter(_clock());
  @override
  Future<AppRecommendationIdentity> load() async {
    await _ensureLoaded();
    final current = _current;
    return AppRecommendationIdentity(
      buvid: _buvid,
      authorizedMid: current?.mid,
      expiresAt: current?.expiresAt,
      expired: current != null && _expired(current),
    );
  }

  Future<
    ({String buvid, String? accessToken, String? accountMid, int revision})
  >
  requestIdentity() async {
    await _ensureLoaded();
    final current = _current;
    if (_storageFailure && current == null) {
      throw const AppFailure(AppFailureKind.protocol, '旧登录信息清理失败，请重新登录');
    }
    if (current != null && _expired(current)) {
      throw const AppFailure(
        AppFailureKind.authentication,
        'App 登录信息已失效，请在账号菜单重新登录',
      );
    }
    return (
      buvid: _buvid,
      accessToken: current?.accessToken,
      accountMid: current?.mid,
      revision: _revision,
    );
  }

  Future<void> _deleteLegacy() async {
    try {
      try {
        await database.writeSetting(
          'app-recommendation-authorization-revoked.v1',
          'true',
        );
      } finally {
        await credentials.delete();
      }
      _storageFailure = false;
    } catch (_) {
      _storageFailure = true;
      rethrow;
    }
  }

  @override
  Future<void> setBuvid(String value) async {
    if (!AppRecommendationIdentity.validBuvid(value)) {
      throw ArgumentError('Invalid device identity');
    }
    await _ensureLoaded();
    if (value == _buvid) return;
    await _queue(() async {
      await database.writeSetting('app-recommendation-device.v1', value);
      _buvid = value;
      _legacy = null;
      _discarded = true;
      _revision++;
      _emit();
      final current = sessionCredentials?.appCredentials;
      if (current != null) {
        await sessionCredentials?.invalidateAppCredentials(current);
      }
      await _deleteLegacy();
    });
  }

  @override
  Future<void> randomizeBuvid() => setBuvid(_generate());
  Future<void> invalidateAuthorization() async {
    final current = sessionCredentials?.appCredentials;
    if (current != null) {
      await sessionCredentials?.invalidateAppCredentials(current);
      return;
    }
    await _queue(() async {
      final old = _legacy;
      if (old == null) return;
      _legacy = AppSessionCredentials(
        mid: old.mid,
        accessToken: old.accessToken,
        expiresAt: old.expiresAt,
        buvid: old.buvid,
        invalid: true,
      );
      _revision++;
      _emit();
      await credentials.write(
        jsonEncode({
          'schemaVersion': 1,
          'mid': old.mid,
          'accessToken': old.accessToken,
          'expiresAtMillis': old.expiresAt.millisecondsSinceEpoch,
          'invalid': true,
        }),
      );
    });
  }

  Future<void> close() async {
    _closed = true;
    await _subscription.cancel();
    await _loaded?.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await _writes;
    await _changes.close();
  }
}
