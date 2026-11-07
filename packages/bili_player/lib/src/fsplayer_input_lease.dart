import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'fsplayer_source.dart';

/// Bounded, per-source input broker. Network requests use the system TLS
/// verifier; local media stays on the native file path. No source data is logged.
final class FsPlayerInputLease {
  FsPlayerInputLease._(this.url, this._server, this._headers);
  final String url;
  final HttpServer? _server;
  final Map<String, String> _headers;
  StreamSubscription<HttpRequest>? _subscription;
  final _resources = <String, ({Uri uri, bool hls})>{};
  final _paths = <Uri, String>{};
  final _activePaths = <String>{};
  HttpClient? _client;
  List<int>? _manifest;
  int _next = 0, _active = 0;
  bool _closed = false;

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<FsPlayerInputLease> open(FsPlayerInput input) async {
    final uri = Uri.parse(input.url);
    if (!input.hls && !{'http', 'https', 'data'}.contains(uri.scheme)) {
      return FsPlayerInputLease._(input.url, null, input.headers);
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = const Duration(seconds: 5);
    final random = Random.secure();
    final token = base64UrlEncode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final root = 'http://127.0.0.1:${server.port}/$token/';
    final lease = FsPlayerInputLease._('${root}input', server, input.headers);
    if (uri.scheme == 'data') {
      var manifest = utf8.decode(
        base64Decode(input.url.substring(input.url.indexOf(',') + 1)),
      );
      for (final resource in input.resources) {
        if ({'http', 'https'}.contains(resource.scheme)) {
          manifest = manifest.replaceAll(
            _xml(resource.toString()),
            _xml(lease._register(resource)),
          );
        }
      }
      lease._manifest = utf8.encode(manifest);
    } else {
      lease._resources[Uri.parse(lease.url).path] = (uri: uri, hls: input.hls);
      lease._paths[uri] = Uri.parse(lease.url).path;
    }
    lease._subscription = server.listen(
      (request) => unawaited(lease._respond(request)),
    );
    return lease;
  }

  String _register(Uri uri) {
    if (uri.scheme == 'file') return uri.toString();
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsupported media resource');
    }
    var path = _paths[uri];
    if (path == null) {
      if (_resources.length >= 512) {
        final retired = _resources.keys
            .where(
              (key) =>
                  !_activePaths.contains(key) && key != Uri.parse(url).path,
            )
            .firstOrNull;
        if (retired == null) {
          throw const FormatException('Media resource capacity');
        }
        final old = _resources.remove(retired);
        _paths.remove(old?.uri);
      }
      path = '${Uri.parse(url).path}/r${_next++}';
      _paths[uri] = path;
      _resources[path] = (
        uri: uri,
        hls: uri.path.toLowerCase().endsWith('.m3u8'),
      );
    }
    return Uri.parse(url).replace(path: path).toString();
  }

  Future<void> _respond(HttpRequest request) async {
    final path = request.uri.path;
    if (_closed || _active >= 8 || !{'GET', 'HEAD'}.contains(request.method)) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    _active++;
    _activePaths.add(path);
    try {
      if (path == Uri.parse(url).path && _manifest != null) {
        request.response.headers.contentType = ContentType(
          'application',
          'dash+xml',
        );
        request.response.contentLength = _manifest!.length;
        if (request.method == 'GET') request.response.add(_manifest!);
      } else {
        final resource = _resources[path];
        if (resource == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          await _forward(request, resource);
        }
      }
      await request.response.close();
    } on Object {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } on Object {
        /* Native cancellation may have closed the socket. */
      }
    } finally {
      _active--;
      _activePaths.remove(path);
    }
  }

  Future<List<int>> _readManifest(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('Manifest capacity');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<void> _forward(
    HttpRequest request,
    ({Uri uri, bool hls}) resource,
  ) async {
    if (resource.uri.scheme == 'file' && resource.hls) {
      final bytes = await _readManifest(File.fromUri(resource.uri).openRead());
      _writeHls(request, bytes, resource.uri);
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null &&
        (range.length > 80 || !RegExp(r'^bytes=\d*-\d*$').hasMatch(range))) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      return;
    }
    final client = _client ??= (HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 5)
      ..maxConnectionsPerHost = 8
      ..autoUncompress = false);
    final outgoing = await client
        .openUrl(request.method, resource.uri)
        .timeout(const Duration(seconds: 10));
    _headers.forEach(outgoing.headers.set);
    outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (range != null) outgoing.headers.set(HttpHeaders.rangeHeader, range);
    final response = await outgoing.close().timeout(
      const Duration(seconds: 15),
    );
    request.response.statusCode = response.statusCode;
    var resolved = resource.uri;
    for (final redirect in response.redirects) {
      resolved = resolved.resolveUri(redirect.location);
    }
    final hls =
        resource.hls ||
        resolved.path.toLowerCase().endsWith('.m3u8') ||
        (response.headers.contentType?.mimeType.toLowerCase().contains(
              'mpegurl',
            ) ??
            false);
    if (hls && request.method == 'GET' && response.statusCode == 200) {
      if (response.headers.value(HttpHeaders.contentEncodingHeader)
          case final encoding? when encoding != 'identity') {
        throw const FormatException('Compressed manifest');
      }
      _writeHls(request, await _readManifest(response), resolved);
      return;
    }
    for (final header in [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.contentEncodingHeader,
    ]) {
      final value = response.headers.value(header);
      if (value != null) request.response.headers.set(header, value);
    }
    if (response.contentLength >= 0) {
      request.response.contentLength = response.contentLength;
    }
    if (request.method == 'HEAD') {
      await response.drain<void>();
    } else {
      await request.response.addStream(
        response.timeout(const Duration(seconds: 15)),
      );
    }
  }

  void _writeHls(HttpRequest request, List<int> bytes, Uri base) {
    final text = utf8.decode(bytes);
    if (!text.trimLeft().startsWith('#EXTM3U')) {
      throw const FormatException('Invalid HLS manifest');
    }
    final lines = const LineSplitter().convert(text);
    if (lines.length > 8192) throw const FormatException('Manifest capacity');
    final uriAttribute = RegExp(r'''URI="([^"]+)"''');
    final rewritten = lines
        .map((line) {
          final value = line.trim();
          if (value.isNotEmpty && !value.startsWith('#')) {
            return _register(base.resolve(value));
          }
          return line.replaceAllMapped(
            uriAttribute,
            (match) => 'URI="${_register(base.resolve(match[1]!))}"',
          );
        })
        .join('\n');
    final output = utf8.encode(rewritten);
    request.response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
    );
    request.response.contentLength = output.length;
    if (request.method == 'GET') request.response.add(output);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client?.close(force: true);
    await _subscription?.cancel();
    await _server?.close(force: true);
    _resources.clear();
    _paths.clear();
  }
}
