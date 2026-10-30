import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/video/application/playback_queue_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/follow_repository_fake.dart';
import '../messages/message_fakes.dart';

const _user = UserId('7');
const _folder = ProfileEntry(
  id: '42',
  kind: ProfileEntryKind.folder,
  title: '公开收藏夹',
);

void main() {
  late AuthFake auth;
  late _Profile repository;
  late ProviderContainer container;
  setUp(() {
    auth = AuthFake();
    repository = _Profile();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(repository),
        videoAuthorRepositoryProvider.overrideWithValue(FollowRepositoryFake()),
        sessionEpochProvider.overrideWithValue(() => repository.sessionEpoch),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  Future<ProfileController> openFolder() async {
    final sub = container.listen(profileControllerProvider(_user), (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(
      profileControllerProvider(_user).notifier,
    );
    controller.openFolder(_folder);
    await Future<void>.delayed(Duration.zero);
    return controller;
  }

  PlaybackQueueController paging(WatchLaterQueue queue) {
    final sub = container.listen(playbackQueueProvider(queue.id), (_, _) {});
    addTearDown(sub.close);
    return container.read(playbackQueueProvider(queue.id).notifier);
  }

  for (final isSelf in [true, false]) {
    for (final playAll in [true, false]) {
      testWidgets(
        '${isSelf ? 'own' : 'UP'} favorites ${playAll ? 'play all' : 'select video'} loads only its first source page',
        (tester) async {
          final width = isSelf ? 375.0 : 1100.0;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final opened = <(VideoSummary, String)>[];
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(isSelf ? 1 : 2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: ProfileScreen(
                    id: _user,
                    isSelf: isSelf,
                    initialSection: ProfileSection.folders,
                    onOpenPlaylist: (video, queueId) =>
                        opened.add((video, queueId)),
                    onOpenVideo: (_) =>
                        fail('Favorite must carry its playlist'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(_folder.title));
          await tester.pumpAndSettle();
          final button = find.byKey(
            const ValueKey('profile-favorite-play-all'),
          );
          expect(tester.widget<TextButton>(button).onPressed, isNotNull);
          expect(tester.getRect(button).right, width - 16);
          expect(find.byIcon(Icons.playlist_play), findsOneWidget);
          final reads = repository.folderCalls.length;
          expect(reads, 1);
          await tester.tap(playAll ? button : find.text('视频 2'));
          await tester.pumpAndSettle();
          expect(opened, hasLength(1));
          expect(opened.single.$1.id, _video(playAll ? 1 : 2).id);
          final queue = container
              .read(watchLaterQueueRegistryProvider)
              .resolve(opened.single.$2, scope: 'guest', sessionEpoch: 4)!;
          expect(queue.title, _folder.title);
          expect(queue.items, hasLength(40));
          expect(queue.hasMore, true);
          expect(queue.nextPage, 2);
          expect(queue.profileSource?.folderId, '42');
          expect(queue.profileSource?.userId, _user);
          expect(repository.folderCalls, hasLength(reads + 1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'capture reads one source page and filters unavailable and repeated videos',
    () async {
      repository.pages[1] = [
        _entry(1),
        const ProfileEntry(
          id: 'invalid',
          kind: ProfileEntryKind.video,
          title: '失效视频',
        ),
        ProfileEntry(
          id: 'duplicate',
          kind: ProfileEntryKind.video,
          title: '重复视频',
          video: _video(1),
        ),
      ];
      final controller = await openFolder();
      final reads = repository.folderCalls.length;
      final queue = (await controller.captureFavoriteQueue())!;
      expect(queue.items.map((item) => item.video.id), [_video(1).id]);
      expect(repository.folderCalls, hasLength(reads + 1));
      expect(queue.isWatchLater, false);
      controller.closeFolder();
      expect(await controller.captureFavoriteQueue(), isNull);
    },
  );

  test('selecting a video captures only its originating page, not earlier loaded pages', () async {
    final origin = await openFolder();
    await origin.load();
    final before = repository.folderCalls.length;
    final queue = (await origin.captureFavoriteQueue(initial: _video(50).id))!;
    expect(repository.folderCalls, hasLength(before + 1));
    expect(repository.folderCalls.last.page, 2);
    expect(queue.items, hasLength(40));
    expect(queue.items.first.video.id, _video(41).id);
    expect(queue.indexOf(_video(50).id), 9);
    expect(queue.hasPrevious, true);
    expect(queue.nextPage, 3);
    final all = (await origin.captureFavoriteQueue())!;
    expect(all.pages.single.page, 1);
    expect(all.items, hasLength(40));
  });

  test('each playback request reads one page, deduplicates and retries the failed page', () async {
    final origin = await openFolder();
    final queue = (await origin.captureFavoriteQueue())!;
    final controller = paging(queue);
    repository.folderCalls.clear();
    final pending = repository.pending = Completer<ProfilePage>();
    final first = controller.loadMore(_video(1).id);
    final second = controller.loadMore(_video(1).id);
    expect(repository.folderCalls.map((call) => call.page), [2]);
    pending.complete(
      ProfilePage(items: [_entry(40), _entry(41)], hasMore: true),
    );
    await Future.wait([first, second]);
    repository.pending = null;
    final provider = playbackQueueProvider(queue.id);
    expect(container.read(provider).queue?.items, hasLength(41));
    repository.failure = const AppFailure(AppFailureKind.network, '分页失败');
    await controller.loadMore(_video(1).id);
    expect(container.read(provider).message, '分页失败');
    repository.failure = null;
    await controller.loadMore(_video(1).id);
    expect(repository.folderCalls.map((call) => call.page), [2, 3, 3]);
    expect(repository.folderCalls.every((call) => call.folderId == '42'), true);
    expect(container.read(provider).queue?.hasMore, false);
    expect(container.read(provider).queue?.items.last.video.id, _video(120).id);
    expect(container.read(provider).message, isNull);
  });

  test(
    'changing the browser folder cannot retarget an existing playback queue',
    () async {
      final origin = await openFolder();
      final queue = (await origin.captureFavoriteQueue())!;
      final controller = paging(queue);
      origin.openFolder(
        const ProfileEntry(
          id: '99',
          kind: ProfileEntryKind.folder,
          title: '另一个收藏夹',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      repository.folderCalls.clear();
      await controller.loadMore(_video(1).id);
      expect(repository.folderCalls.single.folderId, '42');
      expect(repository.folderCalls.single.user, _user);
      expect(
        container.read(playbackQueueProvider(queue.id)).queue?.title,
        _folder.title,
      );
    },
  );

  test('an oversized source page retains at most 99 videos', () async {
    repository.pages[1] = [for (var n = 1; n <= 510; n++) _entry(n)];
    repository.lastPage = 1;
    final origin = await openFolder();
    final queue = (await origin.captureFavoriteQueue())!;
    expect(queue.items, hasLength(99));
    expect(queue.hasMore, false);
    expect(queue.nextPage, 2);
    expect(queue.truncated, true);
  });

  test(
    'account changes cancel pending folder paging and discard its late result',
    () async {
      final origin = await openFolder();
      final queue = (await origin.captureFavoriteQueue())!;
      final controller = paging(queue);
      final pending = repository.pending = Completer<ProfilePage>();
      final loading = controller.loadMore(_video(1).id);
      final read = repository.read;
      repository.sessionEpoch++;
      repository.pending = null;
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '8'));
      await Future<void>.delayed(Duration.zero);
      expect(read?.isCancelled, true);
      pending.complete(ProfilePage(items: [_entry(41)], hasMore: false));
      await loading;
      expect(container.read(playbackQueueProvider(queue.id)).queue, isNull);
      expect(await origin.captureFavoriteQueue(), isNull);
    },
  );

  testWidgets(
    'folder paging times out and retries without accepting late data',
    (tester) async {
      final origin = (await tester.runAsync(openFolder))!;
      final queue = (await origin.captureFavoriteQueue())!;
      final controller = paging(queue);
      final pending = repository.pending = Completer<ProfilePage>();
      final loading = controller.loadMore(_video(1).id);
      final read = repository.read;
      await tester.pump(const Duration(seconds: 31));
      await loading;
      expect(read?.isCancelled, true);
      final provider = playbackQueueProvider(queue.id);
      expect(container.read(provider).message, contains('收藏夹视频加载超时'));
      pending.complete(ProfilePage(items: [_entry(41)], hasMore: false));
      await tester.pump();
      expect(container.read(provider).queue?.items, hasLength(40));
      repository.pending = null;
      await controller.loadMore(_video(1).id);
      expect(container.read(provider).queue?.items, hasLength(80));
    },
  );
}

VideoSummary _video(int index) => VideoSummary(
  id: VideoId('BV${index.toString().padLeft(10, '0')}'),
  title: '视频 $index',
  coverUrl: '',
  author: 'UP',
  duration: Duration.zero,
);

ProfileEntry _entry(int index) => ProfileEntry(
  id: '$index',
  kind: ProfileEntryKind.video,
  title: '视频 $index',
  video: _video(index),
);

typedef _Call = ({
  UserId user,
  ProfileSection section,
  String? folderId,
  int page,
});

final class _Profile implements ProfileRepository {
  @override
  String get accountScope => 'guest';
  @override
  int sessionEpoch = 4;
  final folderCalls = <_Call>[];
  final pages = <int, List<ProfileEntry>>{};
  int lastPage = 3;
  Completer<ProfilePage>? pending;
  AppFailure? failure;
  RequestCancellation? read;

  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '测试用户');
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
    if (section != ProfileSection.folders) {
      return const ProfilePage(items: [], hasMore: false);
    }
    if (folderId == null) {
      return const ProfilePage(items: [_folder], hasMore: false);
    }
    folderCalls.add((
      user: id,
      section: section,
      folderId: folderId,
      page: page,
    ));
    read = cancellation;
    if (failure case final error?) throw error;
    return pending?.future ??
        ProfilePage(
          items:
              pages[page] ??
              [
                for (var n = (page - 1) * 40 + 1; n <= page * 40; n++)
                  _entry(n),
              ],
          hasMore: page < lastPage,
        );
  }
}
