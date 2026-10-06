import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'video-only DASH requires explicit mute and a positive startup budget',
    () async {
      for (final options in [
        const OpenOptions(volume: 100),
        const OpenOptions(volume: 0, openTimeout: Duration.zero),
      ]) {
        final engine = MediaKitEngine();
        await expectLater(
          engine.open(
            DashVideoSource(
              MediaTrack(
                uri: Uri.parse('https://cdn.example/video.m4s'),
                requestPolicy: MediaRequestPolicy(),
              ),
            ),
            options,
          ),
          throwsA(
            isA<PlayerFailure>().having(
              (failure) => failure.kind,
              'kind',
              PlayerFailureKind.invalidSource,
            ),
          ),
        );
        expect(engine.inspectDiagnostics().hasDecodedVideo, false);
        await engine.dispose();
      }
    },
  );
  test(
    'diagnostics before native open contain no media URI or headers',
    () async {
      final engine = MediaKitEngine();
      final diagnostics = engine.inspectDiagnostics();
      expect(diagnostics.hasDecodedVideo, isFalse);
      expect(diagnostics.hasDecodedAudio, isFalse);
      expect(diagnostics.position, Duration.zero);
      expect(diagnostics.toString(), isNot(contains('http')));
      await engine.dispose();
    },
  );

  test(
    'rejects a DASH pair without confirmed audio before creating native player',
    () async {
      final engine = MediaKitEngine();
      final track = MediaTrack(
        uri: Uri.parse('https://cdn.example/video.m4s?token=secret'),
        requestPolicy: MediaRequestPolicy(),
      );
      await expectLater(
        engine.open(
          DashPairSource(video: track, audio: null),
          const OpenOptions(),
        ),
        throwsA(
          isA<PlayerFailure>().having(
            (e) => e.kind,
            'kind',
            PlayerFailureKind.invalidSource,
          ),
        ),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      await engine.dispose();
    },
  );

  test(
    'rejects unequal DASH request headers without exposing a signed URL',
    () async {
      final engine = MediaKitEngine();
      final video = MediaTrack(
        uri: Uri.parse('https://cdn.example/video.m4s?token=video-secret'),
        requestPolicy: MediaRequestPolicy(
          headers: {'Referer': 'https://www.bilibili.com'},
        ),
      );
      final audio = MediaTrack(
        uri: Uri.parse('https://cdn.example/audio.m4s?token=audio-secret'),
        requestPolicy: MediaRequestPolicy(
          headers: {'Referer': 'https://other.example'},
        ),
      );
      final failure = await engine
          .open(DashPairSource(video: video, audio: audio), const OpenOptions())
          .then<PlayerFailure>(
            (_) => throw StateError('expected failure'),
            onError: (Object error) => error as PlayerFailure,
          );
      expect(failure.kind, PlayerFailureKind.unsupportedHeaders);
      expect(failure.toString(), isNot(contains('secret')));
      await engine.dispose();
    },
  );

  test(
    'rejects credential headers that could leak on native redirects',
    () async {
      final engine = MediaKitEngine();
      final source = ProgressiveSource(
        MediaTrack(
          uri: Uri.parse('https://cdn.example/video.mp4'),
          requestPolicy: MediaRequestPolicy(
            headers: {'Cookie': 'SESSDATA=secret'},
          ),
        ),
      );
      await expectLater(
        engine.open(source, const OpenOptions()),
        throwsA(
          isA<PlayerFailure>().having(
            (e) => e.kind,
            'kind',
            PlayerFailureKind.unsupportedHeaders,
          ),
        ),
      );
      await engine.dispose();
    },
  );
}
