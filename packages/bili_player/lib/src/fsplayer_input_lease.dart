import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'fsplayer_source.dart';

/// In-memory manifests and opaque native inputs; media bytes bypass Dart.
final class FsPlayerInputLease {
  FsPlayerInputLease._(this.url, this._server, this._subscription);
  final String url;
  final HttpServer? _server;
  final StreamSubscription<HttpRequest>? _subscription;

  static Future<FsPlayerInputLease> open(FsPlayerInput input) async {
    final uri = Uri.parse(input.url);
    if (!{'http', 'https', 'data'}.contains(uri.scheme)) {
      return FsPlayerInputLease._(input.url, null, null);
    }
    final manifest = uri.scheme == 'data'
        ? base64Decode(input.url.substring(input.url.indexOf(',') + 1))
        : null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = const Duration(seconds: 5);
    final random = Random.secure();
    final token = base64UrlEncode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final path = '/$token/${manifest == null ? 'media' : 'input.mpd'}';
    final url = 'http://127.0.0.1:${server.port}$path';
    Future<void> respond(HttpRequest request) async {
      try {
        if (request.uri.path != path ||
            !{'GET', 'HEAD'}.contains(request.method)) {
          request.response.statusCode = HttpStatus.notFound;
        } else if (manifest != null) {
          request.response.headers.contentType = ContentType(
            'application',
            'dash+xml',
          );
          request.response.contentLength = manifest.length;
          if (request.method == 'GET') request.response.add(manifest);
        } else {
          // Native FFmpeg follows the original URL with validated headers.
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, input.url);
          request.response.contentLength = 0;
        }
        await request.response.close();
      } on Object {
        // Native cancellation can close a request before its response completes.
      }
    }

    final subscription = server.listen(
      (request) => unawaited(respond(request)),
    );
    return FsPlayerInputLease._(url, server, subscription);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
  }
}
