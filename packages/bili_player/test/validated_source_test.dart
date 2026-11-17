import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:bili_player/src/video_decoder_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

MediaTrack track({
  String uri = 'https://example.com/video',
  Map<String, String> headers = const {},
  bool isHdr = false,
}) => MediaTrack(
  uri: Uri.parse(uri),
  requestPolicy: MediaRequestPolicy(headers: headers),
  isHdr: isHdr,
);

void main() {
  test('HDR uses GPU tone mapping before output allocation without losing transport', () {
    const requested = OpenOptions(
      androidVideoOutput: AndroidVideoOutputMode.directTexture,
      startPosition: Duration(seconds: 17),
      play: true,
      rate: 1.5,
      volume: 36,
      audioGainDb: -3,
      openTimeout: Duration(seconds: 19),
      retainPresentation: true,
      maxBufferAhead: Duration(seconds: 45),
    );
    final video = track(isHdr: true);
    final audio = track(uri: 'https://example.com/audio');
    for (final source in <ResolvedMediaSource>[
      DashPairSource(video: video, audio: audio),
      ProgressiveSource(video),
      ManifestSource(video),
    ]) {
      final plan = ValidatedSource.validate(source, requested, 1);
      final options = plan.options;
      expect(plan.source, same(source));
      expect(plan.media, same(video));
      if (source is DashPairSource) expect(plan.audio, same(audio));
      expect(
        options.androidVideoOutput,
        AndroidVideoOutputMode.renderedTexture,
      );
      final decoder = videoDecoderConfiguration(
        isAndroid: true,
        debugMode: false,
        decoding: options.videoDecoding,
        androidOutput: options.androidVideoOutput,
      );
      expect(decoder.vo, isNull); // SDK default gpu, not mediacodec_embed.
      expect(decoder.hwdec, 'mediacodec,auto-safe');
      expect(options.startPosition, requested.startPosition);
      expect(options.play, requested.play);
      expect(options.rate, requested.rate);
      expect(options.volume, requested.volume);
      expect(options.audioGainDb, requested.audioGainDb);
      expect(options.openTimeout, requested.openTimeout);
      expect(options.retainPresentation, requested.retainPresentation);
      expect(options.maxBufferAhead, requested.maxBufferAhead);
    }
    expect(requested.androidVideoOutput, AndroidVideoOutputMode.directTexture);
  });

  test(
    'SDR to HDR to SDR restores direct output and software stays software',
    () {
      for (final decoding in VideoDecodingMode.values) {
        final requested = OpenOptions(
          androidVideoOutput: AndroidVideoOutputMode.directTexture,
          videoDecoding: decoding,
        );
        final outputs = <AndroidVideoOutputMode>[];
        for (final hdr in [false, true, false]) {
          final plan = ValidatedSource.validate(
            ProgressiveSource(
              track(uri: 'file:///offline/video.mp4', isHdr: hdr),
            ),
            requested,
            1,
          );
          outputs.add(plan.options.androidVideoOutput);
          final decoder = videoDecoderConfiguration(
            isAndroid: true,
            debugMode: false,
            decoding: plan.options.videoDecoding,
            androidOutput: plan.options.androidVideoOutput,
          );
          expect(
            decoder.hwdec,
            decoding == VideoDecodingMode.software
                ? 'no'
                : 'mediacodec,auto-safe',
          );
        }
        expect(outputs, [
          AndroidVideoOutputMode.directTexture,
          AndroidVideoOutputMode.renderedTexture,
          AndroidVideoOutputMode.directTexture,
        ]);
      }
    },
  );

  test(
    'HDR preview and live output retain existing buffer and timeline rules',
    () {
      const requested = OpenOptions(
        androidVideoOutput: AndroidVideoOutputMode.directTexture,
        startPosition: Duration(seconds: 17),
        rate: 2,
        volume: 0,
      );
      final video = track(isHdr: true);
      final preview = ValidatedSource.validate(
        DashVideoSource(video),
        requested,
        1,
      );
      expect(
        preview.options.androidVideoOutput,
        AndroidVideoOutputMode.renderedTexture,
      );
      expect(preview.options.maxBufferAhead, const Duration(seconds: 5));
      final live = ValidatedSource.validate(
        ManifestSource(video, isLive: true),
        requested,
        1,
      );
      expect(
        live.options.androidVideoOutput,
        AndroidVideoOutputMode.renderedTexture,
      );
      expect(live.options.startPosition, Duration.zero);
      expect(live.options.rate, 1);
      final audio = ValidatedSource.validate(
        ProgressiveSource(video, isAudioOnly: true),
        requested,
        1,
      );
      expect(audio.options, same(requested));
    },
  );

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
