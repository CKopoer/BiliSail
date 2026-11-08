import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'mp4_buffer_index.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'validated_source.dart';

/// Source-owned, memory-only DASH transport shared by both native backends.
/// A stalled HTTP read resumes at the next byte without replacing the native
/// demuxer, flushing decoded packets, seeking, or changing the playback clock.
final class DashTrackBuffer {
  DashTrackBuffer._(this._server, this._token, this._video, this._audio);
  final HttpServer _server;
  final String _token;
  final _TrackBuffer _video, _audio;
  bool _closed = false;
  Future<void>? _closure;
  final _requests = <Future<void>>{};

  static bool supports(ValidatedSource plan) =>
      plan.source is DashPairSource &&
      plan.audio != null &&
      [plan.media, plan.audio!].every(
        (track) => track.uri.scheme == 'http' || track.uri.scheme == 'https',
      );

  static Future<DashTrackBuffer> create(
    ValidatedSource plan, {
    Duration inactivityTimeout = const Duration(seconds: 2),
    Duration recoveryTimeout = const Duration(seconds: 10),
    int maximumRetries = 3,
    int videoCapacity = 32 * 1024 * 1024,
    int? audioCapacity,
    void Function(NativeErrorSummary)? onFailure,
  }) async {
    if (!supports(plan)) throw ArgumentError('HTTP DASH pair required');
    if (inactivityTimeout <= Duration.zero ||
        recoveryTimeout <= Duration.zero ||
        maximumRetries < 0 ||
        videoCapacity <= 0 ||
        audioCapacity != null && audioCapacity <= 0) {
      throw ArgumentError('Invalid DASH transport limits');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // High quality audio can exceed 8 MiB within the ordinary window. Use the
    // nominal bitrate only for a bounded byte allowance, never for timestamps.
    final audioRate = (plan.audio!.bandwidth ?? 0).clamp(0, 128 * 1024 * 1024);
    final audioWindowBytes =
        audioRate * plan.options.maxBufferAhead.inMilliseconds ~/ 8000;
    final soundCapacity =
        audioCapacity ??
        min<int>(
          32 * 1024 * 1024,
          max<int>(
            8 * 1024 * 1024,
            audioWindowBytes + audioWindowBytes ~/ 4 + 1024 * 1024,
          ),
        );
    final random = Random.secure();
    final token = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _TrackBuffer track(MediaTrack media, int capacity) => _TrackBuffer(
      media,
      capacity,
      inactivityTimeout,
      recoveryTimeout,
      maximumRetries,
      onFailure,
    );
    final buffer = DashTrackBuffer._(
      server,
      token,
      track(plan.media, videoCapacity),
      track(plan.audio!, soundCapacity),
    );
    server.listen(buffer._serve);
    return buffer;
  }

  MediaTrack _local(MediaTrack original, String name) => MediaTrack(
    uri: Uri.parse('http://127.0.0.1:${_server.port}/$_token/$name'),
    requestPolicy: MediaRequestPolicy(),
    codec: original.codec,
    bandwidth: original.bandwidth,
  );

  ValidatedSource prepare(ValidatedSource plan) => ValidatedSource(
    source: plan.source,
    options: plan.options,
    media: _local(plan.media, 'video.mp4'),
    audio: _local(plan.audio!, 'audio.m4a'),
    requiresVideo: plan.requiresVideo,
    audioOnly: plan.audioOnly,
    silent: plan.silent,
    live: plan.live,
  );

  ({Duration video, Duration audio}) buffered(Duration position) =>
      (video: _video.buffered(position), audio: _audio.buffered(position));

  Duration commonBuffered(Duration position, Duration nativeEnd) {
    final ends = buffered(position);
    // The native endpoint remains an upper bound: downloaded bytes must not
    // overstate the native packet window or the configured memory limits.
    final end = [
      ends.video,
      ends.audio,
      nativeEnd,
    ].reduce((a, b) => a < b ? a : b);
    return end < position ? position : end;
  }

  void _serve(HttpRequest request) {
    final track = switch (request.uri.path) {
      final path when path == '/$_token/video.mp4' => _video,
      final path when path == '/$_token/audio.m4a' => _audio,
      _ => null,
    };
    if (_closed ||
        track == null ||
        _requests.length >= 8 ||
        !{'GET', 'HEAD'}.contains(request.method)) {
      request.response.statusCode = HttpStatus.notFound;
      unawaited(request.response.close().catchError((Object _) {}));
      return;
    }
    late final Future<void> work;
    work = track.serve(request).whenComplete(() => _requests.remove(work));
    _requests.add(work);
  }

  /// Stop native I/O before waiting for native teardown, including pending
  /// response headers and delayed bodies; no signed address reaches disk.
  Future<void> close() => _closure ??= _close();

  Future<void> _close() async {
    _closed = true;
    _video.close();
    _audio.close();
    await _server.close(force: true);
    await Future.wait(_requests.toList());
  }
}

final class _TrackBuffer {
  _TrackBuffer(
    this.track,
    this.capacity,
    this.inactivity,
    this.budget,
    this.maximumRetries,
    this.onFailure,
  );
  final MediaTrack track;
  final int capacity, maximumRetries;
  final Duration inactivity, budget;
  final void Function(NativeErrorSummary)? onFailure;
  final _cache = SplayTreeMap<int, Uint8List>();
  final _age = Queue<int>();
  final _clients = <HttpClient>{};
  int _bytes = 0;
  int? _length;
  String? _etag, _modified;
  Uint8List _prefix = Uint8List(0);
  Mp4BufferIndex? _index;
  bool _indexing = false;
  bool _closed = false;

