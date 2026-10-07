import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/application/download_controller.dart';
import 'package:bilisail/features/downloads/data/sqlite_download_repository.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/presentation/offline_screen.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/data/offline_playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_history_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows download survives restart and opens local DASH, subtitles and danmaku with no API calls',
    (tester) async {
      initializePlayerBackend();
      final directory = await Directory.systemTemp.createTemp(
        'bilisail_offline_native_',
      );
      final fixture = File(
        path.join(
          Directory.current.path,
          'test',
          'fixtures',
          'media',
          'video.mp4',
        ),
      );
      final audioFixture = File(
        path.join(
          Directory.current.path,
          'test',
          'fixtures',
          'media',
          'audio.m4a',
        ),
      );
      expect(await fixture.exists(), isTrue);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var transfers = 0;
      final serving = server.listen((request) async {
        transfers++;
        final file = request.uri.path == '/video' ? fixture : audioFixture;
        request.response.headers.contentLength = await file.length();
        request.response.headers.set(
          HttpHeaders.etagHeader,
          '"fixture-${request.uri.path}"',
        );
        await request.response.addStream(file.openRead());
        await request.response.close();
      });
      final sources = _FixtureSources(server.port);
      final dbFile = File(path.join(directory.path, 'client.sqlite'));
      var database = AppDatabase(NativeDatabase(dbFile));
      var downloads = SqliteDownloadRepository(
        database,
        sources,
        defaultDirectory: () async => path.join(directory.path, 'offline'),
      );
      PlaybackSession? session;
      try {
        await downloads.initialize();
        await downloads.enqueue([_item], const DownloadSelection());
        await _until(
          tester,
          () => downloads.current.tasks.any(
            (task) =>
                task.status == DownloadStatus.completed ||
                task.status == DownloadStatus.failed,
          ),
        );
        final task = downloads.current.tasks.single;
        expect(task.failure, isNull);
        expect(task.status, DownloadStatus.completed);
        expect(task.tracks.every((track) => track.complete), isTrue);
        expect(transfers, 2);
        await downloads.close();
        await database.close();
        // There is no network service when the restored task is opened.
        await serving.cancel();
        await server.close(force: true);
        database = AppDatabase(NativeDatabase(dbFile));
        downloads = SqliteDownloadRepository(
          database,
          sources,
          defaultDirectory: () async => path.join(directory.path, 'offline'),
        );
        await downloads.initialize();
        expect(downloads.current.tasks.single.status, DownloadStatus.completed);
        final offline = OfflinePlaybackRepository(
          downloads: downloads,
          network: _RejectNetwork(),
          networkMetadata: _RejectNetwork(),
          networkContent: _RejectContent(),
        );
        final history = _ProbeHistory();
        final engine = MediaKitEngine();
        final player = PlaybackSession(
          engine: engine,
          repository: offline,
          metadataRepository: offline,
          contentRepository: offline.content,
          historyRepository: history,
          progress: _NoProgress(),
          accountScope: () => 'guest',
        );
        session = player;
        final window = WindowService();
        final settings = AppSettings(autoPlay: false, defaultVolume: 0);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              downloadRepositoryProvider.overrideWithValue(downloads),
              downloadSourceRepositoryProvider.overrideWithValue(sources),
              playbackSessionProvider.overrideWithValue(player),
            ],
            child: MaterialApp(
              theme: BiliTheme.light(),
              home: Scaffold(
                body: OfflineScreen(
                  taskId: task.id,
                  playerBuilder: (context, verified) => PlaybackPanel(
                    detail: VideoDetail(
                      summary: verified.item.video,
                      description: '',
                      parts: [verified.item.part],
                    ),
                    part: verified.item.part,
                    target: OfflinePlaybackTarget(verified.id),
                    settings: settings,
                    window: window,
                    onToggleComments: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => player.media != null || player.error != null,
        );
        expect(player.error, isNull);
        expect(player.media?.video.urls.single.scheme, 'file');
        expect(player.media?.audio?.urls.single.scheme, 'file');
        expect(
          player.engine.currentSnapshot.duration,
          greaterThan(Duration.zero),
        );
        await _until(tester, () => player.subtitleTracks.isNotEmpty);
        await player.selectSubtitle(0);
        expect(player.subtitleCues.single.text, '本地字幕');
        final comments = await offline.comments(
          _item.part.cid,
          1,
          cancellation: RequestCancellation(),
        );
        expect(comments.single.text, '本地弹幕');
        await player.seek(const Duration(seconds: 3));
        await player.togglePlaying();
        await _until(
          tester,
          () =>
              player.snapshots.value.position >
                  const Duration(milliseconds: 3300) &&
              engine.inspectDiagnostics().hasDecodedVideo &&
              engine.inspectDiagnostics().hasDecodedAudio,
        );
        expect(engine.inspectDiagnostics().audioChannels, greaterThan(0));
        await player.pause();
        expect(history.calls, 0);
        expect(
          sources.resolutions,
          1,
          reason:
              'Restored offline playback must not re-resolve the remote URL',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await player.close();
        session = null;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await session?.close();
        await downloads.close();
        await database.close();
        await serving.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Native offline state timed out');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _item = DownloadItem(
  video: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '离线下载实测',
    coverUrl: '',
    author: '本地合成媒体',
    duration: Duration(seconds: 12),
  ),
  part: VideoPart(
    cid: '101',
    page: 1,
    title: '分轨视频',
    duration: Duration(seconds: 12),
  ),
);

final class _FixtureSources implements DownloadSourceRepository {
  _FixtureSources(this.port);
  final int port;
  int resolutions = 0;
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<List<int>> qualities(
    DownloadItem item, {
    required RequestCancellation cancellation,
  }) async => [80];
  @override
  Future<DownloadResolvedSource> resolve(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) async {
    resolutions++;
    DownloadTrackSource track(DownloadTrackKind kind) => DownloadTrackSource(
      identity: 'native-fixture-${kind.name}',
      kind: kind,
      urls: [Uri.parse('http://127.0.0.1:$port/${kind.name}')],
      codec: kind == DownloadTrackKind.video ? 'avc1' : 'mp4a',
      bandwidth: 1000,
    );
    return DownloadResolvedSource(
      video: track(DownloadTrackKind.video),
      audio: track(DownloadTrackKind.audio),
      quality: 80,
      duration: const Duration(seconds: 12),
      headers: const {},
    );
  }

  @override
  Future<DownloadExtras> extras(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) async => DownloadExtras(
    comments: const [
      TimedComment(
        id: '1',
        position: Duration(seconds: 1),
        text: '本地弹幕',
        mode: 1,
        color: 0xffffff,
        fontSize: 24,
      ),
    ],
    subtitles: [
      DownloadedSubtitle(
        label: '本地中文',
        cues: const [SubtitleCue(Duration.zero, Duration(seconds: 8), '本地字幕')],
      ),
    ],
  );
}

final class _RejectNetwork extends Fake
    implements PlaybackRepository, PlaybackMetadataRepository {}

final class _RejectContent extends Fake implements ContentPlaybackRepository {}

final class _ProbeHistory extends Fake implements PlaybackHistoryRepository {
  int calls = 0;
  @override
  Future<Duration?> read(
    PlaybackHistoryTarget target, {
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    return null;
  }

  @override
  Future<void> report(
    PlaybackHistoryRecord record, {
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    calls++;
  }
}

final class _NoProgress extends Fake implements PlaybackProgressStore {
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
