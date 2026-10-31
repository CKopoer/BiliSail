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

final class ImageResponseTooLarge extends HttpException {
  const ImageResponseTooLarge() : super('Image response too large');
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
    if (_cancelled) return;
    _cancelled = true;
    _abort?.call();
  }
}

/// One-shot transport for consumers without a longer-lived image service.
Future<Uint8List> loadPublicImage(Uri uri, ImageLoadRequest limits) async {
  final transport = PublicImageTransport(maxConnections: 1);
  try {
    return await transport.load(uri, limits);
  } finally {
    transport.close();
  }
}

/// A bounded pool of public-only connections. Each client is exclusively leased
/// to one transfer, so cancellation can also abort a pending DNS/TLS handshake
/// without closing any other image's sockets. Successful same-origin transfers
/// return the client for keep-alive reuse; failures and cross-origin redirects
/// retire it. No credentials or authentication callbacks are ever installed.
final class PublicImageTransport {
  PublicImageTransport({this.maxConnections = 6}) {
    if (maxConnections < 1) {
      throw ArgumentError.value(
        maxConnections,
        'maxConnections',
        'Must be positive',
      );
    }
  }
  final int maxConnections;
  final _idle = <(Uri, HttpClient)>[];
  final _active = <HttpClient>{};
  bool _closed = false;

  Future<Uint8List> load(Uri uri, ImageLoadRequest limits) async {
    limits.check();
    if (_closed) throw const ImageLoadCancelled();
    if (!ImageByteCache.isPublicImageUri(uri)) {
      throw const HttpException('Unsupported image URL');
    }
    if (_active.length >= maxConnections) throw const ImageQueueFull();
    final origin = uri.replace(path: '', query: '', fragment: '');
    final matching = _idle.indexWhere((entry) => entry.$1 == origin);
    final HttpClient client;
    if (matching >= 0) {
      client = _idle.removeAt(matching).$2;
    } else {
      if (_active.length + _idle.length >= maxConnections) {
        _idle.removeAt(0).$2.close(force: true);
      }
      client = HttpClient()
        ..maxConnectionsPerHost = 1
        ..idleTimeout = const Duration(seconds: 15);
    }
    client.connectionTimeout = limits.timeout;
    _active.add(client);
    void retire() {
      if (_active.remove(client)) client.close(force: true);
    }

    limits.onCancel(retire);
    var successful = false;
    var sameOrigin = true;
    try {
      final bytes = await (() async {
        var target = uri;
        for (var redirect = 0; redirect <= 3; redirect++) {
          limits.check();
          final request = await client.getUrl(target);
          limits.check();
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
            if (target.replace(path: '', query: '', fragment: '') != origin) {
              sameOrigin = false;
            }
            // Closing this response subscription prevents downloading its body.
            await response.listen((_) {}).cancel();
            continue;
          }
          if (response.statusCode != HttpStatus.ok) {
            throw const HttpException('Image response rejected');
          }
          if (response.contentLength > limits.maxBytes) {
            throw const ImageResponseTooLarge();
          }
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in response) {
            limits.check();
            if (bytes.length + chunk.length > limits.maxBytes) {
              throw const ImageResponseTooLarge();
            }
            bytes.add(chunk);
          }
          if (bytes.isEmpty) throw const HttpException('Empty image response');
          return bytes.takeBytes();
        }
        throw const HttpException('Image redirect limit exceeded');
      })().timeout(limits.timeout);
      limits.check();
      successful = true;
      return bytes;
    } on TimeoutException {
      limits.cancel();
      rethrow;
    } catch (_) {
      limits.check();
      rethrow;
    } finally {
      // A released consumer must not later close a client leased to a new image.
      limits.onCancel(() {});
      if (successful && sameOrigin && !_closed && _active.remove(client)) {
        _idle.add((origin, client));
      } else {
        retire();
      }
    }
  }

  /// Session boundaries also discard idle sockets, despite the public transport
  /// never carrying credentials. The service can start fresh after this call.
  void reset() {
    for (final client in [..._active, ..._idle.map((entry) => entry.$2)]) {
      client.close(force: true);
    }
    _active.clear();
    _idle.clear();
  }

  void close() {
    _closed = true;
    reset();
  }
}

