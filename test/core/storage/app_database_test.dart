import 'dart:io';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/library/data/sqlite_library_repository.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v1 migration retains video history and stores PGC episode routes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bilisail_migration_test',
      );
      final file = File('${directory.path}/client.sqlite');
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            sqlite.execute(
              'CREATE TABLE settings(key TEXT NOT NULL PRIMARY KEY,value TEXT NOT NULL)',
            );
            sqlite.execute(
              'INSERT INTO settings VALUES (\'migration-probe\',\'keep\')',
            );
            sqlite.execute('''CREATE TABLE playback_progress (
        scope TEXT NOT NULL,bvid TEXT NOT NULL,cid TEXT NOT NULL,title TEXT NOT NULL,
        cover_url TEXT NOT NULL,author TEXT NOT NULL,duration_ms INTEGER NOT NULL,
        part_title TEXT NOT NULL,part_number INTEGER NOT NULL,position_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,PRIMARY KEY(scope,bvid,cid))''');
            sqlite.execute(
              'CREATE INDEX progress_scope_time ON playback_progress(scope,updated_at_ms DESC)',
            );
            sqlite.execute(
              '''INSERT INTO playback_progress VALUES
        ('guest','BV1234567890','1','Old video','','Author',120000,'Part 1',1,32000,1)''',
            );
            sqlite.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      expect(await database.readSetting('migration-probe'), 'keep');
      final library = SqliteLibraryRepository(
        database,
        accountScope: () => 'guest',
      );
      final old = await library.loadHistory(
        cancellation: RequestCancellation(),
      );
      expect(old.single.position, const Duration(seconds: 32));
      expect(old.single.episodeId, isNull);
      expect(old.single.location.toString(), '/video/BV1234567890?cid=1');
      await library.saveProgress(
        scope: 'guest',
        video: video,
        part: part,
        position: const Duration(seconds: 44),
        duration: part.duration,
        episodeId: '123',
      );
      final pgc = await library.loadHistory(
        cancellation: RequestCancellation(),
      );
      expect(pgc.single.location.toString(), '/pgc/episode/123');
      expect(
        await library.resumePosition('guest', video.id, part.cid),
        const Duration(seconds: 44),
      );
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        2,
      );
    },
  );
  test(
    'schema initializes and reopening retains settings and progress',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bilisail_storage_test',
      );
      final file = File('${directory.path}/client.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      final settings = SqliteSettingsRepository(database);
      expect((await settings.load()).theme, AppThemePreference.system);
      await settings.save(
        AppSettings(theme: AppThemePreference.dark, danmakuEnabled: false),
      );
      final history = SqliteLibraryRepository(
        database,
        accountScope: () => 'guest',
      );
      await history.saveProgress(
        scope: 'guest',
        video: video,
        part: part,
        position: const Duration(seconds: 32),
        duration: part.duration,
      );
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      expect(
        (await SqliteSettingsRepository(database).load()).theme,
        AppThemePreference.dark,
      );
      final reopened = SqliteLibraryRepository(
        database,
        accountScope: () => 'guest',
      );
      expect(
        await reopened.resumePosition('guest', video.id, part.cid),
        const Duration(seconds: 32),
      );
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        2,
      );
      await database.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'history isolates accounts and records intentional backward seeks',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      var scope = 'user:1';
      final history = SqliteLibraryRepository(
        database,
        accountScope: () => scope,
      );
      await history.saveProgress(
        scope: scope,
        video: video,
        part: part,
        position: const Duration(seconds: 75),
        duration: part.duration,
      );
      await history.saveProgress(
        scope: scope,
        video: video,
        part: part,
        position: const Duration(seconds: 12),
        duration: part.duration,
      );
      expect(
        await history.resumePosition(scope, video.id, part.cid),
        const Duration(seconds: 12),
      );
      scope = 'user:2';
      await history.saveProgress(
        scope: 'user:1',
        video: video,
        part: part,
        position: const Duration(seconds: 45),
        duration: part.duration,
      );
      expect(
        await history.loadHistory(cancellation: RequestCancellation()),
        isEmpty,
      );
      expect(
        await history.resumePosition('user:1', video.id, part.cid),
        const Duration(seconds: 12),
      );
      await database.clearPrivateHistory('user:1');
      expect(
        await history.resumePosition('user:1', video.id, part.cid),
        Duration.zero,
      );
      await database.close();
    },
  );
}

const video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: 'Fixture video',
  coverUrl: '',
  author: 'Fixture author',
  duration: Duration(seconds: 120),
);
const part = VideoPart(
  cid: '1',
  page: 1,
  title: 'Part 1',
  duration: Duration(seconds: 120),
);
