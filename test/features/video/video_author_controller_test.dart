import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';
import 'package:bilisail/features/video/presentation/video_author_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = VideoAuthorId('42');
  final provider = videoAuthorControllerProvider(id);
  late _Auth auth;
  late _Repository repo;
  late ProviderContainer container;
  late VideoAuthorController controller;
  setUp(() async {
    auth = _Auth();
    repo = _Repository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        videoAuthorRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(provider, (_, _) {});
    controller = container.read(provider.notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    auth.stream.close();
  });
  VideoAuthorState state() => container.read(provider);

  test(
    'follow is explicit, deduplicates clicks, then allows unfollow',
    () async {
      expect(repo.writes, isEmpty);
      repo.writePending = Completer<void>();
      final first = controller.toggleFollow();
      await controller.toggleFollow();
      expect(repo.writes, [true]);
      expect(state().author?.following, false);
      repo.writePending!.complete();
      await first;
      expect(state().author?.following, true);
      await controller.toggleFollow();
      expect(repo.writes, [true, false]);
      expect(state().author?.following, false);
    },
  );
  test('unknown outcome requires a read before another write', () async {
    repo.failure = const UnknownWriteOutcome();
    await controller.toggleFollow();
    expect(state().uncertain, true);
    await controller.toggleFollow();
    expect(repo.writes, hasLength(1));
    repo.failure = null;
    repo.value = const VideoAuthor(following: true);
    await controller.refresh();
    expect(state().uncertain, false);
    await controller.toggleFollow();
    expect(repo.writes, [true, false]);
  });
  test('same account with a new session rejects an old write', () async {
    repo.writePending = Completer<void>();
    final write = controller.toggleFollow();
    repo.epoch++;
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '1'));
    await Future<void>.delayed(Duration.zero);
    repo.writePending!.complete();
    await write;
    expect(state().author, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(state().author?.following, false);
    expect(state().busy, false);
    expect(state().message, isNull);
  });
  test('logout cancels reads and rejects the previous relationship', () async {
    final pending = Completer<VideoAuthor>();
    repo.readPending = pending;
    final read = controller.refresh();
    final cancellation = repo.cancellations.last;
    repo.readPending = null;
    repo.scope = 'guest';
    repo.epoch++;
    auth.emit(const AuthState());
    await Future<void>.delayed(Duration.zero);
    pending.complete(const VideoAuthor(following: true));
    await read;
    expect(cancellation.isCancelled, true);
    expect(state().signedIn, false);
    expect(state().author?.following, false);
    await controller.toggleFollow();
    expect(repo.writes, isEmpty);
  });
  test(
    'cannot follow self and cancelled requests do not show an error',
    () async {
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '42'));
      await Future<void>.delayed(Duration.zero);
      await controller.toggleFollow();
      expect(repo.writes, isEmpty);
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '1'));
      await Future<void>.delayed(Duration.zero);
      repo.failure = const AppFailure(AppFailureKind.cancelled, '取消');
      await controller.toggleFollow();
      expect(state().busy, false);
      expect(state().message, isNull);
    },
  );

  testWidgets(
    'header displays author totals, supports follow and guest login at large text',
    (tester) async {
      var logins = 0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 600);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child ?? const SizedBox(),
            ),
            home: Scaffold(
              body: VideoAuthorHeader(
                video: const VideoDetail(
                  summary: VideoSummary(
                    id: VideoId('BV1234567890'),
                    title: '视频',
                    coverUrl: '',
                    author: '测试UP',
                    duration: Duration.zero,
                  ),
                  description: '',
                  parts: [],
                  authorMid: '42',
                  likeCount: 999,
                ),
                onLogin: () => logins++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7.1万粉丝 · 21.4万获赞'), findsOneWidget);
      expect(find.textContaining('999'), findsNothing);
      await tester.tap(find.text('关注'));
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsOneWidget);
      auth.emit(const AuthState());
      await tester.pumpAndSettle();
      await tester.tap(find.text('关注'));
      expect(logins, 1);
      expect(repo.writes, [true]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
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

final class _Repository implements VideoAuthorRepository {
  String scope = 'user:1';
  int epoch = 0;
  final writes = <bool>[];
  final cancellations = <RequestCancellation>[];
  Completer<void>? writePending;
  Completer<VideoAuthor>? readPending;
  Object? failure;
  VideoAuthor value = const VideoAuthor(
    following: false,
    followerCount: 70700,
    likeCount: 214000,
  );
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<VideoAuthor> load(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async {
    cancellations.add(cancellation);
    return readPending == null ? value : await readPending!.future;
  }

  @override
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  ) async {
    writes.add(following);
    if (failure case final Object error) throw error;
    await writePending?.future;
  }
}