  Duration buffered(Duration position) =>
      _index?.buffered(position, _contains) ?? position;

  bool _contains(int offset, int length) {
    final end = offset + length;
    while (offset < end) {
      final key = _cache.lastKeyBefore(offset + 1);
      if (key == null) return false;
      final bytes = _cache[key]!;
      if (key + bytes.length <= offset) return false;
      offset = key + bytes.length;
    }
    return true;
  }

  Uint8List? _cached(int offset, int end) {
    if (offset > end) return null;
    final key = _cache.lastKeyBefore(offset + 1);
    if (key == null) return null;
    final bytes = _cache[key]!;
    if (key + bytes.length <= offset) return null;
    return Uint8List.sublistView(
      bytes,
      offset - key,
      min(bytes.length, end + 1 - key),
    );
  }

  void _store(int offset, List<int> bytes) {
    if (_closed || bytes.isEmpty) return;
    // Retain bounded index data separately, not an unbounded media prefix.
    if (_index == null &&
        offset <= _prefix.length &&
        _prefix.length < Mp4BufferIndex.maximumMetadataBytes) {
      final end = min(
        offset + bytes.length,
        Mp4BufferIndex.maximumMetadataBytes,
      );
      if (end > _prefix.length) {
        final next = Uint8List(end)..setRange(0, _prefix.length, _prefix);
        next.setRange(_prefix.length, end, bytes, _prefix.length - offset);
        _prefix = next;
        _parseIndex();
      }
    }
    // Network chunks can be larger than the retention budget. Split them so
    // every allocation and the retained byte total have an explicit bound.
    for (var p = 0; p < bytes.length; p += 64 * 1024) {
      final data = Uint8List.fromList(
        bytes.sublist(p, min(p + 64 * 1024, bytes.length)),
      );
      final key = offset + p;
      _bytes -= _cache.remove(key)?.length ?? 0;
      _cache[key] = data;
      _age.remove(key);
      _age.add(key);
      _bytes += data.length;
      while (_bytes > capacity || _age.length > 4096) {
        final oldKey = _age.removeFirst();
        _bytes -= _cache.remove(oldKey)?.length ?? 0;
      }
    }
  }

  void _parseIndex() {
    if (_closed || _indexing || _index != null) return;
    _indexing = true;
    final prefix = _prefix;
    unawaited(
      _readIndex(prefix).then<void>(
        (index) {
          _indexing = false;
          if (_closed) return;
          _index = index;
          if (index != null) {
            _prefix = Uint8List(0);
          } else if (_prefix.length > prefix.length) {
            _parseIndex();
          }
        },
        onError: (Object _) {
          // Index parsing is optional evidence. Failure must not become a guessed
          // buffer endpoint or terminate a valid native media stream.
          _indexing = false;
        },
      ),
    );
  }

  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _cache.clear();
    _age.clear();
    _prefix = Uint8List(0);
    _index = null;
  }

