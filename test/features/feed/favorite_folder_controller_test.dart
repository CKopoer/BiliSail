import 'dart:async';

import 'package:bili_lite/domain/app_failure.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/features/auth/domain/auth_repository.dart';
import 'package:bili_lite/features/feed/application/favorite_folder_controller.dart';
import 'package:bili_lite/features/feed/domain/favorite_folder_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = (id: '42', scope: 'user:1');
const _original = FavoriteFolderInfo(
  id: '42',
  title: '音乐',
  intro: '原简介',
  isPrivate: true,
);
const _edit = FavoriteFolderEdit(title: '新名称', intro: '新简介', isPrivate: false);

void main() {
  late _Auth auth;
  late _Repository repo;
  late ProviderContainer container;
  late FavoriteFolderController controller;
  FavoriteFolderEditorState state() =>
      container.read(favoriteFolderControllerProvider(_target));
  setUp(() async {
    auth = _Auth();
    repo = _Repository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        favoriteFolderRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(favoriteFolderControllerProvider(_target), (_, _) {});
    controller = container.read(
      favoriteFolderControllerProvider(_target).notifier,
    );
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  test(
    'busy blocks duplicate submissions, and refresh cannot interrupt save',
    () async {
      repo.writePending = Completer<void>();
      final first = controller.save(_edit);
      expect(state().busy, true);
      expect(await controller.save(_edit), false);
      expect(await controller.refresh(), false);
      expect(repo.writes, 1);
      expect(repo.signal?.isCancelled, false);
      repo.writePending?.complete();
      expect(await first, true);
      expect(state().info?.title, _edit.title);
      expect(state().info?.isPrivate, false);
    },
  );
  test(
    'validation prevents blank names and preserves editable details',
    () async {
      expect(
        await controller.save(
          const FavoriteFolderEdit(title: '  ', intro: '', isPrivate: false),
        ),
        false,
      );
      expect(state().info, _original);
      expect(repo.writes, 0);
    },
  );
  test(
    'unknown outcome blocks replay and matching server read confirms save',
    () async {
      repo.failure = const FavoriteFolderWriteUncertain();
      expect(await controller.save(_edit), false);
      expect(state().uncertain, true);
      expect(await controller.save(_edit), false);
      repo.info = const FavoriteFolderInfo(
        id: '42',
        title: '新名称',
        intro: '新简介',
        isPrivate: false,
      );
      expect(await controller.refresh(), true);
      expect(state().uncertain, false);
      expect(repo.writes, 1);
    },
  );
  test(
    'nonmatching read permits a new explicit save without automatic retry',
    () async {
      repo.failure = const FavoriteFolderWriteUncertain();
      await controller.save(_edit);
      expect(await controller.refresh(), false);
      expect(state().info, _original);
      expect(state().uncertain, false);
      expect(repo.writes, 1);
      repo.failure = null;
      expect(await controller.save(_edit), true);
      expect(repo.writes, 2);
    },
  );
  test('failed reconciliation leaves uncertain writes blocked', () async {
    repo.failure = const FavoriteFolderWriteUncertain();
    await controller.save(_edit);
    repo.readFailure = const AppFailure(AppFailureKind.network, '无法连接');
    expect(await controller.refresh(), false);
    expect(state().uncertain, true);
    expect(await controller.save(_edit), false);
    expect(repo.writes, 1);
  });
  test('account change clears private details and ignores late read', () async {
    repo.readPending = Completer<FavoriteFolderInfo>();
    final read = controller.refresh();
    repo.scope = 'user:2';
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '2'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.signal?.isCancelled, true);
    repo.readPending?.complete(_original);
    expect(await read, false);
    expect(state().info, isNull);
    expect(state().active, false);
  });
  test('same-account epoch change rejects late successful write', () async {
    repo.writePending = Completer<void>();
    final write = controller.save(_edit);
    repo.epoch++;
    repo.writePending?.complete();
    expect(await write, false);
    expect(state().info, isNull);
    expect(state().active, false);
  });
  test('stale loaded epoch and guest cannot submit', () async {
    repo.epoch++;
    expect(await controller.save(_edit), false);
    expect(repo.writes, 0);
    repo.scope = 'guest';
    auth.emit(const AuthState());
    await Future<void>.delayed(Duration.zero);
    expect(await controller.save(_edit), false);
    expect(repo.writes, 0);
  });
  test('disposal cancels an active save and rejects its result', () async {
    repo.writePending = Completer<void>();
    final write = controller.save(_edit);
    container.dispose();
    expect(repo.signal?.isCancelled, true);
    repo.writePending?.complete();
    expect(await write, false);
  });
}

final class _Auth implements AuthRepository {
  final stream = StreamController<AuthState>.broadcast(sync: true);
  AuthState value = const AuthState(status: AuthStatus.signedIn, mid: '1');
  void emit(AuthState next) {
    value = next;
    stream.add(next);
  }

  @override
  AuthState get current => value;
  @override
  Stream<AuthState> get changes => stream.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async => emit(const AuthState());
}

final class _Repository implements FavoriteFolderRepository {
  String scope = 'user:1';
  int epoch = 1;
  int writes = 0;
  FavoriteFolderInfo info = _original;
  RequestCancellation? signal;
  Object? failure, readFailure;
  Completer<void>? writePending;
  Completer<FavoriteFolderInfo>? readPending;
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<FavoriteFolderInfo> load(
    FavoriteFolderTarget target,
    RequestCancellation c,
  ) async {
    signal = c;
    if (readFailure case final error?) throw error;
    return readPending == null ? info : await readPending!.future;
  }

  @override
  Future<void> update(
    FavoriteFolderTarget target,
    FavoriteFolderEdit edit,
    RequestCancellation c,
  ) async {
    signal = c;
    writes++;
    if (failure case final error?) throw error;
    await writePending?.future;
  }
}
