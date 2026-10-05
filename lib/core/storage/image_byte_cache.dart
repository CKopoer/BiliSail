import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

typedef ImageByteLoader = Future<Uint8List> Function(
  Uri uri,
  ImageLoadRequest request,
);

/// A temporary admission failure, distinct from a failed HTTP response.
final class ImageQueueFull extends HttpException {
  const ImageQueueFull() : super('Image queue is full');
}

final class ImageLoadCancelled implements Exception {
  const ImageLoadCancelled();
  @override
  String toString() => 'Image load cancelled';
}

/// Cancellation and limits apply to public image transport, independently of
/// the API client and its account credentials.
final class ImageLoadRequest {
  ImageLoadRequest({required this.maxBytes, required this.timeout});
  final int maxBytes;
  final Duration timeout;
  bool _cancelled = false;
  void Function()? _abort;
  bool get cancelled => _cancelled;
  void onCancel(void Function() abort) {
    _abort = abort;
    if (_cancelled) abort();
  }

  void check() {
    if (_cancelled) throw const ImageLoadCancelled();
  }

  void cancel() {
    _cancelled = true;
    _abort?.call();
  }
}

/// Only public CDN requests are supported. No Cookie or Authorization is sent,
/// including redirects. Each request owns its client so abort closes sockets.
Future<Uint8List> loadPublicImage(Uri uri, ImageLoadRequest limits) async {
  final client = HttpClient()..connectionTimeout = limits.timeout;
  limits.onCancel(() => client.close(force: true));
  try {
    return await (() async {
      var target = uri;
      for (var redirect = 0; redirect <= 3; redirect++) {
        limits.check();
        final request = await client.getUrl(target);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.refererHeader,
          'https://www.bilibili.com/',
        );
        request.headers.set(HttpHeaders.acceptHeader, 'image/*');
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 3) {
            throw const HttpException('Invalid image redirect');
          }
          target = target.resolve(location);
          if (!ImageByteCache.isPublicImageUri(target)) {
            throw const HttpException('Unsupported image redirect');
          }
          // Closing this response subscription prevents downloading its body.
          await response.listen((_) {}).cancel();
          continue;
        }
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > limits.maxBytes) {
          throw const HttpException('Image response rejected');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          limits.check();
          if (bytes.length + chunk.length > limits.maxBytes) {
            throw const HttpException('Image response too large');
          }
          bytes.add(chunk);
        }
        if (bytes.isEmpty) throw const HttpException('Empty image response');
        return bytes.takeBytes();
      }
      throw const HttpException('Image redirect limit exceeded');
    })().timeout(limits.timeout);
  } on TimeoutException {
    limits.cancel();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

final class CachedImageBytes {
  const CachedImageBytes(this.bytes, {this.fromDisk = false});
  final Uint8List bytes;
  final bool fromDisk;
}

/// Account-scoped, bounded, best-effort storage. Disk failures never prevent a
/// successfully downloaded image from being displayed. Only digests and numeric
/// timestamps are written; URLs and account identifiers are never persisted.
final class ImageByteCache {
  // Public named injection points keep fake loaders and directories simple.
  ImageByteCache({
    required this.directory,
    this.loader = loadPublicImage,
    DateTime Function()? now,
    this.maxEntries = 512,
    this.maxTotalBytes = 64 * 1024 * 1024,
    this.maxImageBytes = 4 * 1024 * 1024,
    this.maxConcurrent = 6,
    this.maxPending = 64,
    this.ttl = const Duration(days: 7),
    this.timeout = const Duration(seconds: 15),
    bool enabled = true,
  }) : _now = now ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _enabled = enabled;

  final Future<Directory> Function() directory;
  final ImageByteLoader loader;
  final DateTime Function() _now;
  final int maxEntries, maxTotalBytes, maxImageBytes, maxConcurrent, maxPending;
  final Duration ttl, timeout;
  final Map<String, Future<CachedImageBytes>> _inFlight = {};
  final Set<ImageLoadRequest> _requests = {};
  final List<Completer<void>> _waiting = [];
  final _capacityChanges = StreamController<void>.broadcast();
  Future<void> _diskQueue = Future.value();
  int _active = 0;
  int _generation = 0;
  int _policyGeneration = 0;
  bool _closed = false;
  bool _initialized = false;
  bool _enabled;
  String _scope = 'guest';
  bool get enabled => _enabled;
  int get generation => _generation;
  String get scope => _scope;
  bool get hasCapacity => !_closed && _inFlight.length < maxPending;

  /// Consumers wait outside the bounded transport queue and retry only while
  /// visible. A completed request makes room even if its download failed.
  Stream<void> get capacityChanges => _capacityChanges.stream;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    ++_policyGeneration;
  }

  static bool isPublicImageUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (uri.host == 'hdslb.com' ||
          uri.host.endsWith('.hdslb.com') ||
          uri.host == 'bilibili.com' ||
          uri.host.endsWith('.bilibili.com'));

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  Future<void> changeScope(String value) async {
    if (_scope == value) return;
    final old = _scope;
    _scope = value;
    invalidateSession();
    if (old != 'guest') await clearScope(old);
  }

  void invalidateSession() {
    ++_generation;
    for (final request in _requests) {
      request.cancel();
    }
  }

  Future<void> clearScope(String scope) => _diskOperation(() async {
    final root = await directory();
    final scopeDirectory = Directory(path.join(root.path, _digest(scope)));
    if (await scopeDirectory.exists()) {
      await scopeDirectory.delete(recursive: true);
    }
  });

  Future<CachedImageBytes> load(Uri uri, {bool skipDisk = false}) {
    if (_closed || !isPublicImageUri(uri)) {
      return Future.error(const ImageLoadCancelled());
    }
    final generation = _generation;
    final scope = _scope;
    final key = '$generation:${_digest(uri.toString())}';
    final previous = _inFlight[key];
    if (previous != null) return previous;
    if (_inFlight.length >= maxPending) {
      return Future.error(const ImageQueueFull());
    }
    final policy = _policyGeneration;
    final request = ImageLoadRequest(maxBytes: maxImageBytes, timeout: timeout);
    _requests.add(request);
    late final Future<CachedImageBytes> task;
    task = _load(uri, scope, generation, policy, request, skipDisk)
        .whenComplete(() {
          _requests.remove(request);
          if (identical(_inFlight[key], task)) {
            _inFlight.remove(key);
            if (!_closed && _capacityChanges.hasListener) {
              _capacityChanges.add(null);
            }
          }
        });
    _inFlight[key] = task;
    return task;
  }

  Future<CachedImageBytes> _load(
    Uri uri,
    String scope,
    int generation,
    int policy,
    ImageLoadRequest request,
    bool skipDisk,
  ) async {
    final key = _digest(uri.toString());
    Uint8List? cached;
    if (_enabled && !skipDisk) {
      await _diskOperation(() async {
        if (!_enabled || policy != _policyGeneration) return;
        final file = await _file(scope, key);
        if (!await file.exists()) return;
        try {
          final stat = await file.stat();
          if (stat.size > maxImageBytes + 256) throw const FormatException();
          final content = await file.readAsBytes();
          final separator = content.indexOf(10);
          if (separator < 0 || separator > 255) throw const FormatException();
          final Object? decoded = jsonDecode(
            utf8.decode(content.sublist(0, separator)),
          );
          if (decoded is! Map<String, Object?>) throw const FormatException();
          final created = decoded['created'];
          final bytes = Uint8List.sublistView(content, separator + 1);
          if (created is! int ||
              bytes.isEmpty ||
              bytes.length > maxImageBytes ||
              _now().millisecondsSinceEpoch - created > ttl.inMilliseconds ||
              sha256.convert(bytes).toString() != decoded['digest']) {
            throw const FormatException();
          }
          cached = bytes;
          await file.setLastModified(_now());
        } on FormatException {
          await file.delete();
        }
      });
      request.check();
      if (generation != _generation) throw const ImageLoadCancelled();
      if (cached case final Uint8List bytes
          when _enabled && policy == _policyGeneration) {
        return CachedImageBytes(bytes, fromDisk: true);
      }
    }
    await _acquire();
    try {
      request.check();
      final bytes = await loader(uri, request).timeout(
        timeout,
        onTimeout: () {
          request.cancel();
          throw TimeoutException('Image deadline exceeded');
        },
      );
      request.check();
      if (generation != _generation) throw const ImageLoadCancelled();
      if (bytes.isEmpty || bytes.length > maxImageBytes) {
        throw const HttpException('Image response size rejected');
      }
      if (_enabled && policy == _policyGeneration) {
        await _diskOperation(() async {
          if (!_enabled ||
              policy != _policyGeneration ||
              generation != _generation) {
            return;
          }
          final file = await _file(scope, key);
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.tmp');
          final header = utf8.encode(
            '${jsonEncode({'created': _now().millisecondsSinceEpoch, 'digest': sha256.convert(bytes).toString()})}\n',
          );
          try {
            final sink = temporary.openWrite();
            try {
              sink.add(header);
              sink.add(bytes);
              await sink.flush();
            } finally {
              await sink.close();
            }
            if (!_enabled ||
                policy != _policyGeneration ||
                generation != _generation) {
              return;
            }
            if (await file.exists()) await file.delete();
            await temporary.rename(file.path);
            await file.setLastModified(_now());
            await _prune();
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
        });
      }
      request.check();
      if (generation != _generation) throw const ImageLoadCancelled();
      return CachedImageBytes(bytes);
    } finally {
      _release();
    }
  }

  Future<File> _file(String scope, String key) async =>
      File(path.join((await directory()).path, _digest(scope), '$key.img'));

  Future<void> invalidate(Uri uri) => _diskOperation(() async {
    final file = await _file(_scope, _digest(uri.toString()));
    if (await file.exists()) await file.delete();
  });

  Future<void> _prune() async {
    final root = await directory();
    final entries = <({File file, FileStat stat})>[];
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (!entity.path.endsWith('.img') ||
          _now().difference(stat.modified) > ttl) {
        await entity.delete();
        continue;
      }
      entries.add((file: entity, stat: stat));
      total += stat.size;
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var count = entries.length;
    for (final entry in entries) {
      if (count <= maxEntries && total <= maxTotalBytes) break;
      await entry.file.delete();
      total -= entry.stat.size;
      --count;
    }
  }

  Future<void> _diskOperation(Future<void> Function() action) {
    final operation = _diskQueue.then((_) async {
      try {
        if (!_initialized) {
          _initialized = true;
          final root = await directory();
          if (await root.exists()) await _prune();
        }
        await action();
      } on Exception {
        // Cache storage is optional; transport errors still propagate.
      }
    });
    _diskQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      ++_active;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      --_active;
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final request in _requests) {
      request.cancel();
    }
    await Future.wait(
      _inFlight.values.map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
    await _diskQueue;
    await _capacityChanges.close();
  }
}
