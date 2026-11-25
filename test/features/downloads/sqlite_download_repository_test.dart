import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/video_codec.dart';
import 'package:bilisail/features/downloads/data/sqlite_download_repository.dart';
import 'package:bilisail/features/downloads/data/download_file_store.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/domain/download_muxer.dart';
import 'package:bilisail/features/downloads/domain/public_download_storage.dart';
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
  _PublicStorage? publicStorage;
  var slow = false;
  var streamSlow = false;
  var rejectAudioOnce = false;
  var videoRequests = 0;
  Future<void> Function(HttpResponse)? streamVideo;
  final media = List<int>.generate(2048, (index) => index % 256);

  Future<void> openRepository({
    Future<void> Function(bool)? setBackgroundActive,
    Future<void> Function()? requestMergedDownloadAccess,
    Future<void> Function(DownloadTask)? onMergedDownloadCompleted,
    DateTime Function()? clock,
    DownloadFileStore? files,
    String? directory,
  }) async {
    db = AppDatabase(NativeDatabase(databaseFile));
    repository = SqliteDownloadRepository(
      db,
      sources,
      defaultDirectory: () async => directory ?? root.path,
      files: files,
      setBackgroundActive: setBackgroundActive,
      muxer: muxer,
      publicStorage: publicStorage,
      requestMergedDownloadAccess: requestMergedDownloadAccess,
      onMergedDownloadCompleted: onMergedDownloadCompleted,
      clock: clock,
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
    streamVideo = null;
    muxer = null;
    publicStorage = null;
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
      if (streamVideo case final send?
          when request.uri.path.startsWith('/video')) {
        await send(request.response);
      } else if (streamSlow && start == 0) {
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

  test(
    'shared season metadata survives restart alongside legacy episodes',
    () async {
      DownloadItem episode(int index, {bool legacy = false}) => DownloadItem(
        video: item.video,
        part: VideoPart(
          cid: '$index',
          page: index,
          title: '第$index集',
          duration: item.part.duration,
        ),
        episodeId: '$index',
        seasonId: '600',
        work: legacy
            ? null
            : const DownloadWork(description: '整季简介', seasonType: 4),
        section: legacy ? null : '花絮',
        episodeTitle: legacy ? null : '特别篇',
        episodeLongTitle: legacy ? null : '幕后',
      );
      await repository.enqueue([
        episode(1, legacy: true),
      ], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      final oldId = repository.current.tasks.single.id;
      await db.customStatement(
        r"""UPDATE download_tasks SET record_json=json_set(record_json,'$.version',2)""",
      );
      await repository.enqueue([episode(3)], const DownloadSelection());
      final newId = repository.current.tasks
          .firstWhere((t) => t.id != oldId)
          .id;
      await repository.close();
      await db.close();
      await openRepository();
      final old = await repository.offlineTask(oldId);
      final newer = repository.current.tasks.firstWhere((t) => t.id == newId);
      expect(old.item.work?.description, '整季简介');
      expect(old.item.category(old.item.work), DownloadCategory.guochuang);
      expect(old.item.section, isNull);
      expect(newer.item.work, same(old.item.work));
      expect(
        (
          newer.item.section,
          newer.item.episodeTitle,
          newer.item.episodeLongTitle,
        ),
        ('花絮', '特别篇', '幕后'),
      );
      expect(
        (await db.customSelect('SELECT record_json FROM download_tasks').get())
            .every((row) => !row.read<String>('record_json').contains('整季简介')),
        isTrue,
      );
      await repository.remove(newId, deleteFiles: false);
      expect(repository.current.works.length, 1);
      await repository.remove(oldId, deleteFiles: false);
      expect(repository.current.works, isEmpty);
      expect(
        await db
            .customSelect(
              "SELECT key FROM settings WHERE key LIKE 'downloads.work.%'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'background execution spans concurrent and queued jobs until idle',
    () async {
      await repository.close();
      await db.close();
      final started = Completer<void>();
      final idle = Completer<void>();
      final active = <bool>[];
      await openRepository(
        setBackgroundActive: (value) async {
          active.add(value);
          if (value) {
            await started.future;
          } else {
            idle.complete();
          }
        },
      );
      final batch = [
        for (var index = 1; index <= 3; index++)
          DownloadItem(
            video: item.video,
            part: VideoPart(
              cid: '$index',
              page: index,
              title: 'P$index',
              duration: const Duration(seconds: 3),
            ),
          ),
      ];
      await repository.enqueue(batch, const DownloadSelection());
      expect(active, [true]);
      expect(sources.resolveCalls, 0);
      started.complete();
      await idle.future.timeout(const Duration(seconds: 5));
      expect(active, [true, false]);
      expect(
        repository.current.tasks.map((t) => t.status),
        everyElement(DownloadStatus.completed),
      );
    },
  );

  test('snapshots keep creation order through transfers and removal', () async {
    await repository.close();
    await db.close();
    var now = DateTime(2026, 11, 22);
    await openRepository(
      clock: () => now = now.add(const Duration(milliseconds: 1)),
    );
    slow = true;
    final items = [
      for (var index = 1; index <= 3; index++)
        DownloadItem(
          video: item.video,
          part: VideoPart(
            cid: '$index',
            page: index,
            title: 'P$index',
            duration: item.part.duration,
          ),
        ),
    ];
    Iterable<String> order(DownloadQueueState state) =>
        state.tasks.map((task) => task.item.part.cid);
    final finished = repository.changes
        .firstWhere(
          (state) =>
              state.tasks.length == items.length &&
              state.tasks.every(
                (task) => task.status == DownloadStatus.completed,
              ),
        )
        .timeout(const Duration(seconds: 5));
    await repository.enqueue(items, const DownloadSelection());
    final queued = repository.current;
    expect(order(queued), ['3', '2', '1']);
    final completed = await finished;
    expect(order(completed), ['3', '2', '1']);
    expect(queued.tasks.first.status, isNot(DownloadStatus.completed));
    expect(completed.tasks.first.downloadedBytes, media.length * 2);
    await repository.remove(completed.tasks[1].id, deleteFiles: false);
    expect(order(repository.current), ['3', '1']);
    expect(order(completed), ['3', '2', '1']);
  });

  test(
    'manual pause while the system service starts keeps the task paused',
    () async {
      await repository.close();
      await db.close();
      final started = Completer<void>();
      final active = <bool>[];
      await openRepository(
        setBackgroundActive: (value) async {
          active.add(value);
          if (value) await started.future;
        },
      );
      await repository.enqueue([item], const DownloadSelection());
      final paused = repository.pause(repository.current.tasks.single.id);
      await Future<void>.delayed(Duration.zero);
      started.complete();
      await paused;
      expect(repository.current.tasks.single.status, DownloadStatus.paused);
      expect(sources.resolveCalls, 0);
      expect(active, [true, false]);
    },
  );

  test(
    'public output survives restart without hidden media or source reads',
    () async {
      await repository.close();
      await db.close();
      publicStorage = _PublicStorage();
      await openRepository();
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.completed);
      await repository.close();
      final task = repository.current.tasks.single;
      expect(task.publicDestination, 'downloads');
      expect(task.publicFiles.length, 2);
      expect(await File('${task.directory}/video.m4s').exists(), isFalse);
      expect(await File('${task.directory}/audio.m4s').exists(), isFalse);
      final requests = videoRequests;
      await db.close();
      await openRepository();
      expect(
        (await repository.offlineTask(task.id)).publicFiles,
        task.publicFiles,
      );
      expect(videoRequests, requests);
      publicStorage!.available = false;
      await expectLater(
        repository.offlineTask(task.id),
        throwsA(isA<AppFailure>()),
      );
      expect(publicStorage!.deleted, isFalse);
      publicStorage!.available = true;
      await repository.refresh();
      expect(
        (await repository.offlineTask(task.id)).status,
        DownloadStatus.completed,
      );
      await repository.remove(task.id, deleteFiles: true);
      expect(publicStorage!.deleted, isTrue);
    },
  );

  test(
    'public publication failure retains private originals for retry',
    () async {
      await repository.close();
      await db.close();
      publicStorage = _PublicStorage()..failPublish = true;
      await openRepository();
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.failed);
      final task = repository.current.tasks.single;
      expect(await File('${task.directory}/video.m4s').exists(), isTrue);
      expect(task.publicFiles, isEmpty);
      publicStorage!.failPublish = false;
      publicStorage!.selected = 'content://other/tree/new';
      final requests = videoRequests;
      await repository.resume(task.id);
      await _waitFor(repository, DownloadStatus.completed);
      expect(videoRequests, requests);
      expect(repository.current.tasks.single.publicFiles.length, 2);
      expect(publicStorage!.destinations, ['downloads', 'downloads']);
    },
  );

  test(
    'download commits without media digests and keeps URL-free records',
    () async {
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
    },
  );

  test(
    'Android anchor supports legacy records through resume, offline and delete',
    () async {
      await repository.close();
      await db.close();
      final documents = await Directory('${root.path}/app_flutter').create();
      final alias = await Link('${root.path}/system_alias')
          .create(documents.path);
      final files = DownloadFileStore(
        trustedDocumentsDirectory: () async => documents.path,
      );
      final downloadRoot = '${documents.path}/BiliSail/offline';
      await openRepository(files: files, directory: downloadRoot);
      slow = true;
      await repository.enqueue([item], const DownloadSelection());
      await _waitFor(repository, DownloadStatus.downloading);
      final id = repository.current.tasks.single.id;
      final directory = repository.current.tasks.single.directory;
      await repository.close();
      final row = await db
          .customSelect('SELECT record_json FROM download_tasks')
          .getSingle();
      final record =
          jsonDecode(row.read<String>('record_json')) as Map<String, dynamic>;
      final legacyPath = directory.replaceFirst(documents.path, alias.path);
      record['directory'] = legacyPath;
      await db.customStatement('UPDATE download_tasks SET record_json = ?', [
        jsonEncode(record),
      ]);
      await db.close();
      await openRepository(files: files, directory: downloadRoot);
      expect(repository.current.tasks.single.status, DownloadStatus.paused);
      expect(repository.current.tasks.single.directory, legacyPath);
      slow = false;
      await repository.resume(id);
      await _waitFor(repository, DownloadStatus.completed);
      expect((await repository.offlineTask(id)).directory, legacyPath);
      expect(await File('$directory/video.m4s').length(), media.length);
      await repository.remove(id, deleteFiles: true);
      expect(await Directory(directory).exists(), isFalse);
      expect(await Link(alias.path).exists(), isTrue);
    },
    skip: Platform.isWindows
        ? 'Creating Windows symlinks requires additional privileges.'
        : false,
  );

  test(
    'modified media remains playable across refresh and process restart',
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
      expect(
        (await repository.offlineTask(id)).status,
        DownloadStatus.completed,
      );
      await repository.refresh();
      await repository.close();
      await db.close();
      await openRepository();
      expect(
        (await repository.offlineTask(id)).status,
        DownloadStatus.completed,
      );
      expect(
        repository.current.tasks.single.tracks.every((t) => t.sha256 == null),
        isTrue,
      );
      await File('$directory/audio.m4s').delete();
      await expectLater(
        repository.offlineTask(id),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'missing track',
            contains('音频'),
          ),
        ),
      );
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
    var now = DateTime.utc(2026, 10, 11);
    await repository.close();
    await db.close();
    await openRepository(clock: () => now);

    final nextChunks = List.generate(3, (_) => Completer<void>());
    addTearDown(() {
      for (final next in nextChunks) {
        if (!next.isCompleted) next.complete();
      }
    });
    streamVideo = (response) async {
      // flush alone does not guarantee separate client progress callbacks.
      // Wait for the client to observe each chunk before sending another.
      response.bufferOutput = false;
      for (var index = 0; index < 4; index++) {
        if (index > 0) await nextChunks[index - 1].future;
        response.add(media.skip(index * 512).take(512).toList());
        await response.flush();
      }
    };

    Future<DownloadTask> progressAt(int bytes) => repository.changes
        .firstWhere(
          (state) => state.tasks.any(
            (task) =>
                task.status == DownloadStatus.downloading &&
                task.downloadedBytes == bytes,
          ),
        )
        .then((state) => state.tasks.single)
        .timeout(const Duration(seconds: 5));

    final firstChunk = progressAt(512);
    await repository.enqueue([item], const DownloadSelection());
    expect((await firstChunk).bytesPerSecond, 0);

    now = now.add(const Duration(milliseconds: 250));
    final secondChunk = progressAt(1024);
    nextChunks[0].complete();
    expect((await secondChunk).bytesPerSecond, 0);

    now = now.add(const Duration(milliseconds: 250));
    final thirdChunk = progressAt(1536);
    nextChunks[1].complete();
    expect((await thirdChunk).bytesPerSecond, 2048);

    nextChunks[2].complete();
    await _waitFor(repository, DownloadStatus.completed);
    expect(repository.current.tasks.single.bytesPerSecond, 0);
    expect(repository.current.tasks.single.downloadedBytes, media.length * 2);
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

  test('separate downloads bypass permission and Photos import', () async {
    await repository.close();
    await db.close();
    final calls = <String>[];
    await openRepository(
      requestMergedDownloadAccess: () async => calls.add('permission'),
      onMergedDownloadCompleted: (_) async => calls.add('import'),
    );
    await repository.enqueue([
      item,
    ], const DownloadSelection(output: DownloadOutput.separate));
    await _waitFor(repository, DownloadStatus.completed);
    await repository.close();
    expect(calls, isEmpty);
  });

  for (final output in [DownloadOutput.mp4, DownloadOutput.mkv]) {
    group(output.name, () {
      final mergedSelection = DownloadSelection(output: output);

      test(
        'imports committed output once and keeps it if Photos fails',
        () async {
          await repository.close();
          await db.close();
          muxer = _Muxer();
          final permissionRequested = Completer<void>();
          final permission = Completer<void>();
          final imported = Completer<(DownloadTask, String, bool)>();
          var exports = 0;
          Future<void> export(DownloadTask task) async {
            exports++;
            final row = await db
                .customSelect('SELECT record_json FROM download_tasks')
                .getSingle();
            final record = jsonDecode(
              row.read<String>('record_json'),
            ) as Map<String, Object?>;
            final media = File('${task.directory}/${output.fileName}');
            imported.complete((
              task,
              record['status'] as String,
              await media.exists(),
            ));
            throw const AppFailure(
              AppFailureKind.permission,
              'Photos access denied',
            );
          }

          await openRepository(
            requestMergedDownloadAccess: () {
              permissionRequested.complete();
              return permission.future;
            },
            onMergedDownloadCompleted: export,
          );
          final pending = repository.enqueue([item], mergedSelection);
          await permissionRequested.future.timeout(const Duration(seconds: 5));
          expect(videoRequests, 0);
          permission.complete();
          await pending;
          final (task, storedStatus, wasReadable) = await imported.future
              .timeout(const Duration(seconds: 5));
          expect(task.status, DownloadStatus.completed);
          expect(task.mergedMedia?.output, output);
          expect(storedStatus, 'completed');
          expect(wasReadable, isTrue);
          await repository.enqueue([item], mergedSelection);
          await repository.close();
          expect(
            repository.current.tasks.single.status,
            DownloadStatus.completed,
          );
          await db.close();
          await openRepository(onMergedDownloadCompleted: export);
          expect(
            (await repository.offlineTask(task.id)).status,
            DownloadStatus.completed,
          );
          expect(exports, 1);
        },
      );

      test('public merge retries without remux', () async {
        final native = await useMuxer();
        await repository.close();
        await db.close();
        publicStorage = _PublicStorage()..failPublish = true;
        await openRepository();
        await repository.enqueue([item], mergedSelection);
        await _waitFor(repository, DownloadStatus.failed);
        final task = repository.current.tasks.single;
        expect(task.publicFiles, isEmpty);
        final mergedFile = File('${task.directory}/${output.fileName}');
        expect(await mergedFile.exists(), isTrue);
        publicStorage!.failPublish = false;
        await repository.resume(task.id);
        await _waitFor(repository, DownloadStatus.completed);
        await repository.close();
        expect(native.calls, 1);
        expect(repository.current.tasks.single.publicFiles.keys, [
          output.fileName,
        ]);
        for (final name in ['video.m4s', 'audio.m4s', output.fileName]) {
          expect(await File('${task.directory}/$name').exists(), isFalse);
        }
        await db.close();
        await openRepository();
        expect(
          (await repository.offlineTask(task.id)).status,
          DownloadStatus.completed,
        );
      });

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
          expect(native.outputs, [output]);
          expect(task.mergedMedia?.bytes, media.length * 2);
          expect(
            await File('${task.directory}/${output.fileName}').exists(),
            isTrue,
          );
          expect(await File('${task.directory}/video.m4s').exists(), isFalse);
          expect(await File('${task.directory}/audio.m4s').exists(), isFalse);
          await db.close();
          await openRepository();
          expect(
            (await repository.offlineTask(task.id)).mergedMedia?.sha256,
            task.mergedMedia?.sha256,
          );
          expect(repository.current.tasks.single.selection.output, output);
          await File('${task.directory}/${output.fileName}')
              .writeAsBytes(List.filled(media.length * 2, 0));
          expect(
            (await repository.offlineTask(task.id)).status,
            DownloadStatus.completed,
          );
        },
      );

      test('merge failure preserves originals and retry needs no new source request', () async {
        final native = (await useMuxer())..failNext = true;
        await repository.enqueue([item], mergedSelection);
        final failure = await repository.changes.firstWhere(
          (state) =>
              state.tasks.any((task) => task.status == DownloadStatus.failed),
        );
        final task = failure.tasks.single;
        expect(
          await File('${task.directory}/video.m4s').length(),
          media.length,
        );
        expect(
          await File('${task.directory}/audio.m4s').length(),
          media.length,
        );
        expect(
          await File('${task.directory}/${output.fileName}.part').exists(),
          isFalse,
        );
        final resolves = sources.resolveCalls;
        await repository.resume(task.id);
        await _waitFor(repository, DownloadStatus.completed);
        expect(native.calls, 2);
        expect(sources.resolveCalls, resolves);
        expect(videoRequests, 1);
      });

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
          expect(
            await File('${task.directory}/${output.fileName}.part').exists(),
            isFalse,
          );
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
          expect(
            await File('${task.directory}/${output.fileName}').exists(),
            isFalse,
          );
          expect(
            await File('${task.directory}/${output.fileName}.part').exists(),
            isFalse,
          );
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
          final record = jsonDecode(
            row.read<String>('record_json'),
          ) as Map<String, Object?>;
          record['status'] = 'muxing';
          await db.customStatement(
            'UPDATE download_tasks SET record_json = ?',
            [jsonEncode(record)],
          );
          await db.close();
          await openRepository();
          expect(
            (await repository.offlineTask(task.id)).status,
            DownloadStatus.completed,
          );
        },
      );

      test(
        'committed output recovers without the legacy integrity manifest',
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
          final record = jsonDecode(
            row.read<String>('record_json'),
          ) as Map<String, Object?>;
          record['status'] = 'muxing';
          await db.customStatement(
            'UPDATE download_tasks SET record_json = ?',
            [jsonEncode(record)],
          );
          await db.close();
          await openRepository();
          expect(
            repository.current.tasks.single.status,
            DownloadStatus.completed,
          );
          final resolves = sources.resolveCalls;
          await repository.resume(task.id);
          await _waitFor(repository, DownloadStatus.completed);
          expect(native.calls, 1);
          expect(sources.resolveCalls, resolves);
        },
      );

      test('legacy v1 record keeps separate output and unavailable mux refuses MP4', () async {
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
      });

      test(
        'startup accepts modified merged output without original tracks',
        () async {
          await useMuxer();
          await repository.enqueue([item], mergedSelection);
          await _waitFor(repository, DownloadStatus.completed);
          await repository.close();
          final task = repository.current.tasks.single;
          await File('${task.directory}/video.m4s').writeAsBytes(media);
          await File('${task.directory}/audio.m4s').writeAsBytes(media);
          await File('${task.directory}/${output.fileName}')
              .writeAsBytes(List.filled(media.length * 2, 0));
          await db.close();
          await openRepository();
          expect(
            (await repository.offlineTask(task.id)).status,
            DownloadStatus.completed,
          );
          expect(await File('${task.directory}/video.m4s').exists(), isFalse);
          expect(await File('${task.directory}/audio.m4s').exists(), isFalse);
        },
      );

      test(
        'separate and merged versions have distinct queue identities',
        () async {
          final native = (await useMuxer())..block = true;
          await repository.enqueue([item], mergedSelection);
          await native.started.future;
          await repository.enqueue([item], const DownloadSelection());
          expect(repository.current.tasks.length, 2);
          await repository.pauseAll();
        },
      );
    });
  }
}

