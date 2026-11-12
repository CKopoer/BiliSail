import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:flutter_test/flutter_test.dart';

MediaTrack track({
  String uri = 'https://example.com/video',
  Map<String, String> headers = const {},
}) => MediaTrack(
  uri: Uri.parse(uri),
  requestPolicy: MediaRequestPolicy(headers: headers),
);

void main() {
  test(
    'media_kit rejects the same invalid sources before native allocation',
    () async {
      final PlayerEngine engine = MediaKitEngine();
      addTearDown(engine.dispose);
      for (final (source, options, kind) in [
        (
          DashPairSource(video: track(), audio: null),
          const OpenOptions(),
          PlayerFailureKind.invalidSource,
        ),
        (
          DashVideoSource(track()),
          const OpenOptions(),
          PlayerFailureKind.invalidSource,
        ),
        (
          ProgressiveSource(track()),
          const OpenOptions(rate: double.nan),
          PlayerFailureKind.invalidSource,
        ),
        (
          ProgressiveSource(track()),
          const OpenOptions(audioGainDb: 31),
          PlayerFailureKind.invalidSource,
        ),
        (
          ProgressiveSource(track()),
          const OpenOptions(maxBufferAhead: Duration(minutes: 3)),
          PlayerFailureKind.invalidSource,
        ),
        (
          ProgressiveSource(track(uri: 'https://user:password@example.com/v')),
          const OpenOptions(),
          PlayerFailureKind.invalidSource,
        ),
        (
          ProgressiveSource(track(headers: {'Cookie': 'private'})),
          const OpenOptions(),
          PlayerFailureKind.unsupportedHeaders,
        ),
        (
          ProgressiveSource(
            track(headers: {'Referer': 'ok\r\nCookie: private'}),
          ),
          const OpenOptions(),
          PlayerFailureKind.unsupportedHeaders,
        ),
        (
          DashPairSource(
            video: track(headers: {'Accept': 'a'}),
            audio: track(headers: {'accept': 'b'}),
          ),
          const OpenOptions(),
          PlayerFailureKind.unsupportedHeaders,
        ),
      ]) {
        await expectLater(
          engine.open(source, options),
          throwsA(isA<PlayerFailure>().having((e) => e.kind, 'kind', kind)),
        );
      }
    },
  );
  test('normalizes header names and preserves distinct silent, preview and audio requirements', () {
    final paired = ValidatedSource.validate(
      DashPairSource(
        video: track(headers: {'Referer': 'same'}),
        audio: track(headers: {'referer': 'same'}),
      ),
      const OpenOptions(),
      1,
    );
    expect(paired.audio, isNotNull);
    final silent = ValidatedSource.validate(
      DashPairSource(video: track(), audio: null, isIntentionallySilent: true),
      const OpenOptions(volume: 50),
      1,
    );
    expect(silent.silent, true);
    expect(silent.requiresVideo, true);
    final audio = ValidatedSource.validate(
      ProgressiveSource(track(), isAudioOnly: true),
      const OpenOptions(),
      1,
    );
    expect(audio.audioOnly, true);
    expect(audio.requiresVideo, false);
    final preview = ValidatedSource.validate(
      DashVideoSource(track()),
      const OpenOptions(volume: 0),
      1,
    );
    expect(preview.options.maxBufferAhead, const Duration(seconds: 5));
    final live = ValidatedSource.validate(
      ManifestSource(track(), isLive: true),
      const OpenOptions(rate: 2, startPosition: Duration(seconds: 5)),
      1,
    );
    expect(live.options.rate, 1);
    expect(live.options.startPosition, Duration.zero);
    expect(
      () => ValidatedSource.validate(
        ProgressiveSource(track(uri: 'content://provider/video')),
        const OpenOptions(),
        1,
      ),
      throwsA(isA<PlayerFailure>()),
    );
    expect(
      ValidatedSource.validate(
        ProgressiveSource(track(uri: 'content://provider/video')),
        const OpenOptions(),
        1,
        schemes: const {'content'},
      ).media.uri.scheme,
      'content',
    );
  });
}
