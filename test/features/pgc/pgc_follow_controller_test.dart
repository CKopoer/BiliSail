import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_follow_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_follow_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pgc_follow_fake.dart';

const _id = PgcSeasonId('9007199254740993');
final _provider = pgcFollowControllerProvider(_id);
Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  test('guest cannot read or mutate account follow state', () async {
    final h = _Harness(signedIn: false);
    addTearDown(h.dispose);
    await _turn();
    expect(h.state.signedIn, isFalse);
    expect(await h.controller.toggle(), isFalse);
    await h.controller.refresh();
    expect(h.repo.reads, isEmpty);
    expect(h.repo.writes, isEmpty);
  });

  test('follow and unfollow publish only after each write succeeds', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _turn();
    expect(h.state.followed, isFalse);
    h.repo.pendingWrite = Completer<void>();
    final result = h.controller.toggle();
    expect(h.state.busy, isTrue);
    expect(h.state.followed, isFalse);
    expect(await h.controller.toggle(), isFalse);
    await h.controller.refresh();
    expect(h.repo.reads, hasLength(1));
    expect(h.repo.writes, [(_id, true)]);
    h.repo.pendingWrite!.complete();
    expect(await result, isTrue);
    expect(h.state.followed, isTrue);
    expect(await h.controller.toggle(), isTrue);
    expect(h.state.followed, isFalse);
    expect(h.repo.writes, [(_id, true), (_id, false)]);
  });

  test(
    'failed read blocks writes until a successful explicit refresh',
    () async {
      final h = _Harness(
        repo: PgcFollowFake()
          ..readFailure = const AppFailure(AppFailureKind.network, '状态读取失败'),
      );
      addTearDown(h.dispose);
      await _turn();
      expect(h.state.followed, isNull);
      expect(h.state.message, '状态读取失败');
      expect(await h.controller.toggle(), isFalse);
      h.repo.readFailure = null;
      h.repo.followed = true;
      await h.controller.refresh();
      expect(h.state.followed, isTrue);
      expect(h.state.message, isNull);
      expect(h.repo.writes, isEmpty);
    },
  );

  test('known rejection preserves the original state and error', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _turn();
    h.repo.writeFailure = const AppFailure(
      AppFailureKind.authentication,
      '登录失效',
    );
    expect(await h.controller.toggle(), isFalse);
    expect(h.state.followed, isFalse);
    expect(h.state.busy, isFalse);
    expect(h.state.uncertain, isFalse);
    expect(h.state.message, '登录失效');
    expect(h.repo.writes, hasLength(1));
  });

  test(
    'unknown write outcome requires a read before another mutation',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await _turn();
      h.repo.writeFailure = const PgcFollowWriteUncertain();
      expect(await h.controller.toggle(), isFalse);
      expect(h.state.uncertain, isTrue);
      expect(h.state.followed, isNull);
      expect(await h.controller.toggle(), isFalse);
      expect(h.repo.writes, hasLength(1));
      h.repo.writeFailure = null;
      h.repo.followed = true;
      await h.controller.refresh();
      expect(h.state.followed, isTrue);
      expect(h.state.uncertain, isFalse);
      expect(h.repo.writes, hasLength(1));
    },
  );

  test('a newer state read supersedes an older pending response', () async {
    final pending = Completer<bool>();
    final h = _Harness(repo: PgcFollowFake()..pendingRead = pending);
    addTearDown(h.dispose);
    await _turn();
    final cancellation = h.repo.lastCancellation;
    h.repo.pendingRead = null;
    h.repo.followed = true;
    await h.controller.refresh();
    pending.complete(false);
    await _turn();
    expect(cancellation?.isCancelled, isTrue);
    expect(h.state.followed, isTrue);
  });

  for (final operation in ['read', 'write']) {
    test(
      'logout cancels pending $operation and drops its late result',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await _turn();
        final pendingRead = Completer<bool>();
        final pendingWrite = Completer<void>();
        h.repo.pendingRead = pendingRead;
        h.repo.pendingWrite = pendingWrite;
        final result = operation == 'read'
            ? h.controller.refresh()
            : h.controller.toggle();
        final cancellation = h.repo.lastCancellation;
        h.repo.accountScope = 'guest';
        h.repo.sessionEpoch++;
        h.auth.emit(const AuthState());
        await _turn();
        expect(cancellation?.isCancelled, isTrue);
        pendingRead.complete(true);
        pendingWrite.complete();
        await result;
        expect(h.state.signedIn, isFalse);
        expect(h.state.followed, isNull);
        expect(h.state.message, isNull);
      },
    );
  }

  test(
    'epoch change before a click refreshes instead of writing stale state',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await _turn();
      h.repo.sessionEpoch++;
      h.repo.followed = true;
      expect(await h.controller.toggle(), isFalse);
      expect(h.state.followed, isTrue);
      expect(h.repo.writes, isEmpty);
    },
  );

  test('disposing the provider cancels its outstanding request', () async {
    final pending = Completer<bool>();
    final h = _Harness(repo: PgcFollowFake()..pendingRead = pending);
    await _turn();
    final cancellation = h.repo.lastCancellation;
    h.dispose();
    pending.complete(true);
    await _turn();
    expect(cancellation?.isCancelled, isTrue);
  });
}

class _Harness {
  _Harness({bool signedIn = true, PgcFollowFake? repo})
    : repo = repo ?? PgcFollowFake(),
      auth = _Auth(signedIn) {
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pgcFollowRepositoryProvider.overrideWithValue(this.repo),
      ],
    );
    container.listen(_provider, (_, _) {});
  }
  final PgcFollowFake repo;
  final _Auth auth;
  late final ProviderContainer container;
  PgcFollowState get state => container.read(_provider);
  PgcFollowController get controller => container.read(_provider.notifier);
  void dispose() {
    container.dispose();
    auth.events.close();
  }
}

class _Auth implements AuthRepository {
  _Auth(bool signedIn)
    : current = signedIn
          ? const AuthState(status: AuthStatus.signedIn, mid: '7')
          : const AuthState();
  @override
  AuthState current;
  final events = StreamController<AuthState>.broadcast(sync: true);
  @override
  Stream<AuthState> get changes => events.stream;
  void emit(AuthState state) {
    current = state;
    events.add(state);
  }

  @override
  void cancelSignIn() {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async => emit(const AuthState());
}
