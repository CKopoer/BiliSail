import 'dart:convert';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fsplayer_source.dart';
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
