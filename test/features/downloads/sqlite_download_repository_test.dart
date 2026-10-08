import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/data/sqlite_download_repository.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/domain/download_muxer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File databaseFile;
  late HttpServer server;
  late _Sources sources;
  late AppDatabase db;
  late SqliteDownloadRepository repository;
  DownloadMuxer? muxer;
  var slow = false;
  var streamSlow = false;
  var rejectAudioOnce = false;
  var videoRequests = 0;
  final media = List<int>.generate(2048, (index) => index % 256);

  Future<void> openRepository() async {
    db = AppDatabase(NativeDatabase(databaseFile));
    repository = SqliteDownloadRepository(
      db,
      sources,
      defaultDirectory: () async => root.path,
      muxer: muxer,
    );
    await repository.initialize();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bilisail_queue');
    databaseFile = File('${root.path}/downloads.sqlite');
    slow = false;
    streamSlow = false;
    rejectAudioOnce = false;
    videoRequests = 0;
    muxer = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.startsWith('/video')) videoRequests++;
      if (rejectAudioOnce && request.uri.path == '/audio') {
        rejectAudioOnce = false;
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final start = range == null
          ? 0
          : int.parse(range.substring(6, range.length - 1));
      request.response.statusCode = range == null ? 200 : 206;
      request.response.headers.contentLength = media.length - start;
      if (range != null) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${media.length - 1}/${media.length}',
        );
      }
      if (slow) await Future<void>.delayed(const Duration(milliseconds: 300));
      if (streamSlow && start == 0) {
        request.response.add(media.take(512).toList());
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        request.response.add(media.skip(512).take(512).toList());
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        request.response.add(media.skip(1024).toList());
      } else {
        request.response.add(media.skip(start).toList());
      }
      await request.response.close();
    });
    sources = _Sources(Uri.parse('http://127.0.0.1:${server.port}'));
    await openRepository();
  });

  tearDown(() async {
    await repository.close();
    await db.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test('download completes with verified files and URL-free records', () async {
    await repository.enqueue([item], const DownloadSelection());
    await _waitFor(repository, DownloadStatus.completed);
    final task = repository.current.tasks.single;
    expect(task.tracks.length, 2);
    expect(task.tracks.every((track) => track.complete), isTrue);
    expect(await File('${task.directory}/video.m4s').length(), media.length);
    expect(await File('${task.directory}/audio.m4s').length(), media.length);
    expect(await File('${task.directory}/extras.json').exists(), isTrue);
    expect(
      (await File(
        '${task.directory}/manifest.json',
      ).readAsString()).contains('http'),
      isFalse,
    );
    final record = await db
        .customSelect('SELECT record_json FROM download_tasks')
        .getSingle();
    expect(record.read<String>('record_json').contains('http'), isFalse);
    expect((await repository.offlineTask(task.id)).id, task.id);
  });

  test(
    'reopening verifies completed files and rejects damaged media',
    () async {
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      final id = repository.current.tasks.single.id;
      final directory = repository.current.tasks.single.directory;
      await repository.close();
      await db.close();
      await openRepository();
      expect(
        (await repository.offlineTask(id)).status,
        DownloadStatus.completed,
      );
      await File('$directory/video.m4s').writeAsBytes([1, 2, 3]);
      await expectLater(repository.offlineTask(id), throwsException);
      expect(repository.current.tasks.single.status, DownloadStatus.failed);
    },
  );

  test(
    'process restart pauses an in-flight task and account switch isolates it',
    () async {
      slow = true;
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.downloading);
      await repository.close();
      await db.close();
      await openRepository();
      expect(repository.current.tasks.single.status, DownloadStatus.paused);
      sources.scope = 'user:2';
      sources.epoch++;
      await repository.sessionChanged();
      expect(repository.current.tasks, isEmpty);
      sources.scope = 'guest';
      sources.epoch++;
      await repository.sessionChanged();
      expect(repository.current.tasks.single.status, DownloadStatus.paused);
      slow = false;
      await repository.resume(repository.current.tasks.single.id);
      await _waitFor(repository, DownloadStatus.completed);
    },
  );

  test(
    'removing an index can retain files and deleting files is confined to task',
    () async {
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      final task = repository.current.tasks.single;
      final unrelated = File('${root.path}/keep.txt')
        ..writeAsStringSync('keep');
      await repository.remove(task.id, deleteFiles: false);
      expect(await Directory(task.directory).exists(), isTrue);
      expect(await unrelated.readAsString(), 'keep');
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      await repository.remove(
        repository.current.tasks.single.id,
        deleteFiles: true,
      );
      expect(await unrelated.readAsString(), 'keep');
    },
  );

  test(
    'expired audio URL with changed identities resets both tracks',
    () async {
      rejectAudioOnce = true;
      sources.changeIdentityOnRefresh = true;
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      final task = repository.current.tasks.single;
      expect(sources.resolveCalls, 2);
      expect(videoRequests, 2);
      expect(task.tracks.map((track) => track.identity).toSet(), {
        'video:2',
        'audio:2',
      });
      expect(await repository.offlineTask(task.id), isA<DownloadTask>());
    },
  );

  test('refresh racing with remove cannot restore a deleted index', () async {
    await repository.enqueue([item], const DownloadSelection());
    await _waitFor(repository, DownloadStatus.completed);
    final id = repository.current.tasks.single.id;
    await Future.wait([
      repository.refresh(),
      repository.remove(id, deleteFiles: false),
    ]);
    expect(repository.current.tasks, isEmpty);
    expect(
      (await db
              .customSelect('SELECT COUNT(*) AS n FROM download_tasks')
              .getSingle())
          .read<int>('n'),
      0,
    );
  });

  test('account switch during removal retains the old account files', () async {
    slow = true;
    await repository.enqueue([item], const DownloadSelection());
    await _waitFor(repository, DownloadStatus.downloading);
    final task = repository.current.tasks.single;
    final removal = repository.remove(task.id, deleteFiles: true);
    sources.scope = 'user:2';
    sources.epoch++;
    final switchAccount = repository.sessionChanged();
    await Future.wait([removal, switchAccount]);
    expect(await Directory(task.directory).exists(), isTrue);
    sources.scope = 'guest';
    sources.epoch++;
    await repository.sessionChanged();
    expect(repository.current.tasks.single.id, task.id);
  });

  test('streaming progress publishes a nonzero transfer speed', () async {
    streamSlow = true;
    await repository.enqueue([item], const DownloadSelection());
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var observed = false;
    while (DateTime.now().isBefore(deadline)) {
      final task = repository.current.tasks.single;
      if (task.bytesPerSecond > 0) {
        observed = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(observed, isTrue);
    await _waitFor(repository, DownloadStatus.completed);
  });

  test(
    'background database failure becomes a visible recoverable error',
    () async {
      streamSlow = true;
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.downloading);
      await db.close();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (repository.current.failure == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(repository.current.failure?.kind, AppFailureKind.storage);
      expect(repository.current.tasks.single.status, DownloadStatus.failed);
    },
  );

  test('capacity rejection leaves a 490-item queue unchanged', () async {
    slow = true;
    await repository.enqueue([item], const DownloadSelection());
    await _waitFor(repository, DownloadStatus.downloading);
    await repository.pause(repository.current.tasks.single.id);
    final row = await db
        .customSelect('SELECT record_json FROM download_tasks')
        .getSingle();
    final template =
        jsonDecode(row.read<String>('record_json')) as Map<String, dynamic>;
    await repository.close();
    await db.transaction(() async {
      for (var cid = 2; cid <= 490; cid++) {
        final id = cid.toRadixString(16).padLeft(32, '0');
        final record = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
        record['id'] = id;
        record['directory'] = '${root.path}/fixture/$id';
        record['status'] = 'paused';
        record['tracks'] = [];
        (record['part'] as Map<String, dynamic>)['cid'] = '$cid';
        await db.customStatement(
          'INSERT INTO download_tasks(id,scope,item_key,record_json) VALUES (?,?,?,?)',
          [id, 'guest', 'video:BV1234567890:$cid', jsonEncode(record)],
        );
      }
    });
    await db.close();
    await openRepository();
    expect(repository.current.tasks.length, 490);
    final extra = List.generate(
      20,
      (index) => DownloadItem(
        video: item.video,
        part: VideoPart(
          cid: '${501 + index}',
          page: index + 1,
          title: 'Extra',
          duration: const Duration(seconds: 3),
        ),
      ),
    );
    await expectLater(
      repository.enqueue(extra, const DownloadSelection()),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', AppFailureKind.storage),
      ),
    );
    expect(repository.current.tasks.length, 490);
    expect(
      (await db
              .customSelect('SELECT COUNT(*) AS n FROM download_tasks')
              .getSingle())
          .read<int>('n'),
      490,
    );
  });

  test(
    'two simultaneous windows enqueue one task for the same content',
    () async {
      await Future.wait([
        repository.enqueue([item], const DownloadSelection()),
        repository.enqueue([item], const DownloadSelection()),
      ]);
      expect(repository.current.tasks.length, 1);
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM download_tasks')
                .getSingle())
            .read<int>('n'),
        1,
      );
    },
  );

  Future<_Muxer> useMuxer() async {
    await repository.close();
    await db.close();
    final value = _Muxer();
    muxer = value;
    await openRepository();
    return value;
  }

  const mergedSelection = DownloadSelection(output: DownloadOutput.mp4);

  test(
    'merged completion commits output and reopens after removing sources',
    () async {
      final native = await useMuxer();
      expect(repository.current.canMerge, isTrue);
      await repository.enqueue([item], mergedSelection);
      await _waitFor(repository, DownloadStatus.completed);
      await repository.close(); // Also wait for post-commit cleanup.
      final task = repository.current.tasks.single;
      expect(native.calls, 1);
      expect(task.mergedMedia?.bytes, media.length * 2);
      expect(await File('${task.directory}/media.mp4').exists(), isTrue);
      expect(await File('${task.directory}/video.m4s').exists(), isFalse);
      expect(await File('${task.directory}/audio.m4s').exists(), isFalse);
      await db.close();
      await openRepository();
      expect(
        (await repository.offlineTask(task.id)).mergedMedia?.sha256,
        task.mergedMedia?.sha256,
      );
      expect(
        repository.current.tasks.single.selection.output,
        DownloadOutput.mp4,
      );
      await File('${task.directory}/media.mp4')
          .writeAsBytes(List.filled(media.length * 2, 0));
      await expectLater(
        repository.offlineTask(task.id),
        throwsA(isA<AppFailure>()),
      );
    },
  );

  test(
    'merge failure preserves originals and retry needs no new source request',
    () async {
      final native = (await useMuxer())..failNext = true;
      await repository.enqueue([item], mergedSelection);
      final failure = await repository.changes.firstWhere(
        (state) =>
            state.tasks.any((task) => task.status == DownloadStatus.failed),
      );
      final task = failure.tasks.single;
      expect(await File('${task.directory}/video.m4s').length(), media.length);
      expect(await File('${task.directory}/audio.m4s').length(), media.length);
      expect(await File('${task.directory}/media.mp4.part').exists(), isFalse);
      final resolves = sources.resolveCalls;
      await repository.resume(task.id);
      await _waitFor(repository, DownloadStatus.completed);
      expect(native.calls, 2);
      expect(sources.resolveCalls, resolves);
      expect(videoRequests, 1);
    },
  );

  test(
    'pause during merge waits for cancellation and removes partial output',
    () async {
      final native = (await useMuxer())..block = true;
      await repository.enqueue([item], mergedSelection);
      await native.started.future;
      final id = repository.current.tasks.single.id;
      await repository.pause(id);
      final task = repository.current.tasks.single;
      expect(task.status, DownloadStatus.paused);
      expect(task.failure, isNull);
      expect(await File('${task.directory}/media.mp4.part').exists(), isFalse);
      expect(await File('${task.directory}/video.m4s').exists(), isTrue);
      native.block = false;
      await repository.resume(id);
      await _waitFor(repository, DownloadStatus.completed);
    },
  );

  test(
    'switching accounts during merge cannot commit into the new scope',
    () async {
      final native = (await useMuxer())..block = true;
      await repository.enqueue([item], mergedSelection);
      await native.started.future;
      final task = repository.current.tasks.single;
      sources.scope = 'user:2';
      sources.epoch++;
      await repository.sessionChanged();
      expect(repository.current.tasks, isEmpty);
      expect(await File('${task.directory}/media.mp4').exists(), isFalse);
      expect(await File('${task.directory}/media.mp4.part').exists(), isFalse);
      sources.scope = 'guest';
      sources.epoch++;
      await repository.sessionChanged();
      expect(repository.current.tasks.single.status, DownloadStatus.paused);
    },
  );

  test(
    'manifest-before-SQLite interruption recovers completed merged output',
    () async {
      await useMuxer();
      await repository.enqueue([item], mergedSelection);
      await _waitFor(repository, DownloadStatus.completed);
      await repository.close();
      final task = repository.current.tasks.single;
      final row = await db
          .customSelect('SELECT record_json FROM download_tasks')
          .getSingle();
      final record =
          jsonDecode(row.read<String>('record_json')) as Map<String, Object?>;
      record['status'] = 'muxing';
      await db.customStatement('UPDATE download_tasks SET record_json = ?', [
        jsonEncode(record),
      ]);
      await db.close();
      await openRepository();
      expect(
        (await repository.offlineTask(task.id)).status,
        DownloadStatus.completed,
      );
    },
  );

  test(
    'output-before-manifest interruption resumes from verified output only',
    () async {
      final native = await useMuxer();
      await repository.enqueue([item], mergedSelection);
      await _waitFor(repository, DownloadStatus.completed);
      await repository.close();
      final task = repository.current.tasks.single;
      await File('${task.directory}/manifest.json').delete();
      final row = await db
          .customSelect('SELECT record_json FROM download_tasks')
          .getSingle();
      final record =
          jsonDecode(row.read<String>('record_json')) as Map<String, Object?>;
      record['status'] = 'muxing';
      await db.customStatement('UPDATE download_tasks SET record_json = ?', [
        jsonEncode(record),
      ]);
      await db.close();
      await openRepository();
      expect(repository.current.tasks.single.status, DownloadStatus.paused);
      final resolves = sources.resolveCalls;
      await repository.resume(task.id);
      await _waitFor(repository, DownloadStatus.completed);
      expect(native.calls, 1);
      expect(sources.resolveCalls, resolves);
    },
  );

  test(
    'legacy v1 record keeps separate output and unavailable mux refuses MP4',
    () async {
      await expectLater(
        repository.enqueue([item], mergedSelection),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.current.tasks, isEmpty);
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      await repository.close();
      final row = await db
          .customSelect('SELECT record_json FROM download_tasks')
          .getSingle();
      final record =
          jsonDecode(row.read<String>('record_json')) as Map<String, Object?>;
      record['version'] = 1;
      (record['selection'] as Map<String, Object?>).remove('output');
      await db.customStatement('UPDATE download_tasks SET record_json = ?', [
        jsonEncode(record),
      ]);
      await db.close();
      await openRepository();
      final task = repository.current.tasks.single;
      expect(task.selection.output, DownloadOutput.separate);
      expect(
        (await repository.offlineTask(task.id)).status,
        DownloadStatus.completed,
      );
    },
  );

  test(
    'startup cleanup keeps source backups if merged output has been damaged',
    () async {
      await useMuxer();
      await repository.enqueue([item], mergedSelection);
      await _waitFor(repository, DownloadStatus.completed);
      await repository.close();
      final task = repository.current.tasks.single;
      await File('${task.directory}/video.m4s').writeAsBytes(media);
      await File('${task.directory}/audio.m4s').writeAsBytes(media);
      await File('${task.directory}/media.mp4')
          .writeAsBytes(List.filled(media.length * 2, 0));
      await db.close();
      await openRepository();
      expect(await File('${task.directory}/video.m4s').exists(), isTrue);
      expect(await File('${task.directory}/audio.m4s').exists(), isTrue);
      await expectLater(
        repository.offlineTask(task.id),
        throwsA(isA<AppFailure>()),
      );
      await repository.resume(task.id);
      await _waitFor(repository, DownloadStatus.completed);
    },
  );

  test('separate and merged versions have distinct queue identities', () async {
    final native = (await useMuxer())..block = true;
    await repository.enqueue([item], mergedSelection);
    await native.started.future;
    await repository.enqueue([item], const DownloadSelection());
    expect(repository.current.tasks.length, 2);
    await repository.pauseAll();
  });
}

