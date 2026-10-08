import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/playback/data/offline_playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _FakeDownloads downloads;
  late _FakeNetwork network;
  late OfflinePlaybackRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bilisail_offline_test');
    downloads = _FakeDownloads();
    network = _FakeNetwork();
    repository = OfflinePlaybackRepository(
      downloads: downloads,
      network: network,
      networkMetadata: network,
      networkContent: _FakeContent(network.calls),
    );
    downloads.task = _task(directory.path);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'offline resolve uses separate local DASH files without network',
    () async {
      final media = await repository.content.resolve(
        const OfflinePlaybackTarget('task-1'),
        quality: 80,
        cancellation: RequestCancellation(),
      );
      expect(
        media.video.urls.single,
        File('${directory.path}${Platform.pathSeparator}video.m4s').uri,
      );
      expect(
        media.audio?.urls.single,
        File('${directory.path}${Platform.pathSeparator}audio.m4s').uri,
      );
      expect(media.headers, isEmpty);
      expect(media.quality, 80);
      expect(downloads.offlineReads, 1);
      expect(network.calls, isEmpty);
    },
  );

  test(
    'offline extras serve segmented comments and subtitle cues locally',
    () async {
      await _writeExtras(directory, {
        'version': 1,
        'comments': [
          _comment('a', 0),
          _comment('b', 359999),
          _comment('c', 360000),
        ],
        'subtitles': [
          {
            'label': '简体中文',
            'cues': [
              {'startMs': 100, 'endMs': 500, 'text': '第一句'},
            ],
          },
        ],
      });
      await repository.content.resolve(
        const OfflinePlaybackTarget('task-1'),
        quality: 80,
        cancellation: RequestCancellation(),
      );
      final first = await repository.comments(
        '123',
        1,
        cancellation: RequestCancellation(),
      );
      final second = await repository.comments(
        '123',
        2,
        cancellation: RequestCancellation(),
      );
      expect(first.map((entry) => entry.id), ['a', 'b']);
      expect(second.map((entry) => entry.id), ['c']);
      final tracks = await repository.subtitles(
        const VideoId('BV1xx411c7mD'),
        '123',
        cancellation: RequestCancellation(),
      );
      expect(tracks.single.uri.scheme, 'bilisail-offline');
      expect(tracks.single.uri.host, 'task-1');
      expect(
        (await repository.subtitleCues(
          tracks.single,
          cancellation: RequestCancellation(),
        )).single.text,
        '第一句',
      );
      final metadata = await repository.metadata(
        _detail(),
        _task(directory.path).item.part,
        cancellation: RequestCancellation(),
      );
      expect(metadata.subtitles.single.label, '简体中文');
      expect(
        await repository.storyboard(
          const VideoId('BV1xx411c7mD'),
          '123',
          cancellation: RequestCancellation(),
        ),
        isNull,
      );
      expect(network.calls, isEmpty);
    },
  );

  test(
    'merged offline media opens one source with no external audio or network',
    () async {
      downloads.task = _task(directory.path, output: DownloadOutput.mp4);
      final media = await repository.content.resolve(
        const OfflinePlaybackTarget('task-1'),
        quality: 80,
        cancellation: RequestCancellation(),
      );
      expect(media.video.urls.single, File('${directory.path}/media.mp4').uri);
      expect(media.audio, isNull);
      expect(network.calls, isEmpty);
    },
  );

  test('two adapters keep offline and online content isolated', () async {
    await _writeExtras(directory, {
      'version': 1,
      'comments': [_comment('offline', 1000)],
      'subtitles': [],
    });
    final online = OfflinePlaybackRepository(
      downloads: downloads,
      network: network,
      networkMetadata: network,
      networkContent: _FakeContent(network.calls),
    );
    await repository.content.resolve(
      const OfflinePlaybackTarget('task-1'),
      quality: 80,
      cancellation: RequestCancellation(),
    );
    await online.content.resolve(
      const PgcPlaybackTarget('42'),
      quality: 80,
      cancellation: RequestCancellation(),
    );
    expect(
      (await repository.comments(
        '123',
        1,
        cancellation: RequestCancellation(),
      )).single.id,
      'offline',
    );
    expect(
      (await online.comments(
        '123',
        1,
        cancellation: RequestCancellation(),
      )).single.id,
      'network',
    );
    expect(downloads.offlineReads, 1);
    expect(network.calls, ['content', 'comments']);
  });

  test(
    'late offlineTask cannot restore a source after online switch',
    () async {
      final pendingTask = Completer<DownloadTask>();
      downloads.pending = pendingTask;
      final stale = repository.content.resolve(
        const OfflinePlaybackTarget('task-1'),
        quality: 80,
        cancellation: RequestCancellation(),
      );
      await downloads.started.future;
      await repository.resolve(
        const VideoId('BV1xx411c7mD'),
        '123',
        quality: 80,
        cancellation: RequestCancellation(),
      );
      pendingTask.complete(downloads.task);
      await expectLater(stale, throwsA(_cancelled));
      expect(
        (await repository.comments(
          '123',
          1,
          cancellation: RequestCancellation(),
        )).single.id,
        'network',
      );
      expect(network.calls, ['resolve', 'comments']);
    },
  );

  test('cancelled pending offlineTask never writes back the source', () async {
    final pendingTask = Completer<DownloadTask>();
    downloads.pending = pendingTask;
    final cancellation = RequestCancellation();
    final pending = repository.content.resolve(
      const OfflinePlaybackTarget('task-1'),
      quality: 80,
      cancellation: cancellation,
    );
    await downloads.started.future;
    cancellation.cancel();
    pendingTask.complete(downloads.task);
    await expectLater(pending, throwsA(_cancelled));
    expect(
      (await repository.comments(
        '123',
        1,
        cancellation: RequestCancellation(),
      )).single.id,
      'network',
    );
  });

  test('corrupt and oversized extras are rejected before exposure', () async {
    await repository.content.resolve(
      const OfflinePlaybackTarget('task-1'),
      quality: 80,
      cancellation: RequestCancellation(),
    );
    final file = File('${directory.path}${Platform.pathSeparator}extras.json');
    await file.writeAsString('{broken');
    await expectLater(
      repository.comments('123', 1, cancellation: RequestCancellation()),
      throwsA(_storage),
    );

    final another = OfflinePlaybackRepository(
      downloads: downloads,
      network: network,
      networkMetadata: network,
      networkContent: _FakeContent(network.calls),
    );
    await another.content.resolve(
      const OfflinePlaybackTarget('task-1'),
      quality: 80,
      cancellation: RequestCancellation(),
    );
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(32 * 1024 * 1024 + 1);
    await handle.close();
    await expectLater(
      another.subtitles(
        const VideoId('BV1xx411c7mD'),
        '123',
        cancellation: RequestCancellation(),
      ),
      throwsA(_storage),
    );
    expect(network.calls, isEmpty);
  });
}

