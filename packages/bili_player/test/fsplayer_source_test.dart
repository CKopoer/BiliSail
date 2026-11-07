import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fsplayer_source.dart';
import 'package:bili_player/src/fsplayer_input_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaTrack track(String path, {Map<String, String> headers = const {}}) =>
      MediaTrack(
        uri: Uri.parse('https://example.com/$path?one=1&token=private'),
        requestPolicy: MediaRequestPolicy(headers: headers),
      );
  DashPairSource pair({Duration? duration = const Duration(seconds: 180)}) =>
      DashPairSource(
        video: track('v.mp4'),
        audio: track('a.m4a'),
        duration: duration,
      );

  test(
    'DASH is one in-memory input with escaped URLs and resolver duration',
    () {
      final input = fsPlayerInput(pair(), const OpenOptions());
      expect(input.url, startsWith('data:application/dash+xml;base64,'));
      final xml = utf8.decode(base64Decode(input.url.split(',').last));
      expect(xml, contains('mediaPresentationDuration="PT180.0S"'));
      expect(xml, contains('v.mp4?one=1&amp;token=private'));
      expect(xml, contains('a.m4a?one=1&amp;token=private'));
      expect(input.audio, isTrue);
      expect(input.video, isTrue);
    },
  );
  test(
    'missing audio and missing DASH duration fail before creating a core',
    () {
      expect(
        () => fsPlayerInput(
          DashPairSource(video: track('v'), audio: null),
          const OpenOptions(),
        ),
        throwsA(isA<PlayerFailure>()),
      );
      expect(
        () => fsPlayerInput(pair(duration: null), const OpenOptions()),
        throwsA(isA<PlayerFailure>()),
      );
    },
  );
  test('native manifest route is opaque and closes with its lease', () async {
    final input = fsPlayerInput(pair(), const OpenOptions());
    final lease = await FsPlayerInputLease.open(input);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      expect(lease.url, isNot(contains('private')));
      expect(lease.url, isNot(contains('example.com')));
      final response = await (await client.getUrl(Uri.parse(lease.url)))
          .close();
      expect(response.statusCode, 200);
      expect(
        await utf8.decoder.bind(response).join(),
        contains('&amp;token=private'),
      );
      final unknown = await (await client.getUrl(
        Uri.parse(lease.url).replace(path: '/unknown'),
      )).close();
      expect(unknown.statusCode, 404);
      await unknown.drain<void>();
      await lease.close();
      await expectLater(
        Future(() async => (await client.getUrl(Uri.parse(lease.url))).close()),
        throwsA(isA<SocketException>()),
      );
    } finally {
      client.close(force: true);
      await lease.close();
    }
  });
  test('Dolby Vision Profile 5 uses the shared color fallback category', () {
    final dv = MediaTrack(
      uri: Uri.parse('https://example.com/v'),
      requestPolicy: MediaRequestPolicy(),
      codec: 'dvh1.05.06',
    );
    expect(
      () => fsPlayerInput(DashVideoSource(dv), const OpenOptions(volume: 0)),
      throwsA(
        isA<PlayerFailure>().having(
          (e) => e.kind,
          'color failure',
          PlayerFailureKind.unsupportedVideoColor,
        ),
      ),
    );
  });
  test('per-track headers must match and cannot inject HTTP fields', () {
    expect(
      () => fsPlayerInput(
        DashPairSource(
          video: track('v', headers: {'Referer': 'https://a'}),
          audio: track('a'),
          duration: const Duration(seconds: 10),
        ),
        const OpenOptions(),
      ),
      throwsA(isA<PlayerFailure>()),
    );
    for (final headers in [
      {'Cookie': 'secret'},
      {'Referer': 'https://a\r\nCookie: secret'},
    ]) {
      expect(
        () => fsPlayerInput(
          ProgressiveSource(track('v', headers: headers)),
          const OpenOptions(),
        ),
        throwsA(isA<PlayerFailure>()),
      );
    }
  });
  test('credentials and unsupported schemes are rejected', () {
    for (final url in [
      'https://user:secret@example.com/v.mp4',
      'ftp://example.com/v',
    ]) {
      expect(
        () => fsPlayerInput(
          ProgressiveSource(
            MediaTrack(
              uri: Uri.parse(url),
              requestPolicy: MediaRequestPolicy(),
            ),
          ),
          const OpenOptions(),
        ),
        throwsA(isA<PlayerFailure>()),
      );
    }
  });
  test('preview is muted and native parameters are bounded', () {
    expect(
      () => fsPlayerInput(
        DashVideoSource(track('v')),
        const OpenOptions(volume: 20),
      ),
      throwsA(isA<PlayerFailure>()),
    );
    expect(
      fsPlayerInput(
        DashVideoSource(track('v')),
        const OpenOptions(volume: 0),
      ).audio,
      isFalse,
    );
    for (final options in [
      OpenOptions(rate: double.nan),
      const OpenOptions(volume: -1),
      const OpenOptions(audioGainDb: 31),
      const OpenOptions(maxBufferAhead: Duration(minutes: 3)),
    ]) {
      expect(
        () => fsPlayerInput(pair(), options),
        throwsA(isA<PlayerFailure>()),
      );
    }
  });
}