final class CachedImageBytes {
  const CachedImageBytes(this.bytes, {this.fromDisk = false});
  final Uint8List bytes;
  final bool fromDisk;
}

/// Visible images take the next free transport slot before viewport prefetch.
enum ImageLoadPriority { visible, prefetch }

/// One consumer of a shared URL transfer. Releasing a lease never cancels
/// another consumer; the last release cancels unfinished transport immediately.
final class ImageByteLease {
  ImageByteLease._(this.result, this._release, this._setPriority);
  final Future<CachedImageBytes> result;
  final void Function() _release;
  final void Function(ImageLoadPriority) _setPriority;
  bool _released = false;

  void setPriority(ImageLoadPriority priority) {
    if (!_released) _setPriority(priority);
  }

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

final class _ImageTask {
  _ImageTask({
    required this.uri,
    required this.scope,
    required this.generation,
    required this.policy,
    required this.storageEpoch,
    required this.request,
    required this.skipDisk,
  });
  final Uri uri;
  final String scope;
  final int generation, policy, storageEpoch;
  final ImageLoadRequest request;
  final bool skipDisk;
  final result = Completer<CachedImageBytes>();
  final cancelled = Completer<void>();
  final consumers = <Object, ImageLoadPriority>{};
  Completer<void>? slot;
  bool get visible => consumers.values.contains(ImageLoadPriority.visible);
}

final class _DiskEntry {
  _DiskEntry(this.file, this.size, this.modified);
  final File file;
  final int size;
  DateTime modified;
}

final class _PendingImageWrite {
  _PendingImageWrite(this.task, this.bytes);
  final _ImageTask task;
  final Uint8List bytes;
}

/// Account-scoped, bounded, best-effort storage. Disk failures never prevent a
/// successfully downloaded image from being displayed. Only digests and numeric
/// timestamps are written; URLs and account identifiers are never persisted.
final class ImageByteCache {
  ImageByteCache({
    required this.directory,
    this.fileForPath = File.new,
    ImageByteLoader? loader,
    DateTime Function()? now,
    this.maxEntries = 512,
    this.maxTotalBytes = 64 * 1024 * 1024,
    this.maxImageBytes = 4 * 1024 * 1024,
    this.maxConcurrent = 6,
    this.maxPending = 64,
    this.maxPendingWrites = 16,
    this.maxPendingWriteBytes = 16 * 1024 * 1024,
    this.ttl = const Duration(days: 7),
    this.timeout = const Duration(seconds: 15),
    bool enabled = true,
    // Keep the public named `loader` override while storing it privately.
    // ignore: prefer_initializing_formals
  }) : _loader = loader,
       _now = now ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _enabled = enabled;

  final Future<Directory> Function() directory;
  final File Function(String path) fileForPath;
  final ImageByteLoader? _loader;
  PublicImageTransport? _transport;
  late final ImageByteLoader loader =
      _loader ??
      (_transport = PublicImageTransport(maxConnections: maxConcurrent)).load;
  final DateTime Function() _now;
  final int maxEntries, maxTotalBytes, maxImageBytes, maxConcurrent, maxPending;
  final int maxPendingWrites, maxPendingWriteBytes;
  final Duration ttl, timeout;
  final Map<String, _ImageTask> _inFlight = {};
  final Set<Future<void>> _running = {};
  final List<_ImageTask> _waiting = [];
  final _capacityChanges = StreamController<void>.broadcast();
  final Map<String, _DiskEntry> _entries = {};
  final Map<String, _PendingImageWrite> _pendingWriteBuffers = {};
  Future<void> _diskQueue = Future.value();
  int _diskBytes = 0;
  int _pendingWrites = 0;
  int _pendingWriteBytes = 0;
  final Set<Future<void>> _diskReads = {};
  int _active = 0;
  int _generation = 0;
  int _policyGeneration = 0;
  int _storageEpoch = 0;
  bool _closed = false;
  bool _initialized = false;
  bool _initializationScheduled = false;
  bool _dispatchScheduled = false;
  bool _enabled;
  String _scope = 'guest';
  bool get enabled => _enabled;
  int get generation => _generation;
  String get scope => _scope;
  bool get hasCapacity => !_closed && _inFlight.length < maxPending;

