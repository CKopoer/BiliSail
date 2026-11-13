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

  test(
    'album comment thumbnails load and reuse the public image cache',
    () async {
      final source = Uri.parse(
        'https://album.biliimg.com/bfs/new_dyn/fixture.jpg@264w_1280h_0e.webp',
      );
      final loaded = <Uri>[];
      final cache = ImageByteCache(
        directory: () async => directory,
        loader: (uri, _) async {
          loaded.add(uri);
          return bytes;
        },
      );
      addTearDown(cache.close);
      expect((await cache.load(source)).bytes, bytes);
      expect((await cache.load(source)).bytes, bytes);
      expect(loaded, [source]);
      for (final host in [
        'album.biliimg.com.example.com',
        'other.album.biliimg.com',
        'other.biliimg.com',
        'biliimg.com',
      ]) {
        await expectLater(
          cache.load(source.replace(host: host)),
          throwsA(isA<ImageLoadCancelled>()),
        );
      }
      expect(loaded, [source]);
    },
  );

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
      await cache.flushWrites();
      await cache.load(url);
      await cache.flushWrites();
      expect(opens, 0);
      expect(calls, 2);
      cache.enabled = true;
      await cache.load(url);
      await cache.flushWrites();
      expect(await files(), hasLength(1));
      cache.enabled = false;
      final before = opens;
      await cache.load(url);
      await cache.flushWrites();
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
    await cache.flushWrites();
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(urls[1]);
    await cache.flushWrites();
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(urls[0]);
    await cache.flushWrites();
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(urls[2]);
    await cache.flushWrites();
    final stored = await files();
    expect(stored.length, lessThanOrEqualTo(2));
    expect(
      stored.fold<int>(0, (size, file) => size + file.lengthSync()),
      lessThanOrEqualTo(380),
    );
    expect((await cache.load(urls[0])).fromDisk, isTrue);
    expect((await cache.load(urls[1])).fromDisk, isFalse);
    await cache.flushWrites();
    clock = clock.add(const Duration(hours: 2));
    expect((await cache.load(urls[1])).fromDisk, isFalse);
    await cache.flushWrites();
    for (final file in await files()) {
      await file.writeAsBytes([1, 2, 3]);
    }
    expect((await cache.load(urls[1])).fromDisk, isFalse);
    await cache.flushWrites();
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
      await cache.flushWrites();
      expect(await files(), hasLength(1));
      final late = cache.load(Uri.parse('https://i0.hdslb.com/late.jpg'));
      final failure = expectLater(late, throwsA(isA<ImageLoadCancelled>()));
      await Future<void>.delayed(Duration.zero);
      await cache.changeScope('guest');
      response.complete(bytes);
      await failure;
      expect(await files(), isEmpty);
      expect((await cache.load(url)).fromDisk, isFalse);
      await cache.flushWrites();
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

  test('blocked writes release all six transport slots and have count and byte budgets', () async {
    for (final limits in [(2, 1024), (16, 128)]) {
      final gate = Completer<void>();
      var calls = 0;
      final cache = ImageByteCache(
        directory: () async {
          await gate.future;
          return directory;
        },
        maxPendingWrites: limits.$1,
        maxPendingWriteBytes: limits.$2,
        loader: (_, _) async {
          ++calls;
          return bytes;
        },
      );
      final loads = List.generate(
        7,
        (index) => cache.load(
          Uri.parse('https://i0.hdslb.com/budget-${limits.$1}-$index.jpg'),
          skipDisk: true,
        ),
      );
      final results = await Future.wait(loads);
      expect(results, hasLength(7));
      expect(calls, 7);
      expect(cache.pendingWrites, 2);
      expect(cache.pendingWriteBytes, 128);
      var closed = false;
      final closing = cache.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      gate.complete();
      await closing;
      expect(cache.pendingWrites, 0);
      expect(cache.pendingWriteBytes, 0);
    }
    expect(await files(), hasLength(4));
  });

  test(
    'startup scans once and writes maintain the LRU quota incrementally',
    () async {
      for (var i = 0; i < 512; i++) {
        await File('${directory.path}/seed-$i.img').writeAsBytes([1]);
      }
      final counted = _CountingDirectory(directory);
      final cache = ImageByteCache(
        directory: () async => counted,
        loader: (_, _) async => bytes,
      );
      for (var i = 0; i < 20; i++) {
        await cache.load(Uri.parse('https://i0.hdslb.com/scan-$i.jpg'));
        await cache.flushWrites();
      }
      await cache.close();
      expect(counted.scans, 1);
      expect(counted.files, 512);
      expect(await files(), hasLength(512));
    },
  );

  test(
    'disable or clear while persistence is blocked prevents late writes',
    () async {
      for (final clear in [false, true]) {
        final gate = Completer<void>();
        final cache = ImageByteCache(
          directory: () async {
            await gate.future;
            return directory;
          },
          loader: (_, _) async => bytes,
        );
        await cache.load(url, skipDisk: true);
        final cleanup = clear ? cache.clearScope('guest') : null;
        if (!clear) cache.enabled = false;
        gate.complete();
        await cleanup;
        await cache.close();
        expect(await files(), isEmpty);
      }
    },
  );

  test(
    'shared consumers cancel only after the final lease is released',
    () async {
      var calls = 0;
      var aborts = 0;
      final gate = Completer<Uint8List>();
      final cache = ImageByteCache(
        directory: () async => directory,
        enabled: false,
        maxConcurrent: 1,
        loader: (_, request) {
          calls++;
          request.onCancel(() => aborts++);
          return gate.future;
        },
      );
      final first = cache.acquire(url);
      final second = cache.acquire(url);
      await Future<void>.delayed(Duration.zero);
      first.release();
      expect(aborts, 0);
      gate.complete(bytes);
      expect((await second.result).bytes, bytes);
      second.release();
      expect(calls, 1);
      expect(aborts, 0);
      await cache.close();
    },
  );

  test(
    'zero-consumer queued tasks are removed without consuming a network slot',
    () async {
      final gates = <Completer<Uint8List>>[];
      final cache = ImageByteCache(
        directory: () async => directory,
        enabled: false,
        maxConcurrent: 1,
        maxPending: 2,
        loader: (_, _) {
          final gate = Completer<Uint8List>();
          gates.add(gate);
          return gate.future;
        },
      );
      final active = cache.acquire(url);
      final queued = cache.acquire(
        Uri.parse('https://i0.hdslb.com/queued.jpg'),
      );
      final cancelled = expectLater(
        queued.result,
        throwsA(isA<ImageLoadCancelled>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cache.hasCapacity, isFalse);
      queued.release();
      expect(cache.hasCapacity, isTrue);
      await cancelled;
      final replacement = cache.acquire(
        Uri.parse('https://i0.hdslb.com/replacement.jpg'),
      );
      gates.single.complete(bytes);
      await active.result;
      await Future<void>.delayed(Duration.zero);
      expect(gates, hasLength(2));
      gates.last.complete(bytes);
      await replacement.result;
      active.release();
      replacement.release();
      await cache.close();
    },
  );

  test('active cancellation releases the slot and a late response cannot replace the new task', () async {
    final gates = <Completer<Uint8List>>[];
    var aborts = 0;
    final cache = ImageByteCache(
      directory: () async => directory,
      enabled: false,
      maxConcurrent: 1,
      loader: (_, request) {
        request.onCancel(() => aborts++);
        final gate = Completer<Uint8List>();
        gates.add(gate);
        return gate.future;
      },
    );
    final old = cache.acquire(url);
    final failure = expectLater(old.result, throwsA(isA<ImageLoadCancelled>()));
    await Future<void>.delayed(Duration.zero);
    old.release();
    await failure;
    final current = cache.acquire(url);
    await Future<void>.delayed(Duration.zero);
    expect(aborts, 1);
    expect(gates, hasLength(2));
    gates.first.complete(Uint8List.fromList([1]));
    gates.last.complete(bytes);
    expect((await current.result).bytes, bytes);
    current.release();
    await cache.close();
  });

  test(
    'visible consumers promote a shared prefetch task ahead of older prefetch',
    () async {
      final gates = <Completer<Uint8List>>[];
      final paths = <String>[];
      final cache = ImageByteCache(
        directory: () async => directory,
        enabled: false,
        maxConcurrent: 1,
        loader: (uri, _) {
          paths.add(uri.path);
          final gate = Completer<Uint8List>();
          gates.add(gate);
          return gate.future;
        },
      );
      final blocker = cache.acquire(url);
      final older = cache.acquire(
        Uri.parse('https://i0.hdslb.com/older.jpg'),
        priority: ImageLoadPriority.prefetch,
      );
      final newer = cache.acquire(
        Uri.parse('https://i0.hdslb.com/newer.jpg'),
        priority: ImageLoadPriority.prefetch,
      );
      await Future<void>.delayed(Duration.zero);
      newer.setPriority(ImageLoadPriority.visible);
      gates.first.complete(bytes);
      await blocker.result;
      await Future<void>.delayed(Duration.zero);
      expect(paths.last, '/newer.jpg');
      gates.last.complete(bytes);
      await newer.result;
      await Future<void>.delayed(Duration.zero);
      expect(paths.last, '/older.jpg');
      gates.last.complete(bytes);
      await older.result;
      for (final lease in [blocker, older, newer]) {
        lease.release();
      }
      await cache.close();
    },
  );

  test('disk hits do not wait for an unrelated optional write', () async {
    Completer<void>? blockNextDirectory;
    final entered = Completer<void>();
    final cache = ImageByteCache(
      directory: () async {
        final gate = blockNextDirectory;
        if (gate != null) {
          blockNextDirectory = null;
          entered.complete();
          await gate.future;
        }
        return directory;
      },
      loader: (_, _) async => bytes,
    );
    await cache.load(url);
    await cache.flushWrites();
    final gate = Completer<void>();
    blockNextDirectory = gate;
    await cache.load(
      Uri.parse('https://i0.hdslb.com/unrelated.jpg'),
      skipDisk: true,
    );
    await entered.future;
    expect(
      (await cache.load(url).timeout(const Duration(seconds: 2))).fromDisk,
      isTrue,
    );
    gate.complete();
    await cache.close();
  });

  test('same-URL reads use bounded pending bytes until atomic replacement finishes', () async {
    Completer<void>? blockWrite;
    final entered = Completer<void>();
    var response = bytes;
    var calls = 0;
    var clock = DateTime.utc(2026);
    final cache = ImageByteCache(
      directory: () async => directory,
      fileForPath: (path) {
        final gate = blockWrite;
        return _ControlledFile(
          File(path),
          beforeCreate: gate == null
              ? null
              : () async {
                  entered.complete();
                  await gate.future;
                },
        );
      },
      maxTotalBytes: 500,
      now: () => clock,
      loader: (_, _) async {
        calls++;
        return response;
      },
    );
    await cache.load(url);
    await cache.flushWrites();
    response = Uint8List.fromList(List.filled(240, 31));
    clock = clock.add(const Duration(seconds: 1));
    final gate = Completer<void>();
    blockWrite = gate;
    await cache.load(url, skipDisk: true);
    await entered.future;
    blockWrite = null;
    // This is the storyboard dimensions -> thumbnail path: bytes have been
    // delivered, but the optional replacement has not reached the filesystem.
    expect((await cache.load(url)).bytes, response);
    expect(calls, 2);
    expect(cache.pendingWrites, 1);
    expect(cache.pendingWriteBytes, response.length);
    gate.complete();
    await cache.flushWrites();
    response = bytes;
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(Uri.parse('https://i0.hdslb.com/second.jpg'));
    await cache.close();
    final stored = await files();
    expect(
      stored.fold<int>(0, (sum, file) => sum + file.lengthSync()),
      lessThanOrEqualTo(500),
    );
    expect(stored, hasLength(1));
  });

  test('a reader finishing after eviction cannot reinsert a deleted LRU entry', () async {
    Completer<void>? blockRead;
    final entered = Completer<void>();
    var clock = DateTime.utc(2026);
    final cache = ImageByteCache(
      directory: () async => directory,
      fileForPath: (path) {
        final gate = blockRead;
        return _ControlledFile(
          File(path),
          afterReadTouch: gate == null
              ? null
              : () async {
                  entered.complete();
                  await gate.future;
                },
        );
      },
      maxEntries: 2,
      now: () => clock,
      loader: (_, _) async => bytes,
    );
    await cache.load(url);
    await cache.flushWrites();
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(Uri.parse('https://i0.hdslb.com/second.jpg'));
    await cache.flushWrites();
    final gate = Completer<void>();
    blockRead = gate;
    final reading = cache.load(url);
    await entered.future;
    blockRead = null;
    clock = clock.add(const Duration(seconds: 1));
    final third = Uri.parse('https://i0.hdslb.com/third.jpg');
    await cache.load(third);
    await cache.flushWrites();
    clock = clock.add(const Duration(seconds: 1));
    gate.complete();
    await reading;
    // A resurrected, recently touched ghost would cause both older real files
    // to be evicted for the fourth write, leaving only one file for two slots.
    clock = clock.add(const Duration(seconds: 1));
    await cache.load(Uri.parse('https://i0.hdslb.com/fourth.jpg'));
    await cache.flushWrites();
    expect((await cache.load(third)).fromDisk, isTrue);
    expect(await files(), hasLength(2));
    await cache.close();
  });
}