final class _Muxer implements DownloadMuxer {
  bool failNext = false, block = false;
  int calls = 0;
  final outputs = <DownloadOutput>[];
  final started = Completer<void>();
  @override
  bool get available => true;
  @override
  Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required DownloadOutput output,
    required RequestCancellation cancellation,
    required void Function(double) onProgress,
  }) async {
    calls++;
    outputs.add(output);
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
  Future<Set<DownloadVideoOption>> videoOptions(
    DownloadItem item, {
    required RequestCancellation cancellation,
  }) async => {(quality: 80, codec: VideoCodecPreference.h264)};
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

final class _PublicStorage implements PublicDownloadStorage {
  bool available = true, deleted = false, failPublish = false;
  String selected = 'downloads';
  final destinations = <String?>[];
  final Map<String, Map<String, String>> published = {};
  @override
  Future<bool> hasDestination() async => true;
  @override
  Future<bool> requestDirectoryAccess() async => true;
  @override
  Future<DownloadFolderListing> listDirectories(String? directory) async =>
      DownloadFolderListing(folders: const []);
  @override
  Future<void> chooseDestination(String directory) async {}
  @override
  Future<String> destination() async => selected;
  @override
  Future<Map<String, String>> publish(
    DownloadTask task,
    Map<String, String> files,
    RequestCancellation cancellation,
  ) async {
    destinations.add(task.publicDestination);
    if (failPublish) throw const AppFailure(AppFailureKind.storage, '空间不足');
    for (final source in files.values) {
      expect(await File(source).exists(), isTrue);
    }
    return published.putIfAbsent(
      task.id,
      () => {
        for (final name in files.keys) name: 'content://test/${task.id}/$name',
      },
    );
  }

  @override
  Future<void> verify(DownloadTask task) async {
    if (!available) throw const AppFailure(AppFailureKind.permission, '授权已撤销');
    expect(task.publicFiles, published[task.id]);
  }

  @override
  Future<void> delete(DownloadTask task) async {
    await verify(task);
    deleted = true;
  }
}
