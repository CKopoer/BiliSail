import 'package:bili_player/src/android_dolby_backend.dart';
import 'package:bili_player/src/dolby_audio_output.dart';
import 'package:bili_player/src/playback_backend.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaTrack offline([String? audio]) => MediaTrack(
    uri: Uri.file('/downloads/video.mkv'),
    codec: 'hevc',
    embeddedAudioCodec: audio,
    requestPolicy: MediaRequestPolicy(),
  );

  test('only candidate tracks try the Android platform decoder', () {
    bool candidate(
      MediaTrack track, [
      OpenOptions options = const OpenOptions(),
    ]) => AndroidDolbyBackend.candidate(
      ValidatedSource.validate(ProgressiveSource(track), options, 1),
    );
    expect(candidate(offline('ec-3')), isTrue);
    expect(candidate(offline()), isTrue);
    expect(candidate(offline('mp4a.40.2')), isFalse);
    expect(
      candidate(offline('ec-3'), const OpenOptions(audioGainDb: -3)),
      isFalse,
    );
    expect(
      candidate(
        offline('ec-3'),
        const OpenOptions(videoDecoding: VideoDecodingMode.software),
      ),
      isFalse,
    );
  });

  testWidgets('a rejected Android source releases its paused platform player', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/dolby_player');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'state' ? {'failed': true} : null;
    });
    try {
      final plan = ValidatedSource.validate(
        ProgressiveSource(offline()),
        const OpenOptions(),
        1,
      );
      expect(
        await AndroidDolbyBackend.tryOpen(
          plan,
          PlaybackOperation(1, const Duration(seconds: 5)),
        ),
        isNull,
      );
      expect(calls, ['open', 'state', 'release']);
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });

  testWidgets('encoded output follows endpoint, volume, gain and speed', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/audio_passthrough');
    var capable = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => capable,
    );
    final writes = <String>[];
    final output = WindowsDolbyOutput(
      write: (key, value) => writes.add('$key=$value'),
      isCurrent: () => true,
      rate: 1,
      volume: 100,
      gain: 0,
    );
    try {
      await output.start();
      expect(writes, ['audio-spdif=eac3']);
      output.volume = 0;
      output.apply();
      output.volume = 100;
      output.rate = 2;
      output.apply();
      output.rate = 1;
      output.gain = -3;
      output.apply();
      expect(writes, ['audio-spdif=eac3', 'audio-spdif=']);
      output.gain = 0;
      output.apply();
      capable = false;
      await tester.pump(const Duration(seconds: 3));
      expect(writes, [
        'audio-spdif=eac3',
        'audio-spdif=',
        'audio-spdif=eac3',
        'audio-spdif=',
      ]);
    } finally {
      output.stop();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });
}
