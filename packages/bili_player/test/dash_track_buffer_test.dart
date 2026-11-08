import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/src/dash_track_buffer.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:bili_player/src/player_diagnostics.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mp4_buffer_index_test.dart' show indexedMedia;

void main() {
  late HttpServer origin;
  late HttpClient reader;
  late ValidatedSource plan;
  final requests = <(String, int)>[];
  late Uint8List bytes;
  Future<void> Function(HttpRequest, int, int)? respond;

  setUp(() async {
    bytes = indexedMedia();
    requests.clear();
    respond = null;
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      request.response.bufferOutput = false;
      final range = RegExp(r'bytes=(\d+)-(\d+)')
          .firstMatch(request.headers.value('range') ?? '')!;
      final start = int.parse(range[1]!);
      final end = int.parse(range[2]!).clamp(start, bytes.length - 1);
      requests.add((request.uri.path, start));
      if (respond != null) {
        await respond!(request, start, end);
      } else {
        request.response
          ..statusCode = 206
          ..headers.set('Content-Range', 'bytes $start-$end/${bytes.length}')
          ..headers.set('ETag', '"fixture"')
          ..contentLength = end - start + 1
          ..add(bytes.sublist(start, end + 1));
        await request.response.close();
      }
    });
    reader = HttpClient();
    MediaTrack track(String name) => MediaTrack(
      uri: Uri.parse('http://127.0.0.1:${origin.port}/$name'),
      requestPolicy: MediaRequestPolicy(
        headers: {'Referer': 'https://example.test'},
      ),
    );
    plan = ValidatedSource.validate(
      DashPairSource(video: track('video'), audio: track('audio')),
      const OpenOptions(),
      1,
    );
  });
  tearDown(() async {
    reader.close(force: true);
    await origin.close(force: true);
  });
  Future<Uint8List> read(MediaTrack track, {int start = 0, int? end}) async {
    final request = await reader.getUrl(track.uri);
    final partial = start > 0 || end != null;
    if (partial) request.headers.set('Range', 'bytes=$start-${end ?? ''}');
    final response = await request.close();
    expect(response.statusCode, partial ? 206 : 200);
    final data = Uint8List.fromList(
      await response.fold<List<int>>([], (a, b) => a..addAll(b)),
    );
    // A client can consume the final bytes before the server's flush future
    // resumes to acknowledge their delivery.
    await Future<void>.delayed(Duration.zero);
    return data;
  }

  Future<DashTrackBuffer> create({
    int capacity = 1024 * 1024,
    void Function(NativeErrorSummary)? onFailure,
  }) async {
    final buffer = await DashTrackBuffer.create(
      plan,
      inactivityTimeout: const Duration(milliseconds: 60),
      recoveryTimeout: const Duration(seconds: 1),
      videoCapacity: capacity,
      audioCapacity: capacity,
      onFailure: onFailure,
    );
    addTearDown(buffer.close);
    return buffer;
  }

  Future<void> indexed(DashTrackBuffer buffer, {bool audio = true}) async {
    for (var i = 0; i < 200; i++) {
      final ends = buffer.buffered(Duration.zero);
      if (audio ? ends.audio > Duration.zero : ends.video > Duration.zero) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('MP4 index did not become available');
  }

  test(
    'common buffer is the smaller contiguous track and native window',
    () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      await read(local.media);
      final indexLength = bytes.length - 400;
      await read(local.audio!, end: indexLength + 199);
      await indexed(buffer);
      await indexed(buffer, audio: false);
      expect(buffer.buffered(Duration.zero), (
        video: const Duration(seconds: 8),
        audio: const Duration(seconds: 4),
      ));
      expect(
        buffer.commonBuffered(Duration.zero, const Duration(seconds: 7)),
        const Duration(seconds: 4),
      );
      expect(
        buffer.commonBuffered(Duration.zero, const Duration(seconds: 3)),
        const Duration(seconds: 3),
      );
      expect(
        buffer.commonBuffered(
          const Duration(seconds: 5),
          const Duration(seconds: 8),
        ),
        const Duration(seconds: 5),
      );
    },
  );
  for (final stalledTrack in ['audio', 'video']) {
    test('$stalledTrack inactivity resumes only its missing bytes', () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      var stalled = false;
      respond = (request, start, end) async {
        expect(request.headers.value('Referer'), 'https://example.test');
        request.response
          ..statusCode = 206
          ..headers.set('ETag', '"fixture"')
          ..headers.set('Content-Range', 'bytes $start-$end/${bytes.length}')
          ..contentLength = end - start + 1;
        if (request.uri.path == '/$stalledTrack' && !stalled) {
          stalled = true;
          request.response.add(bytes.sublist(start, start + 137));
          await request.response.flush();
          // No more bytes: the proxy must reconnect before native playback
          // reaches this track's buffer end, without restarting its reader.
          return;
        }
        if (request.uri.path == '/$stalledTrack') {
          expect(start, 137);
          expect(request.headers.value('If-Range'), '"fixture"');
        }
        request.response.add(bytes.sublist(start, end + 1));
        await request.response.close();
      };
      final result = await Future.wait([read(local.media), read(local.audio!)]);
      await indexed(buffer);
      await indexed(buffer, audio: false);
      expect(result, [bytes, bytes]);
      expect(requests.where((r) => r.$1 == '/$stalledTrack').map((r) => r.$2), [
        0,
        137,
      ]);
      expect(requests.where((r) => r.$1 != '/$stalledTrack').length, 1);
      expect(
        buffer.commonBuffered(Duration.zero, const Duration(seconds: 8)),
        const Duration(seconds: 8),
      );
    });
  }
  test(
    'changed object and ignored resume range cannot concatenate data',
    () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      respond = (request, start, end) async {
        if (start > 0) {
          request.response
            ..statusCode = 200
            ..contentLength = bytes.length
            ..add(bytes);
        } else {
          request.response
            ..statusCode = 206
            ..headers.set('ETag', '"fixture"')
            ..headers.set('Content-Range', 'bytes 0-$end/${bytes.length}')
            ..contentLength = end + 1
            ..add(bytes.sublist(0, 137));
          await request.response.flush();
          return;
        }
        await request.response.close();
      };
      await expectLater(read(local.audio!), throwsA(isA<HttpException>()));
      expect(requests.length, 2);
      expect(buffer.buffered(Duration.zero).audio, Duration.zero);
    },
  );
  test('full cache is idle; repeated local reads need no reconnect', () async {
    final buffer = await create();
    final local = buffer.prepare(plan);
    expect(await read(local.audio!), bytes);
    expect(await read(local.audio!), bytes);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests, [('/audio', 0)]);
  });
  test(
    'cancelled seek readers release admission without retrying old ranges',
    () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      respond = (request, start, end) async {
        /* Retired native request. */
      };
      for (var i = 0; i < 12; i++) {
        final reading = read(local.media)
            .then<void>((_) {}, onError: (Object _) {});
        for (var wait = 0; wait < 100 && requests.length <= i; wait++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(requests.length, i + 1);
        buffer.cancelReads();
        await reading.timeout(const Duration(seconds: 1));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests.length, 12);
      respond = null;
      expect(await read(local.media), bytes);
      expect(await read(local.audio!), bytes);
    },
  );
  test(
    'filling a gap adjacent to a cached tail ends at the requested byte',
    () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      expect(
        await read(local.audio!, start: 400, end: 479),
        bytes.sublist(400),
      );
      final prefix = await read(
        local.audio!,
        end: 399,
      ).timeout(const Duration(seconds: 2));
      expect(prefix, bytes.sublist(0, 400));
      expect(requests.map((request) => request.$2), [400, 0]);
    },
  );
  test(
    'high bitrate audio retains more than the minimum byte allowance',
    () async {
      bytes = indexedMedia(count: 9, segmentSize: 1024 * 1024);
      final audio = plan.audio!;
      final highQuality = ValidatedSource.validate(
        DashPairSource(
          video: plan.media,
          audio: MediaTrack(
            uri: audio.uri,
            requestPolicy: audio.requestPolicy,
            bandwidth: 1000000,
          ),
        ),
        plan.options,
        1,
      );
      final buffer = await DashTrackBuffer.create(highQuality);
      addTearDown(buffer.close);
      final local = buffer.prepare(highQuality);
      expect((await read(local.audio!)).length, bytes.length);
      await indexed(buffer);
      expect(buffer.buffered(Duration.zero).audio, const Duration(seconds: 18));
    },
  );
  test('transient HTTP failures have a finite retry budget', () async {
    final failures = <NativeErrorSummary>[];
    final buffer = await create(onFailure: failures.add);
    final local = buffer.prepare(plan);
    respond = (request, start, end) async {
      request.response.statusCode = 503;
      await request.response.close();
    };
    final request = await reader.getUrl(local.audio!.uri);
    final response = await request.close();
    expect(response.statusCode, 502);
    await response.drain<void>();
    expect(requests.length, 4);
    expect(failures.single.httpStatus, 503);
    expect(failures.single.cause, NativeErrorCause.http);
    expect(buffer.buffered(Duration.zero).audio, Duration.zero);
  });
  test(
    'a different ETag on resume fails without replaying the track',
    () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      respond = (request, start, end) async {
        request.response
          ..statusCode = 206
          ..headers.set('Content-Range', 'bytes $start-$end/${bytes.length}')
          ..headers.set('ETag', start == 0 ? '"old"' : '"new"')
          ..contentLength = end - start + 1;
        if (start == 0) {
          request.response.add(bytes.sublist(0, 137));
          await request.response.flush();
          return;
        }
        request.response.add(bytes.sublist(start, end + 1));
        await request.response.close();
      };
      await expectLater(read(local.audio!), throwsA(isA<HttpException>()));
      expect(requests.map((r) => r.$2), [0, 137]);
    },
  );
  test(
    'evicting retry bytes preserves the buffer already delivered to native',
    () async {
      final buffer = await create(capacity: 150);
      final local = buffer.prepare(plan);
      await read(local.media);
      for (
        var i = 0;
        i < 200 &&
            buffer.buffered(Duration.zero).video < const Duration(seconds: 8);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(buffer.buffered(Duration.zero).video, const Duration(seconds: 8));
    },
  );
  test('unknown indexes preserve native buffer evidence', () async {
    bytes = Uint8List(64);
    final buffer = await create();
    final local = buffer.prepare(plan);
    await read(local.media);
    await read(local.audio!);
    expect(
      buffer.commonBuffered(
        const Duration(seconds: 1),
        const Duration(seconds: 9),
      ),
      const Duration(seconds: 9),
    );
  });
  test('delivered ranges keep gaps until the missing bytes arrive', () async {
    final buffer = await create(capacity: 150);
    final local = buffer.prepare(plan);
    final indexLength = bytes.length - 400;
    await read(local.audio!, end: indexLength + 99);
    await read(local.audio!, start: indexLength + 200);
    await indexed(buffer);
    expect(buffer.buffered(Duration.zero).audio, const Duration(seconds: 2));
    await read(local.audio!, start: indexLength + 100, end: indexLength + 199);
    expect(buffer.buffered(Duration.zero).audio, const Duration(seconds: 8));
  });
  test(
    'closing cancels a read waiting for headers and is a shared barrier',
    () async {
      final buffer = await create();
      final local = buffer.prepare(plan);
      final entered = Completer<void>();
      respond = (request, start, end) async {
        if (!entered.isCompleted) entered.complete();
      };
      final reading = reader
          .getUrl(local.audio!.uri)
          .then((request) => request.close())
          .then<void>(
            (response) => response.drain<void>(),
            onError: (Object _) {},
          );
      await entered.future;
      final closing = buffer.close();
      expect(identical(closing, buffer.close()), isTrue);
      await closing.timeout(const Duration(seconds: 1));
      await reading;
      final count = requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(requests.length, count);
    },
  );
}
