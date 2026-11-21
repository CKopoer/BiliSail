import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/downloads/data/http_download_transfer.dart';
import 'package:bilisail/features/downloads/domain/download_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  final body = List<int>.generate(128, (index) => index);
  final ranges = <String?>[];
  var mode = 'range';
  late Completer<void> finishForeground;

  setUp(() async {
    finishForeground = Completer<void>();
    ranges.clear();
    mode = 'range';
    directory = await Directory.systemTemp.createTemp('bilisail_transfer');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      if (mode == 'handoff') {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.add(
          ascii.encode(
            'HTTP/1.1 200 OK\r\nContent-Length: 128\r\nETag: "v1"\r\n\r\n',
          ),
        );
        socket.add(body.take(40).toList());
        await socket.flush();
        await finishForeground.future;
        socket.destroy();
        return;
      } else if (mode == 'bad206' && range != null) {
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-127/128',
        );
        request.response.headers.contentLength = body.length;
        request.response.add(body);
      } else if (mode == 'short') {
        final socket = await request.response.detachSocket();
        socket.add(
          ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 128\r\n\r\n'),
        );
        socket.add(body.take(12).toList());
        await socket.flush();
        socket.destroy();
        return;
      } else if (mode == 'oversized206' && range != null) {
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 40-79/128',
        );
        request.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        request.response.add(body.skip(40).toList());
      } else if (mode == 'segment') {
        final start = range == null ? 0 : 64;
        final end = start == 0 ? 63 : 127;
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/128',
        );
        request.response.headers.contentLength = end - start + 1;
        request.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        request.response.add(body.skip(start).take(end - start + 1).toList());
      } else if (mode == 'changedEtag' && range != null) {
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 40-127/128',
        );
        request.response.headers.contentLength = 88;
        request.response.headers.set(HttpHeaders.etagHeader, '"v2"');
        request.response.add(body.skip(40).toList());
      } else if (mode == '416' && range != null) {
        request.response.statusCode = 416;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */128',
        );
        request.response.headers.set(HttpHeaders.etagHeader, '"v2"');
      } else if (range != null && mode == 'range') {
        final start = int.parse(range.substring(6, range.length - 1));
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${body.length - 1}/${body.length}',
        );
        request.response.headers.contentLength = body.length - start;
        request.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        request.response.add(body.skip(start).toList());
      } else {
        request.response.statusCode = 200;
        request.response.headers.contentLength = body.length;
        if (mode != 'noEtag') {
          request.response.headers.set(
            HttpHeaders.etagHeader,
            mode == 'invalidEtag'
                ? 'unquoted'
                : mode == 'changedEtag' || mode == '416'
                ? '"v2"'
                : '"v1"',
          );
        }
        request.response.add(body);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  DownloadTrackSource source(String identity) => DownloadTrackSource(
    identity: identity,
    kind: DownloadTrackKind.video,
    urls: [Uri.parse('http://127.0.0.1:${server.port}/video')],
    codec: 'avc1',
    bandwidth: 1000,
  );

  DownloadTrackProgress previous(String identity, int bytes) =>
      DownloadTrackProgress(
        kind: DownloadTrackKind.video,
        identity: identity,
        fileName: 'video.m4s',
        codec: 'avc1',
        bandwidth: 1000,
        bytes: bytes,
        totalBytes: bytes == 0 ? null : body.length,
        etag: bytes == 0 ? null : '"v1"',
      );

  test(
    'moving a live transfer to the background resumes at validated disk bytes',
    () async {
      mode = 'handoff';
      final system = _BackgroundTransfer((headers) async {
        expect(headers[HttpHeaders.rangeHeader], 'bytes=40-');
        expect(headers[HttpHeaders.ifRangeHeader], '"v1"');
        expect(headers.containsKey('Cookie'), isFalse);
        return TrackHttpResponse(
          status: 206,
          length: 88,
          range: 'bytes 40-127/128',
          etag: '"v1"',
          body: Stream.value(body.skip(40).toList()),
        );
      });
      final part = File('${directory.path}/video.m4s.part');
      try {
        final transfer = await HttpDownloadTransfer(background: system)
            .transfer(
              source: source('one'),
              previous: previous('one', 0),
              partFile: part,
              headers: const {'Cookie': 'discard'},
              cancellation: RequestCancellation(),
              onProgress: (track) {
                if (track.bytes == 40) system.hide();
              },
            );
        expect(transfer.bytes, body.length);
        expect(await part.readAsBytes(), body);
        expect(system.listener, isNull);
        expect(system.requests, 1);
        expect(ranges, [null]);
      } finally {
        finishForeground.complete();
      }
    },
  );

  test(
    'background response is validated before replacing the part file',
    () async {
      final staged = File('${directory.path}/system-response');
      final part = File('${directory.path}/video.m4s.part');
      final system = _BackgroundTransfer((_) async {
        await staged.writeAsBytes(body);
        return TrackHttpResponse(
          status: 200,
          length: body.length,
          range: null,
          etag: '"v1"',
          body: staged.openRead(),
          stagedFile: staged,
        );
      })..hide();
      final result = await HttpDownloadTransfer(background: system).transfer(
        source: source('one'),
        previous: previous('one', 0),
        partFile: part,
        headers: {},
        cancellation: RequestCancellation(),
        onProgress: (_) {},
      );
      expect(result.bytes, body.length);
      expect(await part.readAsBytes(), body);
      expect(await staged.exists(), isFalse);
      expect(ranges, isEmpty);
    },
  );

  test(
    'invalid system response is discarded without touching the saved prefix',
    () async {
      final part = File('${directory.path}/video.m4s.part');
      final prefix = body.take(40).toList();
      await part.writeAsBytes(prefix);
      final staged = File('${directory.path}/system-response');
      final system = _BackgroundTransfer((_) async {
        await staged.writeAsBytes(body);
        return TrackHttpResponse(
          status: 206,
          length: body.length,
          range: 'bytes 0-127/128',
          etag: '"v1"',
          body: staged.openRead(),
          stagedFile: staged,
        );
      })..hide();
      await expectLater(
        HttpDownloadTransfer(background: system).transfer(
          source: source('one'),
          previous: previous('one', 40),
          partFile: part,
          headers: {},
          cancellation: RequestCancellation(),
          onProgress: (_) {},
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.protocol,
          ),
        ),
      );
      expect(await part.readAsBytes(), prefix);
      expect(await staged.exists(), isFalse);
    },
  );

  test('resumes with validated Range and preserves bytes', () async {
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: previous('one', 40),
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, ['bytes=40-']);
    expect(result.bytes, body.length);
    expect(await part.readAsBytes(), body);
  });

  test('Range ignored by server restarts cleanly', () async {
    mode = 'ignore';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: previous('one', 40),
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(result.bytes, body.length);
    expect(await part.readAsBytes(), body);
  });

  test('malformed 206 is rejected without appending', () async {
    mode = 'bad206';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    await expectLater(
      const HttpDownloadTransfer().transfer(
        source: source('one'),
        previous: previous('one', 40),
        partFile: part,
        headers: const {},
        cancellation: RequestCancellation(),
        onProgress: (_) {},
      ),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.protocol,
        ),
      ),
    );
    expect(await part.length(), 40);
  });

  test('new source identity discards the old partial file', () async {
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    final result = await const HttpDownloadTransfer().transfer(
      source: source('two'),
      previous: previous('one', 40),
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, [null]);
    expect(result.identity, 'two');
    expect(await part.readAsBytes(), body);
  });

  test('short responses cannot be marked complete', () async {
    mode = 'short';
    final part = File('${directory.path}/video.m4s.part');
    await expectLater(
      const HttpDownloadTransfer().transfer(
        source: source('one'),
        previous: previous('one', 0),
        partFile: part,
        headers: const {},
        cancellation: RequestCancellation(),
        onProgress: (_) {},
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(
      await part.exists() ? await part.length() : 0,
      lessThan(body.length),
    );
  });

  test('partial 206 segments continue with a validated Range', () async {
    mode = 'segment';
    final part = File('${directory.path}/video.m4s.part');
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: previous('one', 0),
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, [null, 'bytes=64-']);
    expect(result.bytes, body.length);
    expect(await part.readAsBytes(), body);
  });

  test('chunked 206 cannot write beyond its declared range', () async {
    mode = 'oversized206';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    await expectLater(
      const HttpDownloadTransfer().transfer(
        source: source('one'),
        previous: previous('one', 40),
        partFile: part,
        headers: const {},
        cancellation: RequestCancellation(),
        onProgress: (_) {},
      ),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.protocol,
        ),
      ),
    );
    expect(await part.length(), 40);
  });

  test('changed ETag discards partial bytes before restarting', () async {
    mode = 'changedEtag';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: previous('one', 40),
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, ['bytes=40-', null]);
    expect(result.etag, '"v2"');
    expect(await part.readAsBytes(), body);
  });

  test('missing strong ETag starts over rather than resuming', () async {
    mode = 'noEtag';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    final old = DownloadTrackProgress(
      kind: DownloadTrackKind.video,
      identity: 'one',
      fileName: 'video.m4s',
      codec: 'avc1',
      bandwidth: 1000,
      bytes: 40,
      totalBytes: 128,
    );
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: old,
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, [null]);
    expect(result.bytes, body.length);
    expect(await part.readAsBytes(), body);
  });

  test('unquoted ETag is not trusted for Range continuation', () async {
    mode = 'invalidEtag';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body.take(40).toList());
    final old = DownloadTrackProgress(
      kind: DownloadTrackKind.video,
      identity: 'one',
      fileName: 'video.m4s',
      codec: 'avc1',
      bandwidth: 1000,
      bytes: 40,
      totalBytes: 128,
      etag: 'unquoted',
    );
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: old,
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, [null]);
    expect(result.etag, isNull);
    expect(await part.readAsBytes(), body);
  });

  test('416 without matching validator restarts from zero', () async {
    mode = '416';
    final part = File('${directory.path}/video.m4s.part');
    await part.writeAsBytes(body);
    final result = await const HttpDownloadTransfer().transfer(
      source: source('one'),
      previous: previous('one', 128),
      partFile: part,
      headers: const {},
      cancellation: RequestCancellation(),
      onProgress: (_) {},
    );
    expect(ranges, ['bytes=128-', null]);
    expect(result.etag, '"v2"');
    expect(await part.readAsBytes(), body);
  });
}

final class _BackgroundTransfer implements BackgroundTrackTransfer {
  _BackgroundTransfer(this.response);
  final Future<TrackHttpResponse> Function(Map<String, String>) response;
  int requests = 0;
  void Function()? listener;
  @override
  bool inBackground = false;

  void hide() {
    inBackground = true;
    listener?.call();
  }

  @override
  void Function() onHide(void Function() callback) {
    listener = callback;
    return () {
      listener = null;
    };
  }

  @override
  Future<TrackHttpResponse> fetch(
    Uri url,
    Map<String, String> headers,
    RequestCancellation cancellation,
    DateTime? deadline,
  ) {
    requests++;
    return response(headers);
  }
}
