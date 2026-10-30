import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/application/profile_playback_queue.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';
import '../../support/follow_repository_fake.dart';

const _id = UserId('7');
ProfileEntry _entry(int index) {
  final video = VideoSummary(
    id: VideoId('BV${index.toString().padLeft(10, '0')}'),
    title: '投稿$index',
    coverUrl: '',
    author: 'UP',
    duration: const Duration(minutes: 1),
  );
  return ProfileEntry(
    id: '$index',
    kind: ProfileEntryKind.video,
    title: video.title,
    video: video,
  );
}

void main() {
  if (const bool.fromEnvironment('PROFILE_TOOLBAR_PREVIEW')) {
    setUpAll(() async {
      await (FontLoader('HarmonyOS Sans')..addFont(
            rootBundle.load(
              'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
            ),
          ))
          .load();
      await (FontLoader(
        'BiliIcons',
      )..addFont(rootBundle.load('assets/fonts/biliicon.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }
  late _Repository repository;
  late AuthFake auth;
  late ProviderContainer container;
  setUp(() {
    repository = _Repository();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(auth),
        videoAuthorRepositoryProvider.overrideWithValue(FollowRepositoryFake()),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  Future<ProfileController> profile() async {
    final sub = container.listen(profileControllerProvider(_id), (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    return container.read(profileControllerProvider(_id).notifier);
  }

  WatchLaterQueue capture({int count = 2}) => container
      .read(watchLaterQueueRegistryProvider)
      .capture(
        scope: repository.accountScope,
        sessionEpoch: repository.sessionEpoch,
        items: [
          for (var i = 0; i < count; i++)
            WatchLaterQueueItem(video: _entry(i).video!),
        ],
        profileSource: const ProfileVideoQueueSource(
          userId: _id,
          name: 'UP',
          order: 'click',
        ),
        hasMore: true,
        nextPage: 2,
      )!;
  ProfilePlaybackQueueController paging(WatchLaterQueue queue) {
    final sub = container.listen(
      profilePlaybackQueueProvider(queue.id),
      (_, _) {},
    );
    addTearDown(sub.close);
    return container.read(profilePlaybackQueueProvider(queue.id).notifier);
  }

  test('play all starts from page one with the selected sort and no search, including guests', () async {
    final controller = await profile();
    controller.filter(order: 'click', keyword: '只搜部分投稿');
    await Future<void>.delayed(Duration.zero);
    repository.calls.clear();
    final queue = await controller.playAll();
    expect(queue, isNotNull);
    expect(repository.calls.single, (page: 1, order: 'click', keyword: ''));
    expect(queue?.items.map((item) => item.video.id), [
      _entry(0).video?.id,
      _entry(1).video?.id,
    ]);
    expect(queue?.profileSource?.userId, _id);
    expect(queue?.hasMore, true);
    expect(queue?.isWatchLater, false);
    expect(
      queue?.withoutRemoved({'${_entry(0).video?.id.value}'}),
      same(queue),
    );
    expect(container.read(profileControllerProvider(_id)).keyword, '只搜部分投稿');
  });

  test('play all is single flight and discards a late result after account changes', () async {
    final controller = await profile();
    final pending = repository.pending = Completer<ProfilePage>();
    final first = controller.playAll();
    final read = repository.read;
    expect(await controller.playAll(), isNull);
    repository.pending = null;
    repository.sessionEpoch++;
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await Future<void>.delayed(Duration.zero);
    expect(read?.isCancelled, true);
    pending.complete(ProfilePage(items: [_entry(2)], hasMore: false));
    expect(await first, isNull);
    expect(container.read(profileControllerProvider(_id)).queueLoading, false);
  });

  test(
    'empty and failed starts report errors without publishing a queue',
    () async {
      final controller = await profile();
      repository.items = [];
      expect(await controller.playAll(), isNull);
      expect(
        container.read(profileControllerProvider(_id)).queueMessage,
        contains('暂无'),
      );
      repository.failure = const AppFailure(AppFailureKind.network, '网络暂时不可用');
      expect(await controller.playAll(), isNull);
      expect(
        container.read(profileControllerProvider(_id)).queueMessage,
        '网络暂时不可用',
      );
      repository.failure = null;
      repository.items = [_entry(1)];
      expect(await controller.playAll(), isNotNull);
      expect(
        container.read(profileControllerProvider(_id)).queueMessage,
        isNull,
      );
    },
  );

  test('pagination deduplicates, reads once, preserves sorting and retries the same failed page', () async {
    final queue = capture();
    final controller = paging(queue);
    final pending = repository.pending = Completer<ProfilePage>();
    final first = controller.loadMore(queue.items.first.video.id);
    final second = controller.loadMore(queue.items.first.video.id);
    expect(repository.calls, hasLength(1));
    pending.complete(ProfilePage(items: [_entry(1), _entry(2)], hasMore: true));
    await Future.wait([first, second]);
    repository.pending = null;
    expect(
      container.read(profilePlaybackQueueProvider(queue.id)).queue?.items,
      hasLength(3),
    );
    repository.failure = const AppFailure(AppFailureKind.network, '加载失败');
    await controller.loadMore(queue.items.first.video.id);
    expect(
      container.read(profilePlaybackQueueProvider(queue.id)).message,
      '加载失败',
    );
    repository.failure = null;
    repository.items = [_entry(3)];
    repository.hasMore = false;
    await controller.loadMore(queue.items.first.video.id);
    expect(repository.calls.map((call) => call.page), [2, 3, 3]);
    expect(
      repository.calls.every(
        (call) => call.order == 'click' && call.keyword.isEmpty,
      ),
      true,
    );
    final updated = container
        .read(profilePlaybackQueueProvider(queue.id))
        .queue!;
    expect(updated.items.map((item) => item.video.id), [
      for (var i = 0; i < 4; i++) _entry(i).video?.id,
    ]);
    expect(updated.hasMore, false);
    expect(
      container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            queue.id,
            scope: repository.accountScope,
            sessionEpoch: repository.sessionEpoch,
          ),
      same(updated),
    );
  });

  test('a bounded window drops only played entries and continues beyond 1000 submissions', () async {
    final queue = capture(count: 1000);
    final controller = paging(queue);
    await controller.loadMore(queue.items.first.video.id);
    expect(repository.calls, isEmpty);
    final blocked = container.read(profilePlaybackQueueProvider(queue.id));
    expect(blocked.canPrefetch(queue.items.first.video.id), false);
    expect(blocked.canPrefetch(queue.items[995].video.id), true);
    repository.items = [for (var i = 1000; i < 1030; i++) _entry(i)];
    await controller.loadMore(queue.items[995].video.id);
    final updated = container
        .read(profilePlaybackQueueProvider(queue.id))
        .queue!;
    expect(updated.items, hasLength(1000));
    expect(updated.offset, 30);
    expect(updated.indexOf(queue.items[995].video.id), 965);
    expect(updated.items.last.video.id, _entry(1029).video?.id);
  });

  test('repeated duplicate pages stop automatic paging with an explicit retry message', () async {
    final queue = capture();
    final controller = paging(queue);
    for (var i = 0; i < 3; i++) {
      await controller.loadMore(queue.items.first.video.id);
    }
    final state = container.read(profilePlaybackQueueProvider(queue.id));
    expect(state.queue?.items, hasLength(2));
    expect(state.message, contains('连续多页'));
    expect(state.queue?.hasMore, true);
  });

  testWidgets('paging deadline cancels transport and retries the same page', (
    tester,
  ) async {
    final queue = capture();
    final controller = paging(queue);
    final pending = repository.pending = Completer<ProfilePage>();
    final loading = controller.loadMore(queue.items.first.video.id);
    final read = repository.read;
    await tester.pump(const Duration(seconds: 31));
    await loading;
    expect(read?.isCancelled, true);
    expect(
      container.read(profilePlaybackQueueProvider(queue.id)).message,
      contains('超时'),
    );
    pending.complete(ProfilePage(items: [_entry(9)], hasMore: false));
    await tester.pump();
    expect(
      container.read(profilePlaybackQueueProvider(queue.id)).queue?.items,
      hasLength(2),
    );
    repository.pending = null;
    repository.items = [_entry(2)];
    await controller.loadMore(queue.items.first.video.id);
    expect(repository.calls.map((call) => call.page), [2, 2]);
    expect(
      container.read(profilePlaybackQueueProvider(queue.id)).queue?.items,
      hasLength(3),
    );
  });

  for (final close in [false, true]) {
    test(
      'pending pagination is cancelled on ${close ? 'close' : 'account change'} and ignores late data',
      () async {
        final queue = capture();
        final sub = container.listen(
          profilePlaybackQueueProvider(queue.id),
          (_, _) {},
        );
        final controller = container.read(
          profilePlaybackQueueProvider(queue.id).notifier,
        );
        final pending = repository.pending = Completer<ProfilePage>();
        final loading = controller.loadMore(queue.items.first.video.id);
        final read = repository.read;
        if (close) {
          sub.close();
        } else {
          repository.sessionEpoch++;
          auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '8'));
          repository.pending = null;
        }
        await Future<void>.delayed(Duration.zero);
        expect(read?.isCancelled, true);
        pending.complete(ProfilePage(items: [_entry(9)], hasMore: false));
        await loading;
        if (!close) {
          expect(
            container.read(profilePlaybackQueueProvider(queue.id)).queue,
            isNull,
          );
          sub.close();
        }
      },
    );
  }

  if (const bool.fromEnvironment('PROFILE_TOOLBAR_PREVIEW')) {
    for (final (width, dark, scale) in [
      (375.0, false, 1.0),
      (1100.0, false, 1.0),
      (375.0, true, 1.0),
      (320.0, false, 2.0),
    ]) {
      testWidgets('profile toolbar preview $width dark=$dark scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        repository.hasMore = false;
        repository.items = [for (var i = 0; i < 8; i++) _entry(i)];
        final theme = dark ? BiliTheme.dark() : BiliTheme.light();
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                backgroundColor: theme.colorScheme.surface,
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: ColoredBox(
                    color: theme.colorScheme.surface,
                    child: ProfileScreen(
                      id: _id,
                      isSelf: true,
                      onOpenPlaylist: (_, _) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final frame = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
          frame.dispose();
          if (bytes == null) throw StateError('Preview image was empty');
          final file = File(
            'build/validation/profile-toolbar-preview/$width-${dark ? 'dark' : 'light'}-$scale.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
        });
      });
    }
  }

  for (final width in [320.0, 1100.0]) {
    testWidgets(
      'selecting a submission opens only that video at width=$width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        repository.hasMore = false;
        final opened = <VideoSummary>[];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ProfileScreen(
                  id: _id,
                  isSelf: width < 600,
                  onOpenVideo: opened.add,
                  onOpenPlaylist: (_, _) =>
                      fail('Submission must open without a playlist'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('投稿1'));
        await tester.pumpAndSettle();
        expect(opened, hasLength(1));
        expect(opened.single.id, _entry(1).video?.id);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('play all button opens the UP playlist at width=$width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      VideoSummary? selected;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ProfileScreen(
                id: _id,
                isSelf: width < 600,
                onOpenPlaylist: (video, queueId) {
                  selected = video;
                  opened = queueId;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final play = find.byKey(const ValueKey('profile-play-all'));
      final buttonRect = tester.getRect(play);
      final pending = repository.pending = Completer<ProfilePage>();
      await tester.tap(play);
      await tester.pump();
      expect(tester.widget<TextButton>(play).onPressed, isNull);
      expect(
        find.descendant(
          of: play,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(play), buttonRect);
      pending.complete(ProfilePage(items: [_entry(9)], hasMore: true));
      await tester.pumpAndSettle();
      expect(selected?.id, _entry(9).video?.id);
      final queue = container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            opened,
            scope: repository.accountScope,
            sessionEpoch: repository.sessionEpoch,
          );
      expect(queue?.title, '测试UP的投稿');
      expect(tester.takeException(), isNull);
    });
  }
}

class _Repository extends Fake implements ProfileRepository {
  @override
  String accountScope = 'guest';
  @override
  int sessionEpoch = 0;
  List<ProfileEntry> items = [_entry(0), _entry(1)];
  bool hasMore = true;
  AppFailure? failure;
  Completer<ProfilePage>? pending;
  RequestCancellation? read;
  final calls = <({int page, String order, String keyword})>[];
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '测试UP');
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => null;
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    required RequestCancellation cancellation,
  }) async {
    calls.add((page: page, order: order, keyword: keyword));
    read = cancellation;
    if (failure case final error?) throw error;
    return pending?.future ?? ProfilePage(items: items, hasMore: hasMore);
  }
}
