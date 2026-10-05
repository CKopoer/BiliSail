import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small, explicit SQL schema. No credentials or signed media URLs belong here.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return AppDatabase(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'bilisail.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await customStatement('''CREATE TABLE settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      )''');
      await customStatement('''CREATE TABLE playback_progress (
        scope TEXT NOT NULL,
        bvid TEXT NOT NULL,
        cid TEXT NOT NULL,
        title TEXT NOT NULL,
        cover_url TEXT NOT NULL,
        author TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        part_title TEXT NOT NULL,
        part_number INTEGER NOT NULL,
        position_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        pgc_episode_id TEXT,
        PRIMARY KEY (scope, bvid, cid)
      )''');
      await customStatement(
        'CREATE INDEX progress_scope_time ON playback_progress(scope, updated_at_ms DESC)',
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from == 1 && to == 2) {
        await customStatement(
          'ALTER TABLE playback_progress ADD COLUMN pgc_episode_id TEXT',
        );
        return;
      }
      throw StateError('Unsupported database migration $from → $to');
    },
  );

  Future<String?> readSetting(String key) async {
    final row = await customSelect(
      'SELECT value FROM settings WHERE key = ?',
      variables: [Variable<String>(key)],
    ).getSingleOrNull();
    return row?.read<String>('value');
  }

  Future<void> writeSetting(String key, String value) => customStatement(
    'INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  Future<void> clearPrivateHistory(String scope) =>
      customStatement('DELETE FROM playback_progress WHERE scope = ?', [scope]);
}
