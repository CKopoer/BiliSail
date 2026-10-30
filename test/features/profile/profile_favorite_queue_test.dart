import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/feed/application/home_repository_provider.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

void main() {
  for (final playAll in [true, false]) {
    testWidgets(
      'profile favorites ${playAll ? 'play all' : 'select video'} opens ordered queue',
      (tester) async {
        final auth = AuthFake();
        final home = _Home();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            profileRepositoryProvider.overrideWithValue(_Profile()),
            homeRepositoryProvider.overrideWithValue(home),
            sessionEpochProvider.overrideWithValue(() => 4),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(auth.stream.close);
        final opened = <(VideoSummary, String)>[];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ProfileScreen(
                  id: const UserId('7'),
                  isSelf: true,
                  initialSection: ProfileSection.folders,
                  onOpenPlaylist: (video, queueId) =>
                      opened.add((video, queueId)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('公开收藏夹'));
        await tester.pumpAndSettle();
        await tester.tap(
          playAll
              ? find.byKey(const ValueKey('profile-favorite-play-all'))
              : find.text('视频 2'),
        );
        await tester.pumpAndSettle();
        expect(opened, hasLength(1));
        expect(
          opened.single.$1.id,
          VideoId(playAll ? 'BV0000000001' : 'BV0000000002'),
        );
        final queue = container
            .read(watchLaterQueueRegistryProvider)
            .resolve(opened.single.$2, scope: 'guest', sessionEpoch: 4)!;
        expect(queue.title, '公开收藏夹');
        expect(queue.items, hasLength(2));
        expect(home.queries.every((q) => q.folderId == '42'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

VideoSummary _video(int index) => VideoSummary(
  id: VideoId('BV000000000$index'),
  title: '视频 $index',
  coverUrl: '',
  author: 'UP',
  duration: Duration.zero,
);

final class _Profile implements ProfileRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 4;
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
  }) async => ProfilePage(
    items: folderId == null
        ? [
            const ProfileEntry(
              id: '42',
              kind: ProfileEntryKind.folder,
              title: '公开收藏夹',
            ),
          ]
        : [
            for (var n = 1; n <= 2; n++)
              ProfileEntry(
                id: '$n',
                kind: ProfileEntryKind.video,
                title: '视频 $n',
                video: _video(n),
              ),
          ],
    hasMore: false,
  );
}

final class _Home implements HomeRepository {
  @override
  String get accountScope => 'guest';
  final queries = <HomeQuery>[];
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    queries.add(query);
    return HomePage([
      for (var n = 1; n <= 2; n++)
        HomeEntry(
          id: '$n',
          kind: HomeEntryKind.video,
          title: '视频 $n',
          bvid: _video(n).id.value,
        ),
    ], hasMore: false);
  }
}
