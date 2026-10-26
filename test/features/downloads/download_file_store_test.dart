import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/data/download_file_store.dart';
import 'package:bilisail/features/downloads/domain/download_models.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Android app-private download boundary', () {
    late Directory sandbox;
    late Directory documents;
    late DownloadFileStore files;
    late String root;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('bilisail_boundary');
      documents = await Directory(p.join(sandbox.path, 'app_flutter')).create();
      root = p.join(documents.path, 'BiliSail', 'offline');
      files = DownloadFileStore(
        trustedDocumentsDirectory: () async => documents.path,
      );
    });
    tearDown(() => sandbox.delete(recursive: true));

    test('creates and reopens a task without migrating its files', () async {
      final directory = await files.createTaskDirectory(root, 'guest', _id);
      final task = _task(directory);
      expect(await files.ownedDirectory(task), isA<Directory>());
      await (await files.taskFile(
        task,
        'video.m4s.part',
      )).writeAsString('part');
      expect(
        await (await files.taskFile(task, 'video.m4s.part')).readAsString(),
        'part',
      );
      await files.writeExtras(task, DownloadExtras());
      expect(
        await (await files.taskFile(task, 'extras.json')).exists(),
        isTrue,
      );
      await files.deleteOwned(task);
      expect(await Directory(directory).exists(), isFalse);
    });

    test(
      'rejects a DB root outside the platform anchor before creating files',
      () async {
        final outside = p.join(sandbox.path, 'other', 'BiliSail', 'offline');
        await Directory(p.join(sandbox.path, 'other')).create();
        await expectLater(
          files.createTaskDirectory(outside, 'guest', _id),
          _failure('应用离线目录'),
        );
        expect(await Directory(outside).exists(), isFalse);
        final valid = await files.createTaskDirectory(root, 'guest', _id);
        final forged = valid.replaceFirst(
          documents.path,
          p.join(sandbox.path, 'other'),
        );
        await expectLater(
          files.ownedDirectory(_task(forged)),
          _failure('应用离线目录'),
        );
        await expectLater(files.deleteOwned(_task(forged)), _failure('应用离线目录'));
      },
    );

    test('rejects traversal and wrong layout before normalizing', () async {
      await expectLater(
        files.createTaskDirectory(p.join(root, '..', 'offline'), 'guest', _id),
        _failure('下载目录无效'),
      );
      await expectLater(
        files.createTaskDirectory(
          p.join(documents.path, 'offline'),
          'guest',
          _id,
        ),
        _failure('应用离线目录'),
      );
      final valid = await files.createTaskDirectory(root, 'guest', _id);
      await expectLater(
        files.ownedDirectory(_task(p.join(valid, '..', _id))),
        _failure('下载目录无效'),
      );
    });

    test('distinguishes a regular file from a symbolic link', () async {
      await File(p.join(documents.path, 'BiliSail')).writeAsString('keep');
      await expectLater(
        files.createTaskDirectory(root, 'guest', _id),
        _failure('非目录节点'),
      );
      expect(
        await File(p.join(documents.path, 'BiliSail')).readAsString(),
        'keep',
      );
    });

    test(
      'missing directories do not claim a symbolic link was found',
      () async {
        final directory = await files.createTaskDirectory(root, 'guest', _id);
        await Directory(directory).delete(recursive: true);
        await expectLater(
          files.ownedDirectory(_task(directory)),
          _failure('不存在或无法访问'),
        );
      },
    );

    group(
      'symbolic links',
      () {
        test(
          'allows a platform ancestor alias and legacy task spelling',
          () async {
            final alias = Link(p.join(sandbox.path, 'system_alias'));
            await alias.create(documents.path);
            final aliasRoot = p.join(alias.path, 'BiliSail', 'offline');
            await expectLater(
              const DownloadFileStore().createTaskDirectory(
                aliasRoot,
                'guest',
                _id,
              ),
              _failure('符号链接'),
            );
            final platformFiles = DownloadFileStore(
              trustedDocumentsDirectory: () async => alias.path,
            );
            final directory = await platformFiles.createTaskDirectory(
              aliasRoot,
              'guest',
              _id,
            );
            expect(
              directory,
              startsWith(await documents.resolveSymbolicLinks()),
            );
            final legacyPath = directory.replaceFirst(
              await documents.resolveSymbolicLinks(),
              alias.path,
            );
            final legacy = _task(legacyPath);
            await (await platformFiles.taskFile(
              legacy,
              'video.m4s.part',
            )).writeAsString('resume');
            // A restarted app can receive the canonical platform spelling instead.
            expect(
              await (await files.taskFile(
                legacy,
                'video.m4s.part',
              )).readAsString(),
              'resume',
            );
            await files.writeExtras(legacy, DownloadExtras());
            await files.deleteOwned(legacy);
            expect(await Directory(directory).exists(), isFalse);
            expect(await Link(alias.path).exists(), isTrue);
          },
        );

        for (final segment in ['BiliSail', 'offline', 'scope', 'task']) {
          test('rejects $segment links without touching the target', () async {
            final directory = await files.createTaskDirectory(
              root,
              'guest',
              _id,
            );
            final task = _task(directory);
            final target = await Directory(p.join(sandbox.path, 'outside'))
                .create();
            final sentinel = await File(p.join(target.path, 'keep'))
                .writeAsString('safe');
            final replaced = switch (segment) {
              'BiliSail' => p.dirname(root),
              'offline' => root,
              'scope' => p.dirname(directory),
              _ => directory,
            };
            await Directory(replaced).delete(recursive: true);
            await Link(replaced).create(target.path);
            await expectLater(
              files.createTaskDirectory(root, 'guest', _id),
              _failure('符号链接'),
            );
            await expectLater(files.ownedDirectory(task), _failure('符号链接'));
            await expectLater(files.deleteOwned(task), _failure('符号链接'));
            expect(await sentinel.readAsString(), 'safe');
            expect(await target.list().length, 1);
          });
        }

        for (final name in [
          'video.m4s',
          'video.m4s.part',
          'media.mp4',
          'media.mkv.part',
          'extras.json.tmp',
          '.bilisail-task',
        ]) {
          test(
            'rejects $name links for access and recursive deletion',
            () async {
              final directory = await files.createTaskDirectory(
                root,
                'guest',
                _id,
              );
              final task = _task(directory);
              final target = await File(p.join(sandbox.path, 'outside'))
                  .writeAsString('safe');
              final child = File(p.join(directory, name));
              if (await child.exists()) await child.delete();
              await Link(child.path).create(target.path);
              if (name == '.bilisail-task') {
                await expectLater(files.ownedDirectory(task), _failure('归属标记'));
              } else if (name.endsWith('.tmp')) {
                await expectLater(
                  files.writeExtras(task, DownloadExtras()),
                  _failure('符号链接'),
                );
              } else {
                await expectLater(files.taskFile(task, name), _failure('符号链接'));
              }
              await expectLater(
                files.deleteOwned(task),
                throwsA(isA<AppFailure>()),
              );
              expect(await target.readAsString(), 'safe');
            },
          );
        }

        test('rejects dangling links before directory creation', () async {
          await Link(p.join(documents.path, 'BiliSail'))
              .create(p.join(sandbox.path, 'missing'));
          await expectLater(
            files.createTaskDirectory(root, 'guest', _id),
            _failure('符号链接'),
          );
          expect(
            await Directory(p.join(sandbox.path, 'missing')).exists(),
            isFalse,
          );
        });
      },
      skip: Platform.isWindows
          ? 'Creating Windows symlinks requires additional privileges.'
          : false,
    );
  });

  test('extras writer matches offline reader counts and size limit', () async {
    final root = await Directory.systemTemp.createTemp('bilisail_extras');
    addTearDown(() => root.delete(recursive: true));
    const files = DownloadFileStore();
    const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final directory = await files.createTaskDirectory(root.path, 'guest', id);
    final now = DateTime.now();
    final task = DownloadTask(
      id: id,
      scope: 'guest',
      item: DownloadItem(
        video: const VideoSummary(
          id: VideoId('BV1234567890'),
          title: 'Fixture',
          coverUrl: '',
          author: 'Author',
          duration: Duration(seconds: 1),
        ),
        part: const VideoPart(
          cid: '1',
          page: 1,
          title: 'P1',
          duration: Duration(seconds: 1),
        ),
      ),
      selection: const DownloadSelection(),
      status: DownloadStatus.paused,
      directory: directory,
      createdAt: now,
      updatedAt: now,
    );
    final comment = TimedComment(
      id: '1',
      position: Duration.zero,
      text: 'text',
      mode: 1,
      color: 1,
      fontSize: 25,
    );
    final extras = DownloadExtras(
      comments: List.filled(60001, comment),
      subtitles: List.generate(
        17,
        (index) => DownloadedSubtitle(label: '$index', cues: const []),
      ),
      cover: Uint8List(4 * 1024 * 1024 + 1),
    );
    await files.writeExtras(task, extras);
    final file = File('$directory/extras.json');
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect((decoded['comments'] as List).length, 60000);
    expect((decoded['subtitles'] as List).length, 16);
    expect(await File('$directory/cover.img').exists(), isFalse);
    final previous = await file.length();
    await expectLater(
      files.writeExtras(
        task,
        DownloadExtras(warnings: ['x' * (33 * 1024 * 1024)]),
      ),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', AppFailureKind.storage),
      ),
    );
    expect(await file.length(), previous);
  });
}

const _id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Matcher _failure(String message) => throwsA(
  isA<AppFailure>().having((e) => e.message, 'message', contains(message)),
);

DownloadTask _task(String directory) => DownloadTask(
  id: _id,
  scope: 'guest',
  item: DownloadItem(
    video: const VideoSummary(
      id: VideoId('BV1234567890'),
      title: 'Fixture',
      coverUrl: '',
      author: 'Author',
      duration: Duration(seconds: 1),
    ),
    part: const VideoPart(
      cid: '1',
      page: 1,
      title: 'P1',
      duration: Duration(seconds: 1),
    ),
  ),
  selection: const DownloadSelection(),
  status: DownloadStatus.paused,
  directory: directory,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