  /// Includes the running write, so a blocked disk cannot retain unbounded
  /// downloaded byte buffers. Writes beyond either budget are simply skipped.
  int get pendingWrites => _pendingWrites;
  int get pendingWriteBytes => _pendingWriteBytes;

  /// Wait for optional persistence at explicit shutdown/verification boundaries.
  /// Display and transport admission never wait for this drain.
  Future<void> flushWrites() => _diskQueue;

  Stream<void> get capacityChanges => _capacityChanges.stream;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    ++_policyGeneration;
  }

  static bool isPublicImageUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      // Private message originals use a separate, credential-free image CDN.
      // The private viewer loads them in memory, bypassing the disk cache.
      (uri.host == 'message.biliimg.com' ||
          uri.host == 'hdslb.com' ||
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
    for (final entry in _inFlight.entries.toList()) {
      _cancel(entry.key, entry.value);
    }
    _transport?.reset();
  }

  Future<void> clearScope(String scope) {
    // Invalidate pending writes synchronously, including loads that have not
    // reached the write queue yet. The serialized delete then drains old work.
    ++_storageEpoch;
    return _diskOperation(() async {
      final root = await directory();
      final scopeDirectory = Directory(path.join(root.path, _digest(scope)));
      if (await scopeDirectory.exists()) {
        await scopeDirectory.delete(recursive: true);
      }
      for (final entry in _entries.values.toList()) {
        if (path.isWithin(scopeDirectory.path, entry.file.path)) {
          _forget(entry.file.path);
        }
      }
    });
  }

  /// Non-widget consumers own demand until completion; widgets use acquire so
  /// viewport/source disposal can release their demand before completion.
  Future<CachedImageBytes> load(Uri uri, {bool skipDisk = false}) {
    final lease = acquire(uri, skipDisk: skipDisk);
    return lease.result.whenComplete(lease.release);
  }

