import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/video/application/video_actions_controller.dart';
import 'package:bilisail/features/video/application/video_card_controller.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

void main() {
  const id = VideoId('BV1234567890');
  late _Videos videos;
  late _Playback playback;
  late VideoCardPreviewPlayback previews;
  late List<CardFakeEngine> engines;
  late _Actions actions;
  late VideoCardController controller;
  setUp(() {
    videos = _Videos();
    playback = _Playback();
    engines = [];
    previews = VideoCardPreviewPlayback(
      createEngine: () {
        final engine = CardFakeEngine();
        engines.add(engine);
        return engine;
      },
    );
    actions = _Actions();
    controller = VideoCardController(
      videos: videos,
      playback: playback,
      previews: previews,
      actions: actions,
      signedIn: true,
    );
  });
  tearDown(() async {
    controller.dispose();
    await previews.close();
  });

  test(
    'hover resolves first part and caches bounded metadata with LRU ordering',
    () async {
      final first = await controller.preview(id, RequestCancellation());
      expect(first?.engine, engines.single);
      expect(playback.lastCid, '42');
      expect(playback.lastQuality, 32);
      final next = await controller.preview(id, RequestCancellation());
      expect(next, isNot(same(first)));
      expect(first?.closed, true);
      expect(engines.first.disposals, 1);
      expect(videos.calls, 1);
      expect(playback.calls, 2); // Expiring stream URLs are resolved afresh.
      for (var i = 0; i < 24; i++) {
        await controller.preview(
          VideoId('BV${i.toString().padLeft(10, '0')}'),
          RequestCancellation(),
        );
      }
      await controller.preview(id, RequestCancellation());
      expect(videos.calls, 26);
    },
  );

  test('new hover cancels old read and rejects late detail without resolving a stream', () async {
    videos.pending = Completer<VideoDetail>();
    final token = RequestCancellation();
    final first = controller.preview(id, token);
    final pending = videos.pending!;
    videos.pending = null;
    await controller.preview(
      const VideoId('BV1234567891'),
      RequestCancellation(),
    );
    expect(token.isCancelled, true);
    pending.complete(_detail(id));
    expect(await first, isNull);
    expect(playback.calls, 1);
  });

  test('cancelled late stream never opens a native player', () async {
    playback.pending = Completer<PlaybackMedia>();
    final token = RequestCancellation();
    final first = controller.preview(id, token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    playback.pending!.complete(cardPreviewMedia());
    expect(await first, isNull);
    expect(engines, isEmpty);
    playback.pending = null;
    await controller.preview(id, RequestCancellation());
    expect(playback.calls, 2);
    expect(engines.length, 1);
  });

  test('guest never writes and successful addition is not repeated', () async {
    final guest = VideoCardController(
      videos: videos,
      playback: playback,
      previews: previews,
      actions: actions,
      signedIn: false,
    );
    addTearDown(guest.dispose);
    expect(await guest.addWatchLater(id), WatchLaterResult.signIn);
    expect(actions.writes, 0);
    expect(await controller.addWatchLater(id), WatchLaterResult.added);
    expect(await controller.addWatchLater(id), WatchLaterResult.alreadyAdded);
    expect(actions.writes, 1);
  });

  test('confirmed deletion clears added status and next successful add notifies its owner', () async {
    final added = <VideoId>[];
    final synchronized = VideoCardController(
      videos: videos,
      playback: playback,
      previews: previews,
      actions: actions,
      signedIn: true,
      onWatchLaterAdded: added.add,
    );
    addTearDown(synchronized.dispose);
    expect(await synchronized.addWatchLater(id), WatchLaterResult.added);
    expect(synchronized.beginWatchLaterRemoval(id), true);
    expect(await synchronized.addWatchLater(id), WatchLaterResult.busy);
    synchronized.finishWatchLaterRemoval(id, removed: true);
    expect(synchronized.isAdded(id), false);
    expect(synchronized.isUncertain(id), false);
    expect(await synchronized.addWatchLater(id), WatchLaterResult.added);
    expect(added, [id, id]);
    expect(actions.writes, 2);
  });

  test(
    'an unknown deletion drops stale added certainty and blocks another add',
    () async {
      expect(await controller.addWatchLater(id), WatchLaterResult.added);
      expect(controller.beginWatchLaterRemoval(id), true);
      controller.finishWatchLaterRemoval(id, uncertain: true);
      expect(controller.isAdded(id), false);
      expect(controller.isUncertain(id), true);
      expect(await controller.addWatchLater(id), WatchLaterResult.uncertain);
      expect(actions.writes, 1);
    },
  );

  test('pending add and explicit delete cannot overlap', () async {
    actions.pending = Completer<void>();
    final add = controller.addWatchLater(id);
    expect(controller.beginWatchLaterRemoval(id), false);
    actions.pending?.complete();
    expect(await add, WatchLaterResult.added);
    expect(controller.beginWatchLaterRemoval(id), true);
    expect(controller.beginWatchLaterRemoval(id), false);
    controller.finishWatchLaterRemoval(id);
    expect(controller.isAdded(id), true);
  });

  test(
    'busy and unknown results prevent duplicate or automatic writes',
    () async {
      actions.pending = Completer<void>();
      final write = controller.addWatchLater(id);
      expect(await controller.addWatchLater(id), WatchLaterResult.busy);
      actions.pending!.completeError(const UnknownWriteOutcome());
      expect(await write, WatchLaterResult.uncertain);
      expect(await controller.addWatchLater(id), WatchLaterResult.uncertain);
      expect(actions.writes, 1);
      expect(controller.isUncertain(id), true);
    },
  );

  test(
    'account transition disposes reads and writes and resets added state',
    () async {
      final auth = _Auth();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          videoRepositoryProvider.overrideWithValue(videos),
          videoCardPlaybackRepositoryProvider.overrideWithValue(playback),
          videoCardPreviewPlaybackProvider.overrideWithValue(previews),
          videoActionsRepositoryProvider.overrideWithValue(actions),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(auth.stream.close);
      final old = container.read(videoCardControllerProvider);
      expect(await old.addWatchLater(id), WatchLaterResult.added);
      actions.pending = Completer<void>();
      final write = old.addWatchLater(const VideoId('BV1234567891'));
      playback.pending = Completer<PlaybackMedia>();
      final token = RequestCancellation();
      final read = old.preview(id, token);
      await Future<void>.delayed(Duration.zero);
      actions.scope = 'user:2';
      auth.stream.add(const AuthState(status: AuthStatus.signedIn, mid: '2'));
      await Future<void>.delayed(Duration.zero);
      final next = container.read(videoCardControllerProvider);
      expect(next, isNot(same(old)));
      expect(token.isCancelled, true);
      expect(actions.lastToken?.isCancelled, true);
      expect(next.isAdded(id), false);
      actions.pending!.complete();
      playback.pending!.complete(cardPreviewMedia());
      expect(await write, WatchLaterResult.cancelled);
      expect(await read, isNull);
    },
  );
}

VideoDetail _detail(VideoId id) => VideoDetail(
  summary: VideoSummary(
    id: id,
    title: '测试',
    coverUrl: '',
    author: '测试',
    duration: const Duration(seconds: 30),
  ),
  description: '',
  parts: const [
    VideoPart(
      cid: '42',
      page: 1,
      title: '第一集',
      duration: Duration(seconds: 20),
    ),
  ],
);

class _Videos extends Fake implements VideoRepository {
  int calls = 0;
  Completer<VideoDetail>? pending;
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    calls++;
    return pending?.future ?? _detail(id);
  }
}

class _Playback extends Fake implements PlaybackRepository {
  int calls = 0;
  String? lastCid;
  int? lastQuality;
  Completer<PlaybackMedia>? pending;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    lastCid = cid;
    lastQuality = quality;
    return pending?.future ?? cardPreviewMedia();
  }
}

class _Actions extends Fake implements VideoActionsRepository {
  String scope = 'user:1';
  int writes = 0;
  Completer<void>? pending;
  RequestCancellation? lastToken;
  @override
  String get accountScope => scope;
  @override
  Future<void> watchLater(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) async {
    writes++;
    lastToken = cancellation;
    await pending?.future;
  }
}

class _Auth extends Fake implements AuthRepository {
  final stream = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState get current =>
      const AuthState(status: AuthStatus.signedIn, mid: '1');
  @override
  Stream<AuthState> get changes => stream.stream;
}