  Future<HttpClientResponse> _open(
    HttpClient client,
    int start,
    int end,
  ) async {
    var uri = track.uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await client.getUrl(uri).timeout(inactivity);
      request.followRedirects = false;
      track.requestPolicy.headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      if (start > 0 && (_etag ?? _modified) != null) {
        request.headers.set(HttpHeaders.ifRangeHeader, _etag ?? _modified!);
      }
      final response = await request.close().timeout(
        inactivity,
        onTimeout: () {
          request.abort();
          throw TimeoutException('DASH response stalled');
        },
      );
      if (!{301, 302, 303, 307, 308}.contains(response.statusCode)) {
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.listen((_) {}).cancel();
      if (location == null) throw const _ReadFailure();
      final next = uri.resolve(location);
      if (!{'http', 'https'}.contains(next.scheme) ||
          next.userInfo.isNotEmpty ||
          uri.scheme == 'https' && next.scheme != 'https') {
        throw const _ReadFailure();
      }
      uri = next;
    }
    throw const _ReadFailure();
  }

  /// Validate resumed bytes against the same object before forwarding any.
  int _validate(HttpClientResponse response, int start, int end) {
    if (response.statusCode != 206) {
      throw _ReadFailure(
        retryable: {408, 429, 500, 502, 503, 504}.contains(response.statusCode),
        httpStatus: response.statusCode,
      );
    }
    var length = response.contentLength;
    var last = length - 1;
    if (response.statusCode == 206) {
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
        response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
      );
      if (range == null || int.parse(range[1]!) != start) {
        throw const _ReadFailure();
      }
      last = int.parse(range[2]!);
      length = int.parse(range[3]!);
      if (last < start ||
          last >= length ||
          last > end ||
          response.contentLength >= 0 &&
              response.contentLength != last - start + 1) {
        throw const _ReadFailure();
      }
    }
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final modified = response.headers.value(HttpHeaders.lastModifiedHeader);
    final encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
    if (length <= 0 ||
        encoding != null && encoding != 'identity' ||
        _length != null && _length != length ||
        _etag != null && etag != _etag ||
        _modified != null && modified != _modified) {
      throw const _ReadFailure();
    }
    _length = length;
    // A weak ETag cannot validate an If-Range request.
    if (etag != null && !etag.startsWith('W/')) _etag ??= etag;
    _modified ??= modified;
    return last;
  }

  Future<void> _fill(
    HttpClient client,
    int offset,
    int end,
    void Function() changed,
  ) async {
    var retries = 0;
    Stopwatch? recovering;
    while (!_closed && offset <= end) {
      try {
        final response = await _open(client, offset, end);
        final last = _validate(response, offset, end);
        end = min(end, _length! - 1);
        changed();
        final iterator = StreamIterator(response);
        try {
          while (await iterator.moveNext().timeout(inactivity)) {
            if (_closed) return;
            final bytes = iterator.current;
            if (offset + bytes.length > last + 1) throw const _ReadFailure();
            _store(offset, bytes);
            offset += bytes.length;
            changed();
          }
        } finally {
          await iterator.cancel();
        }
        if (offset <= last) throw const _ReadFailure(retryable: true);
      } on Object catch (error) {
        if (_closed) return;
        final retryable =
            error is TimeoutException ||
            error is SocketException ||
            error is HttpException ||
            error is _ReadFailure && error.retryable;
        recovering ??= Stopwatch()..start();
        if (!retryable ||
            retries++ >= maximumRetries ||
            recovering.elapsed >= budget) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> serve(HttpRequest request) async {
    request.response.bufferOutput = false;
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = inactivity;
    _clients.add(client);
    var disconnected = false, headersSent = false;
    unawaited(
      request.response.done.then<void>(
        (_) {
          disconnected = true;
          client.close(force: true);
        },
        onError: (Object _) {
          disconnected = true;
          client.close(force: true);
        },
      ),
    );
    var offset = 0;
    int? requestedEnd;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(rangeHeader);
      if (match == null) {
        request.response.statusCode = 416;
        await request.response.close();
        _clients.remove(client);
        client.close(force: true);
        return;
      }
      offset = int.parse(match[1]!);
      if (match[2]!.isNotEmpty) requestedEnd = int.parse(match[2]!);
    }
    Future<void>? filling;
    Future<void> send(List<int> data) async {
      try {
        request.response.add(data);
        await request.response.flush();
      } on Object {
        disconnected = true;
        client.close(force: true);
        rethrow;
      }
    }

    void headers() {
      if (headersSent) return;
      final length = _length!;
      final end = min(requestedEnd ?? length - 1, length - 1);
      if (offset >= length || end < offset) throw const _ReadFailure();
      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentTypeHeader, 'video/mp4');
      request.response.contentLength = end - offset + 1;
      if (rangeHeader != null) {
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $offset-$end/$length',
        );
      }
      headersSent = true;
    }

    try {
      while (!_closed && !disconnected) {
        var end = min(
          requestedEnd ?? 0x7fffffffffffffff,
          (_length ?? 0x7fffffffffffffff) - 1,
        );
        if (_length != null) {
          headers();
          if (request.method == 'HEAD' || offset > end) break;
          final cached = _cached(offset, end);
          if (cached != null) {
            await send(cached);
            offset += cached.length;
            continue;
          }
        }
        // Bounded range requests permit exact continuation and keep SDK read
        // backpressure separate from the upstream inactivity timer.
        final block = min<int>(
          4 * 1024 * 1024,
          max<int>(256 * 1024, (track.bandwidth ?? 0) ~/ 4),
        );
        end = min<int>(end, offset + min<int>(block, capacity) - 1);
        var done = false;
        Object? failure;
        Completer<void>? wake;
        void changed() {
          final pending = wake;
          wake = null;
          if (pending != null && !pending.isCompleted) pending.complete();
        }

        // Keep fetching this bounded block even when the SDK pauses its local
        // socket. Its inactivity timer must not wait for playback to consume
        // buffered data before resuming a stalled upstream connection.
        filling = _fill(client, offset, end, changed).then<void>(
          (_) {
            done = true;
            changed();
          },
          onError: (Object error) {
            failure = error;
            done = true;
            changed();
          },
        );
        while (!_closed && !disconnected) {
          if (_length != null) {
            headers();
            if (request.method == 'HEAD') break;
            if (offset > min(end, _length! - 1)) break;
            final cached = _cached(offset, min(end, _length! - 1));
            if (cached != null) {
              await send(cached);
              offset += cached.length;
              continue;
            }
          }
          if (done) break;
          wake = Completer<void>();
          await wake!.future;
        }
        if (_closed || disconnected || request.method == 'HEAD') break;
        await filling;
        filling = null;
        if (failure != null) throw failure!;
      }
    } on Object catch (error) {
      // This is a failed native byte stream, never an empty successful source.
      // Do not forward exception messages containing CDN URLs or headers.
      if (!_closed &&
          !disconnected &&
          error is _ReadFailure &&
          error.httpStatus != null) {
        onFailure?.call(
          NativeErrorSummary(
            NativeErrorCause.http,
            httpStatus: error.httpStatus,
            component: 'stream',
          ),
        );
      }
      if (!headersSent) request.response.statusCode = HttpStatus.badGateway;
    } finally {
      client.close(force: true);
      await filling;
      _clients.remove(client);
      try {
        await request.response.close();
      } on Object {
        /* Retired reader. */
      }
    }
  }
}

final class _ReadFailure implements Exception {
  const _ReadFailure({this.retryable = false, this.httpStatus});
  final bool retryable;
  final int? httpStatus;
}

Future<Mp4BufferIndex?> _readIndex(Uint8List prefix) =>
    Isolate.run(() => Mp4BufferIndex.parse(prefix));
