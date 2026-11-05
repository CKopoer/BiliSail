import 'dart:io';

import 'package:bilisail/core/platform/log_archive_storage.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('log_save_');
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      LogArchiveStorage.channel,
      null,
    );
    await directory.delete(recursive: true);
  });
  final bytes = Uint8List.fromList([80, 75, 3, 4]);
  const name = 'BiliSail-logs-20261106-1.zip';

  test(
    'default export location is adjacent to the platform offline directory',
    () async {
      final downloads = p.join(directory.path, 'BiliSail', 'offline');
      final storage = LogArchiveStorage(
        android: false,
        defaultDownloadDirectory: () async => downloads,
      );
      final saved = await storage.save(bytes, name);
      expect(saved, p.join(directory.path, 'BiliSail', 'exported_logs', name));
      expect(await File(saved).readAsBytes(), bytes);
      expect(await File('$saved.partial').exists(), isFalse);
    },
  );

  test(
    'Android delegates ZIP publishing to the public Downloads channel',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LogArchiveStorage.channel,
        (call) async {
          expect(call.method, 'save');
          expect(call.arguments, {'bytes': bytes, 'name': name});
          return 'Download/BiliSail/logs/$name';
        },
      );
      final saved = await const LogArchiveStorage(android: true)
          .save(bytes, name);
      expect(saved, 'Download/BiliSail/logs/$name');
    },
  );

  test(
    'Android denial and missing saved location cannot report success',
    () async {
      final storage = const LogArchiveStorage(android: true);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LogArchiveStorage.channel,
        (_) async {
          throw PlatformException(code: 'permission_denied');
        },
      );
      await expectLater(
        storage.save(bytes, name),
        throwsA(isA<PlatformException>()),
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LogArchiveStorage.channel,
        (_) async => null,
      );
      await expectLater(storage.save(bytes, name), throwsA(isA<AppFailure>()));
    },
  );

  test('rejects path traversal before invoking storage', () async {
    var called = false;
    final storage = LogArchiveStorage(
      android: false,
      defaultDownloadDirectory: () async {
        called = true;
        return directory.path;
      },
    );
    await expectLater(
      storage.save(bytes, '../secret.zip'),
      throwsA(isA<AppFailure>()),
    );
    expect(called, isFalse);
  });
}