final class _CountingDirectory implements Directory {
  _CountingDirectory(this.inner);
  final Directory inner;
  int scans = 0;
  int files = 0;
  @override
  String get path => inner.path;
  @override
  Future<bool> exists() => inner.exists();
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    scans++;
    return inner.list(recursive: recursive, followLinks: followLinks).map((
      entity,
    ) {
      if (entity is File) files++;
      return entity;
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ControlledFile implements File {
  _ControlledFile(this.inner, {this.beforeCreate, this.afterReadTouch});
  final File inner;
  final Future<void> Function()? beforeCreate;
  final Future<void> Function()? afterReadTouch;
  bool read = false;
  @override
  String get path => inner.path;
  @override
  Directory get parent => _ControlledParent(inner.parent, beforeCreate);
  @override
  Future<FileStat> stat() => inner.stat();
  @override
  Future<bool> exists() => inner.exists();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      inner.delete(recursive: recursive);
  @override
  Future<Uint8List> readAsBytes() {
    read = true;
    return inner.readAsBytes();
  }

  @override
  Future<void> setLastModified(DateTime time) async {
    await inner.setLastModified(time);
    if (read) await afterReadTouch?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ControlledParent implements Directory {
  _ControlledParent(this.inner, this.beforeCreate);
  final Directory inner;
  final Future<void> Function()? beforeCreate;
  @override
  Future<Directory> create({bool recursive = false}) async {
    await beforeCreate?.call();
    return inner.create(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
