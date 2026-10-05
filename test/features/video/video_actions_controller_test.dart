import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/application/video_actions_controller.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const target = (id: VideoId('BV1234567890'), aid: '42');
  late _Auth auth;
  late _Repository repo;
  late ProviderContainer container;
  late VideoActionsController controller;
  setUp(() async {
    auth = _Auth();
    repo = _Repository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        videoActionsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(videoActionsControllerProvider(target), (_, _) {});
    controller = container.read(
      videoActionsControllerProvider(target).notifier,
    );
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    auth.stream.close();
  });
  VideoActionsState state() =>
      container.read(videoActionsControllerProvider(target));
  test('account change rejects late refresh response', () async {
    repo.readPending = Completer<VideoInteraction>();
    final read = controller.refresh();
    repo.scope = 'guest';
    auth.emit(const AuthState());
    await Future<void>.delayed(Duration.zero);
    repo.readPending!.complete(const VideoInteraction(liked: true, coins: 2));
    await read;
    expect(state().signedIn, false);
    expect(state().interaction.liked, false);
    expect(state().interaction.coins, 0);
  });
  test('cancelled refresh clears loading without an error toast', () async {
    repo.readFailure = const AppFailure(AppFailureKind.cancelled, '请求已取消');
    await controller.refresh();
    expect(state().loading, false);
    expect(state().message, isNull);
  });
  test(
    'busy prevents duplicate writes and successful result updates state',
    () async {
      repo.pending = Completer<void>();
      final first = controller.toggleLike();
      expect(state().busy, true);
      expect(await controller.toggleLike(), false);
      expect(repo.writes, 1);
      repo.pending!.complete();
      expect(await first, true);
      expect(state().interaction.liked, true);
      expect(state().busy, false);
    },
  );
  test(
    'unknown result blocks replay until a successful read reconciles',
    () async {
      repo.failure = const UnknownWriteOutcome();
      expect(await controller.toggleLike(), false);
      expect(state().uncertain, contains('like'));
      expect(await controller.toggleLike(), false);
      expect(repo.writes, 1);
      repo.failure = null;
      repo.value = const VideoInteraction(liked: true);
      await controller.refresh();
      expect(state().interaction.liked, true);
      expect(state().uncertain, isEmpty);
      expect(await controller.toggleLike(), true);
      expect(repo.writes, 2);
    },
  );
  test('sending cannot be reconciled by video interaction reads', () async {
    repo.failure = const UnknownWriteOutcome();
    expect(await controller.send('8', '测试', Duration.zero, 1, 0xffffff), false);
    repo.failure = null;
    await controller.refresh();
    expect(state().uncertain, contains('send'));
    expect(await controller.send('8', '测试', Duration.zero, 1, 0xffffff), false);
    expect(repo.writes, 1);
  });
  test('account change rejects late successful write', () async {
    repo.pending = Completer<void>();
    final first = controller.toggleLike();
    repo.scope = 'user:2';
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '2'));
    await Future<void>.delayed(Duration.zero);
    repo.pending!.complete();
    expect(await first, false);
    expect(state().interaction.liked, false);
    expect(state().message, isNull);
  });
  test('guest cannot submit any mutation', () async {
    auth.emit(const AuthState());
    await Future<void>.delayed(Duration.zero);
    expect(await controller.watchLater(), false);
    expect(await controller.toggleLike(), false);
    expect(repo.writes, 0);
  });
  test(
    'cancelled write does not claim success or leave actions busy',
    () async {
      repo.failure = const AppFailure(AppFailureKind.cancelled, '请求已取消');
      expect(await controller.watchLater(), false);
      expect(state().message, isNull);
      expect(state().watchLaterAdded, false);
      expect(state().busy, false);
    },
  );
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

final class _Repository implements VideoActionsRepository {
  String scope = 'user:1';
  int writes = 0;
  Object? failure;
  Completer<void>? pending;
  VideoInteraction value = const VideoInteraction();
  Completer<VideoInteraction>? readPending;
  Object? readFailure;
  @override
  String get accountScope => scope;
  Future<void> write() async {
    writes++;
    if (failure case final Object error) throw error;
    await pending?.future;
  }

  @override
  Future<VideoInteraction> load(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) async {
    if (readFailure case final Object e) throw e;
    return readPending == null ? value : await readPending!.future;
  }

  @override
  Future<List<FavoriteFolder>> folders(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) async => const [];
  @override
  Future<void> like(
    VideoActionTarget target,
    bool liked,
    RequestCancellation cancellation,
  ) => write();
  @override
  Future<void> coin(
    VideoActionTarget target,
    int count,
    RequestCancellation cancellation,
  ) => write();
  @override
  Future<void> favorite(
    VideoActionTarget target,
    List<String> add,
    List<String> remove,
    RequestCancellation cancellation,
  ) => write();
  @override
  Future<void> watchLater(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) => write();
  @override
  Future<void> sendDanmaku(
    VideoActionTarget target,
    String cid,
    String message,
    Duration position,
    int mode,
    int color,
    RequestCancellation cancellation,
  ) => write();
}
