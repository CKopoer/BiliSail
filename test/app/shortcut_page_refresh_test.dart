import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/presentation/input_scope.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/live/application/live_controller.dart';
import 'package:bilisail/features/live/domain/live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_test_app.dart';

void main() {
  for (final changed in [false, true]) {
    testWidgets('delayed PGC refresh opens once with changed=$changed', (
      tester,
    ) async {
      final pgc = _PgcRepository();
      final engine = _Engine();
      final session = _session(engine);
      final auth = _AuthRepository();
      final router = createBiliRouter(
        initialLocation: '/pgc/season/1',
        playerBuilder: (_, _, _) => const SizedBox(),
        pgcPlayerBuilder: (_, season, episode) =>
            _panel(PgcPlaybackTarget(episode.episodeId, cid: episode.cid)),
      );
      addTearDown(session.close);
      addTearDown(auth.dispose);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            pgcRepositoryProvider.overrideWithValue(pgc),
            playbackSessionProvider.overrideWithValue(session),
            settingsRepositoryProvider.overrideWithValue(_Settings()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.opens, 1);
      await session.seek(const Duration(seconds: 20));
      await session.pause();
      final gate = pgc.pending = Completer<PgcSeason>();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(pgc.reads, 2, reason: 'Concurrent refresh merges into one read');
      expect(engine.opens, 1, reason: 'Loading must retain the old source');
      gate.complete(_season(changed ? '2' : '1'));
      await tester.pumpAndSettle();
      expect(
        engine.opens,
        2,
        reason: 'Activation and retry must not both open',
      );
      expect(
        session.contentTarget,
        PgcPlaybackTarget(changed ? '2' : '1', cid: changed ? '2' : '1'),
      );
      expect(session.snapshots.value.desiredPlaying, isFalse);
      if (!changed) {
        expect(session.snapshots.value.position, const Duration(seconds: 20));
        final input = InputScope.of<Object>(
          tester.element(find.byType(PlaybackPanel)),
        )!.dispatcher;
        input.diagnosticsEnabled = true;
        pgc.pending = null;
        engine.failOpen = true;
        await tester.sendKeyEvent(LogicalKeyboardKey.f5);
        await tester.pumpAndSettle();
        expect(session.error, isNotNull);
        expect(
          input.diagnostics.any(
            (trace) => trace.result.reason == DispatchReason.failed,
          ),
          isTrue,
          reason:
              'A swallowed PlayerFailure cannot become a successful refresh',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('delayed live refresh keeps one source with changed=$changed', (
      tester,
    ) async {
      final live = _LiveRepository();
      final engine = _Engine();
      final session = _session(engine);
      final auth = _AuthRepository();
      final router = createBiliRouter(
        initialLocation: '/live/1',
        playerBuilder: (_, _, _) => const SizedBox(),
        livePlayerBuilder: (_, room) =>
            _panel(LivePlaybackTarget(room.id.value)),
      );
      addTearDown(session.close);
      addTearDown(auth.dispose);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            liveRepositoryProvider.overrideWithValue(live),
            playbackSessionProvider.overrideWithValue(session),
            settingsRepositoryProvider.overrideWithValue(_Settings()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.opens, 1);
      final gate = live.pending = Completer<LiveRoom>();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(live.reads, 2);
      expect(engine.opens, 1);
      gate.complete(_room(changed ? '2' : '1'));
      await tester.pumpAndSettle();
      expect(engine.opens, changed ? 2 : 1);
      expect(session.contentTarget, LivePlaybackTarget(changed ? '2' : '1'));
      final input = InputScope.of<Object>(
        tester.element(find.byType(PlaybackPanel)),
      )!.dispatcher;
      input.diagnosticsEnabled = true;
      final failure = live.pending = Completer<LiveRoom>();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      failure.completeError(const AppFailure(AppFailureKind.network, '房间加载失败'));
      await tester.pumpAndSettle();
      expect(
        input.diagnostics.any(
          (trace) => trace.result.reason == DispatchReason.failed,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}

final _settings = AppSettings(danmakuEnabled: false, autoPlay: false);
Widget _panel(ContentPlaybackTarget target) => PlaybackPanel(
  target: target,
  settings: _settings,
  window: WindowService(),
  onToggleComments: () {},
);
PlaybackSession _session(_Engine engine) => PlaybackSession(
  engine: engine,
  repository: _UgcRepository(),
  contentRepository: _ContentRepository(),
  progress: _Progress(),
  accountScope: () => 'guest',
);
PgcSeason _season(String episode) => PgcSeason(
  id: const PgcSeasonId('1'),
  title: '刷新样本',
  episodes: [
    PgcEpisode(
      id: PgcEpisodeId(episode),
      title: episode,
      bvid: 'BV1234567890',
      cid: episode,
    ),
  ],
);
LiveRoom _room(String id) => LiveRoom(
  id: RoomId(id),
  title: '刷新样本',
  anchorName: 'fixture',
  isLive: true,
);

final class _PgcRepository implements PgcRepository {
  int reads = 0;
  Completer<PgcSeason>? pending;
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    required RequestCancellation cancellation,
  }) {
    reads++;
    return pending?.future ?? Future.value(_season('1'));
  }
}

final class _LiveRepository implements LiveRepository {
  int reads = 0;
  Completer<LiveRoom>? pending;
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    reads++;
    return pending?.future ?? Future.value(_room(id.value));
  }

  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) async => LivePlayInfo(roomId: id, isLive: true, streams: const []);
}

final class _ContentRepository implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri.parse('https://fixture.test/video')],
      codec: 'h264',
      bandwidth: 1,
    ),
    audio: target is LivePlaybackTarget
        ? null
        : PlaybackTrack(
            urls: [Uri.parse('https://fixture.test/audio')],
            codec: 'aac',
            bandwidth: 1,
          ),
    kind: target is LivePlaybackTarget
        ? PlaybackMediaKind.liveHls
        : PlaybackMediaKind.dash,
    quality: quality,
    qualities: [quality],
    duration: const Duration(minutes: 3),
    headers: const {},
  );
}

final class _UgcRepository implements PlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => throw StateError('Content must use its own resolver');
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => [];
}