  ImageByteLease acquire(
    Uri uri, {
    bool skipDisk = false,
    ImageLoadPriority priority = ImageLoadPriority.visible,
  }) {
    if (_closed || !isPublicImageUri(uri)) {
      return ImageByteLease._(
        Future.error(const ImageLoadCancelled()),
        () {},
        (_) {},
      );
    }
    final key = '$_generation:${_digest(uri.toString())}';
    var task = _inFlight[key];
    if (task == null) {
      if (_inFlight.length >= maxPending) {
        return ImageByteLease._(
          Future.error(const ImageQueueFull()),
          () {},
          (_) {},
        );
      }
      task = _ImageTask(
        uri: uri,
        scope: _scope,
        generation: _generation,
        policy: _policyGeneration,
        storageEpoch: _storageEpoch,
        request: ImageLoadRequest(maxBytes: maxImageBytes, timeout: timeout),
        skipDisk: skipDisk,
      );
      _inFlight[key] = task;
      // A consumer may release a deferred image before Flutter listens.
      // Keep cancellation handled while preserving errors on the result.
      unawaited(
        task.result.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      final created = task;
      late final Future<void> running;
      running = Future<void>.microtask(() => _run(key, created))
          .whenComplete(() => _running.remove(running));
      _running.add(running);
    }
    final shared = task;
    final consumer = Object();
    shared.consumers[consumer] = priority;
    return ImageByteLease._(shared.result.future, () {
      shared.consumers.remove(consumer);
      if (shared.consumers.isEmpty && !shared.result.isCompleted) {
        _cancel(key, shared);
      }
    }, (value) => shared.consumers[consumer] = value);
  }

  void _remove(String key, _ImageTask task) {
    if (!identical(_inFlight[key], task)) return;
    _inFlight.remove(key);
    if (!_closed && _capacityChanges.hasListener) _capacityChanges.add(null);
  }

  void _cancel(String key, _ImageTask task) {
    task.request.cancel();
    if (!task.cancelled.isCompleted) task.cancelled.complete();
    if (_waiting.remove(task)) {
      task.slot?.completeError(const ImageLoadCancelled());
    }
    if (!task.result.isCompleted) {
      task.result.completeError(const ImageLoadCancelled());
    }
    _remove(key, task);
  }

  Future<void> _run(String key, _ImageTask task) async {
    try {
      task.request.check();
      final result = await Future.any([
        _load(task),
        task.cancelled.future.then<CachedImageBytes>(
          (_) => throw const ImageLoadCancelled(),
        ),
      ]);
      if (!task.result.isCompleted) task.result.complete(result);
    } catch (error, stack) {
      if (!task.result.isCompleted) task.result.completeError(error, stack);
    } finally {
      _remove(key, task);
    }
  }

  Future<CachedImageBytes> _load(_ImageTask task) async {
    final key = _digest(task.uri.toString());
    final pending = _pendingWriteBuffers['${task.generation}:$key'];
    if (!task.skipDisk && pending != null && _canStore(pending.task)) {
      return CachedImageBytes(pending.bytes);
    }
    if (_enabled && !task.skipDisk && _diskReads.length < maxPending) {
      // Disk hits may proceed while optional writes wait. Atomic replacement
      // means a reader sees either a complete old file or a complete new file.
      // Initialization/maintenance remains on the serialized writer queue.
      if (!_initialized && !_initializationScheduled) {
        _initializationScheduled = true;
        unawaited(
          _diskOperation(() async {}).whenComplete(() {
            _initializationScheduled = false;
          }),
        );
      }
      final cached = await _read(task, key);
      task.request.check();
      if (cached != null && _canStore(task)) {
        return CachedImageBytes(cached, fromDisk: true);
      }
    }
    await _acquire(task);
    try {
      task.request.check();
      final bytes =
          await Future.any([
            loader(task.uri, task.request),
            task.cancelled.future.then<Uint8List>(
              (_) => throw const ImageLoadCancelled(),
            ),
          ]).timeout(
            timeout,
            onTimeout: () {
              task.request.cancel();
              throw TimeoutException('Image deadline exceeded');
            },
          );
      task.request.check();
      if (task.generation != _generation) throw const ImageLoadCancelled();
      if (bytes.isEmpty || bytes.length > maxImageBytes) {
        throw const HttpException('Image response size rejected');
      }
      _scheduleWrite(task, key, bytes);
      return CachedImageBytes(bytes);
    } finally {
      _release();
    }
  }

  Future<Uint8List?> _read(_ImageTask task, String key) async {
    Uint8List? cached;
    late final Future<void> operation;
    operation = (() async {
      try {
        if (!_canStore(task) || task.request.cancelled) return;
        final file = await _file(task.scope, key);
        final observedEntry = _entries[file.path];
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size > maxImageBytes + 256) {
          return;
        }
        final content = await file.readAsBytes();
        final separator = content.indexOf(10);
        if (separator < 0 || separator > 255) return;
        final Object? decoded = jsonDecode(
          utf8.decode(content.sublist(0, separator)),
        );
        if (decoded is! Map<String, Object?>) return;
        final created = decoded['created'];
        final bytes = Uint8List.sublistView(content, separator + 1);
        if (created is! int ||
            bytes.isEmpty ||
            bytes.length > maxImageBytes ||
            _now().millisecondsSinceEpoch - created > ttl.inMilliseconds ||
            sha256.convert(bytes).toString() != decoded['digest'] ||
            !_canStore(task) ||
            task.request.cancelled) {
          return;
        }
        cached = bytes;
        await file.setLastModified(_now());
        // Readers only touch an existing entry. A concurrent clear, invalidate
        // or eviction must never be undone by a late read re-inserting it.
        final entry = _entries[file.path];
        if (_canStore(task) &&
            entry != null &&
            identical(entry, observedEntry)) {
          entry.modified = _now();
        }
      } on Exception {
        // Missing, expired or corrupt data is a cache miss. A later atomic
        // write replaces it; no racing delete can remove another writer's file.
      }
    })().whenComplete(() => _diskReads.remove(operation));
    _diskReads.add(operation);
    await operation;
    return cached;
  }

  bool _canStore(_ImageTask task) =>
      _enabled &&
      task.policy == _policyGeneration &&
      task.generation == _generation &&
      task.storageEpoch == _storageEpoch;

