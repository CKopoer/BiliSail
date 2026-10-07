import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/data/download_file_store.dart';
import 'package:bilisail/features/downloads/domain/download_models.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