final class _Progress implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
}

final class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

final class _AuthRepository implements AuthRepository {
  final _events = StreamController<AuthState>.broadcast();
  @override
  AuthState get current => const AuthState();
  @override
  Stream<AuthState> get changes => _events.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async {}
  Future<void> dispose() => _events.close();
}

final class _Engine implements PlayerEngine, VideoSurfaceSource {
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast();
  PlaybackSnapshot _snapshot = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );
  int opens = 0;
  bool failOpen = false;
  void _emit(PlaybackSnapshot snapshot) {
    _snapshot = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  PlaybackSnapshot get currentSnapshot => _snapshot;
  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PlayerFailure> get failures => _failures.stream;
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);
  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    if (failOpen) {
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        '播放失败',
        _snapshot.generation,
      );
    }
    _emit(
      PlaybackSnapshot(
        phase: PlaybackPhase.ready,
        generation: ++opens,
        position: options.startPosition,
        duration: const Duration(minutes: 3),
      ),
    );
  }

  @override
  Future<void> play() async => _emit(
    _snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => _emit(
    _snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
  @override
  Future<void> seek(Duration target) async =>
      _emit(_snapshot.copyWith(position: target));
  @override
  Future<void> setRate(double rate) async =>
      _emit(_snapshot.copyWith(rate: rate));
  @override
  Future<void> setVolume(double volume) async =>
      _emit(_snapshot.copyWith(volume: volume));
  @override
  Future<void> stop() async =>
      _emit(_snapshot.copyWith(phase: PlaybackPhase.idle));
  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _failures.close();
  }

  @override
  Widget buildVideoSurface() => const ColoredBox(color: Colors.black);
}