  void _scheduleWrite(_ImageTask task, String key, Uint8List bytes) {
    if (!_canStore(task) ||
        _pendingWrites >= maxPendingWrites ||
        _pendingWriteBytes + bytes.length > maxPendingWriteBytes) {
      return;
    }
    ++_pendingWrites;
    _pendingWriteBytes += bytes.length;
    final bufferKey = '${task.generation}:$key';
    final pending = _PendingImageWrite(task, bytes);
    _pendingWriteBuffers[bufferKey] = pending;
    unawaited(
      _diskOperation(() async {
        if (!_canStore(task)) return;
        final file = await _file(task.scope, key);
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
          if (!_canStore(task)) return;
          await temporary.rename(file.path);
          await file.setLastModified(_now());
          _remember(file, header.length + bytes.length);
          await _pruneIndex();
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }).whenComplete(() {
        if (identical(_pendingWriteBuffers[bufferKey], pending)) {
          _pendingWriteBuffers.remove(bufferKey);
        }
        --_pendingWrites;
        _pendingWriteBytes -= bytes.length;
      }),
    );
  }

  Future<File> _file(String scope, String key) async => fileForPath(
    path.join((await directory()).path, _digest(scope), '$key.img'),
  );

  Future<void> invalidate(Uri uri) {
    final scope = _scope;
    _pendingWriteBuffers.remove('$_generation:${_digest(uri.toString())}');
    return _diskOperation(() async {
      final file = await _file(scope, _digest(uri.toString()));
      if (await file.exists()) await file.delete();
      _forget(file.path);
    });
  }

  void _forget(String filePath) {
    final previous = _entries.remove(filePath);
    if (previous != null) _diskBytes -= previous.size;
  }

  void _remember(File file, int size, [DateTime? modified]) {
    _forget(file.path);
    _entries[file.path] = _DiskEntry(file, size, modified ?? _now());
    _diskBytes += size;
  }

  Future<void> _initializeIndex() async {
    final root = await directory();
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (!entity.path.endsWith('.img') ||
          _now().difference(stat.modified) > ttl) {
        await entity.delete();
      } else {
        _remember(entity, stat.size, stat.modified);
        // Bound the index even if an older/external cache exceeds the quota.
        if (_entries.length > maxEntries || _diskBytes > maxTotalBytes) {
          await _pruneIndex();
        }
      }
    }
  }

  Future<void> _pruneIndex() async {
    final entries = _entries.values.toList()
      ..sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (_entries.length <= maxEntries &&
          _diskBytes <= maxTotalBytes &&
          _now().difference(entry.modified) <= ttl) {
        break;
      }
      if (await entry.file.exists()) await entry.file.delete();
      _forget(entry.file.path);
    }
  }

  Future<void> _diskOperation(Future<void> Function() action) {
    final operation = _diskQueue.then((_) async {
      try {
        if (!_initialized) {
          await _initializeIndex();
          _initialized = true;
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

  Future<void> _acquire(_ImageTask task) async {
    task.request.check();
    final waiter = Completer<void>();
    task.slot = waiter;
    _waiting.add(task);
    _scheduleDispatch();
    await waiter.future;
  }

  void _scheduleDispatch() {
    if (_dispatchScheduled) return;
    _dispatchScheduled = true;
    // Collect demand from the current layout before assigning free slots, so
    // a preceding prefetch child cannot jump ahead of visible siblings.
    scheduleMicrotask(() {
      _dispatchScheduled = false;
      while (_active < maxConcurrent && _waiting.isNotEmpty) {
        final visible = _waiting.indexWhere((task) => task.visible);
        final task = _waiting.removeAt(visible < 0 ? 0 : visible);
        ++_active;
        task.slot?.complete();
      }
    });
  }

  void _release() {
    --_active;
    _scheduleDispatch();
  }

  Future<void> close() async {
    _closed = true;
    for (final entry in _inFlight.entries.toList()) {
      _cancel(entry.key, entry.value);
    }
    _transport?.close();
    await Future.wait(_running.toList());
    await Future.wait(_diskReads.toList());
    await _diskQueue;
    await _capacityChanges.close();
  }
}