final class _Muxer implements DownloadMuxer {
  bool failNext = false, block = false;
  int calls = 0;
  final started = Completer<void>();
  @override
  bool get available => true;
  @override
  Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required RequestCancellation cancellation,
    required void Function(double) onProgress,
  }) async {
    calls++;
    await File(outputPath).writeAsBytes([1]);
    if (!started.isCompleted) started.complete();
    if (block) {
      final cancelled = Completer<void>();
      cancellation.onCancel(() {
        if (!cancelled.isCompleted) cancelled.complete();
      });
      await cancelled.future;
      throw const AppFailure(AppFailureKind.cancelled, 'cancelled');
    }
    if (failNext) {
      failNext = false;
      throw const AppFailure(AppFailureKind.storage, 'merge failed');
    }
    onProgress(0.5);
    await File(outputPath).writeAsBytes([
      ...await File(videoPath).readAsBytes(),
      ...await File(audioPath).readAsBytes(),
    ]);
    onProgress(1);
  }
}

Future<void> _waitFor(
  SqliteDownloadRepository repository,
  DownloadStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (repository.current.tasks.any((task) => task.status == status)) return;
    if (repository.current.tasks.any(
      (task) => task.status == DownloadStatus.failed,
    )) {
      fail('Download failed: ${repository.current.tasks.single.failure}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(
    'Timed out waiting for $status: ${repository.current.tasks.map((t) => t.status)}',
  );
}

final item = DownloadItem(
  video: const VideoSummary(
    id: VideoId('BV1234567890'),
    title: 'Fixture',
    coverUrl: '',
    author: 'Author',
    duration: Duration(seconds: 3),
  ),
  part: const VideoPart(
    cid: '1',
    page: 1,
    title: 'P1',
    duration: Duration(seconds: 3),
  ),
);

final class _Sources implements DownloadSourceRepository {
  _Sources(this.base);
  final Uri base;
  String scope = 'guest';
  int epoch = 0;
  int resolveCalls = 0;
  bool changeIdentityOnRefresh = false;
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
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
    resolveCalls++;
    final revision = changeIdentityOnRefresh && resolveCalls > 1 ? 2 : 1;
    return DownloadResolvedSource(
      video: DownloadTrackSource(
        identity: 'video:$revision',
        kind: DownloadTrackKind.video,
        urls: [base.resolve('/video$revision')],
        codec: 'avc1',
        bandwidth: 1000,
      ),
      audio: DownloadTrackSource(
        identity: 'audio:$revision',
        kind: DownloadTrackKind.audio,
        urls: [base.resolve(revision == 1 ? '/audio' : '/audio2')],
        codec: 'mp4a',
        bandwidth: 128,
      ),
      quality: 80,
      duration: const Duration(seconds: 3),
      headers: const {},
    );
  }

  @override
  Future<DownloadExtras> extras(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) async => DownloadExtras();
}