final _cancelled = isA<AppFailure>().having(
  (failure) => failure.kind,
  'kind',
  AppFailureKind.cancelled,
);
final _storage = isA<AppFailure>().having(
  (failure) => failure.kind,
  'kind',
  AppFailureKind.storage,
);

Map<String, Object?> _comment(String id, int positionMs) => {
  'id': id,
  'positionMs': positionMs,
  'text': id,
  'mode': 1,
  'color': 16777215,
  'fontSize': 25,
  'weight': 1,
};

Future<void> _writeExtras(Directory directory, Map<String, Object?> body) =>
    File('${directory.path}${Platform.pathSeparator}extras.json')
        .writeAsString(jsonEncode(body));

DownloadTask _task(
  String directory, {
  DownloadOutput output = DownloadOutput.separate,
}) {
  final now = DateTime(2026, 10, 7);
  return DownloadTask(
    id: 'task-1',
    scope: 'account-a',
    directory: directory,
    item: DownloadItem(
      video: const VideoSummary(
        id: VideoId('BV1xx411c7mD'),
        title: '测试视频',
        coverUrl: '',
        author: '作者',
        duration: Duration(minutes: 12),
      ),
      part: const VideoPart(
        cid: '123',
        page: 1,
        title: '第一集',
        duration: Duration(minutes: 12),
      ),
    ),
    selection: DownloadSelection(quality: 80, output: output),
    mergedMedia: output == DownloadOutput.mp4
        ? const DownloadMergedMedia(bytes: 8, sha256: 'digest')
        : null,
    status: DownloadStatus.completed,
    createdAt: now,
    updatedAt: now,
    tracks: const [
      DownloadTrackProgress(
        kind: DownloadTrackKind.video,
        identity: 'v',
        fileName: 'video.m4s',
        codec: 'avc1',
        bandwidth: 1000,
        bytes: 4,
        totalBytes: 4,
        sha256: 'digest-v',
      ),
      DownloadTrackProgress(
        kind: DownloadTrackKind.audio,
        identity: 'a',
        fileName: 'audio.m4s',
        codec: 'mp4a',
        bandwidth: 100,
        bytes: 4,
        totalBytes: 4,
        sha256: 'digest-a',
      ),
    ],
  );
}

VideoDetail _detail() => VideoDetail(
  summary: const VideoSummary(
    id: VideoId('BV1xx411c7mD'),
    title: '测试视频',
    coverUrl: '',
    author: '作者',
    duration: Duration(minutes: 12),
  ),
  description: '',
  parts: const [
    VideoPart(
      cid: '123',
      page: 1,
      title: '第一集',
      duration: Duration(minutes: 12),
    ),
  ],
);

final class _FakeDownloads implements DownloadRepository {
  late DownloadTask task;
  Completer<DownloadTask>? pending;
  int offlineReads = 0;
  final started = Completer<void>();

  @override
  DownloadQueueState get current => DownloadQueueState();
  @override
  Stream<DownloadQueueState> get changes => const Stream.empty();
  @override
  Future<DownloadTask> offlineTask(String id) async {
    offlineReads++;
    if (!started.isCompleted) started.complete();
    expect(id, task.id);
    return pending?.future ?? task;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeNetwork
    implements PlaybackRepository, PlaybackMetadataRepository {
  final calls = <String>[];
  static final media = PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri(scheme: 'https', host: 'cdn.example', path: '/video.m4s')],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [Uri(scheme: 'https', host: 'cdn.example', path: '/audio.m4s')],
      codec: 'mp4a',
      bandwidth: 100,
    ),
    quality: 80,
    qualities: const [80],
    duration: const Duration(minutes: 12),
    headers: const {},
  );

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    calls.add('resolve');
    return media;
  }

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('comments');
    return const [
      TimedComment(
        id: 'network',
        position: Duration.zero,
        text: 'network',
        mode: 1,
        color: 0,
        fontSize: 25,
      ),
    ];
  }

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('subtitles');
    return const [];
  }

  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('subtitleCues');
    return const [];
  }

  @override
  Future<PlaybackMetadata> metadata(
    VideoDetail video,
    VideoPart part, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('metadata');
    return const PlaybackMetadata(subtitles: [], chapters: []);
  }

  @override
  Future<VideoStoryboard?> storyboard(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('storyboard');
    return null;
  }
}

final class _FakeContent implements ContentPlaybackRepository {
  _FakeContent(this.calls);
  final List<String> calls;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    calls.add('content');
    return _FakeNetwork.media;
  }
}
