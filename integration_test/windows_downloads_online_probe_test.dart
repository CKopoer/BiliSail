import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/data/api_download_source_repository.dart';
import 'package:bilisail/features/downloads/data/sqlite_download_repository.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

/// Explicit guest-only probe: no stored account, cookies, or account writes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows guest downloads actual Web DASH and verifies both local tracks',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'bilisail_download_guest_',
      );
      final requests = ApiRequests();
      final api = BiliApiClient(sessionProvider: requests);
      final sources = ApiDownloadSourceRepository(
        api,
        requests,
        accountScope: () => 'guest',
      );
      final database = AppDatabase(
        NativeDatabase(File(path.join(directory.path, 'client.sqlite'))),
      );
      final downloads = SqliteDownloadRepository(
        database,
        sources,
        defaultDirectory: () async => path.join(directory.path, 'offline'),
      );
      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())),
        );
        final detail = await ApiVideoRepository(api, requests).loadDetail(
          const VideoId(
            String.fromEnvironment(
              'BILI_DOWNLOAD_BVID',
              defaultValue: 'BV1GJ411x7h7',
            ),
          ),
          cancellation: RequestCancellation(),
        );
        final item = DownloadItem.fromVideo(detail).first;
        final qualities = await sources.qualities(
          item,
          cancellation: RequestCancellation(),
        );
        expect(qualities, isNotEmpty);
        final quality = qualities.reduce((a, b) => a < b ? a : b);
        await downloads.enqueue([item], DownloadSelection(quality: quality));
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (!downloads.current.tasks.any(
          (task) =>
              task.status == DownloadStatus.completed ||
              task.status == DownloadStatus.failed,
        )) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Guest download timed out');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        final task = downloads.current.tasks.single;
        expect(task.failure, isNull);
        expect(task.status, DownloadStatus.completed);
        final verified = await downloads.offlineTask(task.id);
        expect(verified.tracks, hasLength(2));
        expect(verified.tracks.every((track) => track.complete), isTrue);
        // Only non-sensitive aggregate facts are emitted from this probe.
        debugPrint(
          'DOWNLOAD_GUEST quality=$quality bytes=${verified.downloadedBytes} '
          'warnings=${verified.warnings.length}',
        );
        expect(tester.takeException(), isNull);
      } finally {
        requests.advanceSession();
        await downloads.close();
        await database.close();
        api.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('BILI_DOWNLOAD_ONLINE'),
  );
}
