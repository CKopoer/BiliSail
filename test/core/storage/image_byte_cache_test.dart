import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('bili_images_'),
  );
  tearDown(() async => directory.delete(recursive: true));
  final url = Uri.parse(
    'https://i0.hdslb.com/cover.jpg?signature=private-query',
  );
  final bytes = Uint8List.fromList(List.filled(64, 42));
  Future<List<File>> files() async => directory
      .list(recursive: true)
      .where((file) => file is File && file.path.endsWith('.img'))
      .cast<File>()
      .toList();

  test('same URL is single-flight and reused after cache restart without leaking URLs', () async {
    var calls = 0;
    final response = Completer<Uint8List>();
    final started = Completer<void>();
    final cache = ImageByteCache(
      directory: () async => directory,
      loader: (_, _) {
        ++calls;
        started.complete();
        return response.future;
      },
    );
    final first = cache.load(url);
    final second = cache.load(url);
    await started.future;
    expect(calls, 1);
    response.complete(bytes);
    expect((await first).bytes, bytes);
    expect((await second).bytes, bytes);
    await cache.close();
    final stored = await files();
    expect(stored, hasLength(1));
    expect(stored.single.path, isNot(contains('cover')));
    expect(
      String.fromCharCodes(await stored.single.readAsBytes()),
      isNot(contains('private-query')),
    );
    final restarted = ImageByteCache(
      directory: () async => directory,
      loader: (_, _) async {
        ++calls;
        return bytes;
      },
    );
    expect((await restarted.load(url)).fromDisk, isTrue);
    expect(calls, 1);
    await restarted.close();
  });

  test(
    'disabled cache never opens its directory and does not write late response',
    () async {
      var opens = 0;
      var calls = 0;
      final cache = ImageByteCache(
        enabled: false,
        directory: () async {
          ++opens;
          return directory;
        },
        loader: (_, _) async {
          ++calls;
          return bytes;
        },
      );
      await cache.load(url);
      await cache.load(url);
      expect(opens, 0);
      expect(calls, 2);
      cache.enabled = true;
      await cache.load(url);
      expect(await files(), hasLength(1));
      cache.enabled = false;
      final before = opens;
      await cache.load(url);
      expect(opens, before);
      expect(calls, 4);
      await cache.close();
      final response = Completer<Uint8List>();
      final pending = ImageByteCache(
        directory: () async => directory,
        loader: (_, _) => response.future,
      );
      final load = pending.load(Uri.parse('https://i0.hdslb.com/late.jpg'));
      await Future<void>.delayed(Duration.zero);
      pending.enabled = false;
      response.complete(bytes);
      await load;
      expect(await files(), hasLength(1));
      await pending.close();
    },
  );

  test('LRU count and total bytes are bounded; expired and corrupt entries redownload', () async {
    var clock = DateTime.utc(2026);
    var calls = 0;
    final cache = ImageByteCache(
      directory: () async => directory,
      maxEntries: 2,
      maxTotalBytes: 380,
      ttl: const Duration(hours: 1),
      now: () => clock,
      loader: (_, _) async {
        ++calls;
        return bytes;
      },
    );
    final urls = List.generate(
      3,
      (i) => Uri.parse('https://i0.hdslb.com/$i.jpg'),
    );
    await cache.load(urls[0]);
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(urls[1]);
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(urls[0]);
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(urls[2]);
    final stored = await files();
    expect(stored.length, lessThanOrEqualTo(2));
    expect(
      stored.fold<int>(0, (size, file) => size + file.lengthSync()),
      lessThanOrEqualTo(380),
    );
    expect((await cache.load(urls[0])).fromDisk, isTrue);
    expect((await cache.load(urls[1])).fromDisk, isFalse);
    clock = clock.add(const Duration(hours: 2));
    expect((await cache.load(urls[1])).fromDisk, isFalse);
    for (final file in await files()) {
      await file.writeAsBytes([1, 2, 3]);
    }
    expect((await cache.load(urls[1])).fromDisk, isFalse);
    expect(calls, 6);
    expect(
      await directory
          .list(recursive: true)
          .where((file) => file.path.endsWith('.tmp'))
          .toList(),
      isEmpty,
    );
    await cache.close();
  });

  test('storage failure still returns network bytes and oversized image is rejected', () async {
    final cache = ImageByteCache(
      directory: () async => throw const FileSystemException('denied'),
      loader: (_, _) async => bytes,
    );
    expect((await cache.load(url)).bytes, bytes);
    await cache.close();
    final oversized = ImageByteCache(
      directory: () async => directory,
      maxImageBytes: 4,
      loader: (_, _) async => bytes,
    );
    await expectLater(oversized.load(url), throwsA(isA<HttpException>()));
    expect(await files(), isEmpty);
    await oversized.close();
  });

  test(
    'scope switch cancels old response and clears old private cache',
    () async {
      final response = Completer<Uint8List>();
      var calls = 0;
      final cache = ImageByteCache(
        directory: () async => directory,
        loader: (_, _) {
          ++calls;
          return calls == 2 ? response.future : Future.value(bytes);
        },
      );
      await cache.changeScope('user:123');
      await cache.load(url);
      expect(await files(), hasLength(1));
      final late = cache.load(Uri.parse('https://i0.hdslb.com/late.jpg'));
      final failure = expectLater(late, throwsA(isA<ImageLoadCancelled>()));
      await Future<void>.delayed(Duration.zero);
      await cache.changeScope('guest');
      response.complete(bytes);
      await failure;
      expect(await files(), isEmpty);
      expect((await cache.load(url)).fromDisk, isFalse);
      expect(await files(), hasLength(1));
      await cache.close();
    },
  );

  test('pending queue and active downloads are bounded and deadlines release slots', () async {
    var active = 0;
    var maximum = 0;
    final responses = <Completer<Uint8List>>[];
    final cache = ImageByteCache(
      directory: () async => directory,
      enabled: false,
      maxConcurrent: 2,
      maxPending: 3,
      loader: (_, _) async {
        ++active;
        if (active > maximum) maximum = active;
        final response = Completer<Uint8List>();
        responses.add(response);
        final result = await response.future;
        --active;
        return result;
      },
    );
    final loads = List.generate(
      3,
      (i) => cache.load(Uri.parse('https://i0.hdslb.com/$i')),
    );
    await expectLater(cache.load(url), throwsA(isA<HttpException>()));
    await Future<void>.delayed(Duration.zero);
    expect(responses, hasLength(2));
    responses[0].complete(bytes);
    await loads[0];
    await Future<void>.delayed(Duration.zero);
    expect(responses, hasLength(3));
    responses[1].complete(bytes);
    responses[2].complete(bytes);
    await Future.wait(loads);
    expect(maximum, 2);
    await cache.close();
    var cancelled = false;
    final deadline = ImageByteCache(
      directory: () async => directory,
      timeout: const Duration(milliseconds: 10),
      loader: (_, request) {
        request.onCancel(() => cancelled = true);
        return Completer<Uint8List>().future;
      },
    );
    await expectLater(deadline.load(url), throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    await deadline.close();
  });
}
