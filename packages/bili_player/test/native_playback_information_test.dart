import 'dart:async';

import 'package:bili_player/src/native_playback_information.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const diagnostics = PlayerDiagnostics(
    generation: 3,
    position: Duration.zero,
    hasDecodedVideo: true,
    hasDecodedAudio: true,
  );

  test(
    'native information preserves units, signed sync and zero drops',
    () async {
      final properties = {
        'hwdec-current': 'd3d11va',
        'video-format': 'h264',
        'audio-codec-name': 'aac',
        'container-fps': '59.94',
        'video-bitrate': '12000000',
        'audio-bitrate': '192000',
        'avsync': '-0.125',
        'frame-drop-count': '0',
        'decoder-frame-drop-count': '3',
        'demuxer-cache-state/fw-bytes': '1048576',
        'cache-speed': '2097152',
        'demuxer-cache-duration': '12.5',
        'video-params/gamma': 'pq',
      };
      final info = await sampleNativePlaybackInformation(
        read: (name) async => properties[name],
        diagnostics: diagnostics,
        audioGainDb: -3,
      );
      expect(info.generation, 3);
      expect(info.hardwareDecoder, 'd3d11va');
      expect(info.sourceFps, 59.94);
      expect(info.videoBitrate, 12000000);
      expect(info.audioBitrate, 192000);
      expect(info.avSyncSeconds, -.125);
      expect(info.frameDrops, 0);
      expect(info.decoderDrops, 3);
      expect(info.cacheBytes, 1048576);
      expect(info.cacheSpeed, 2097152);
      expect(info.cacheSeconds, 12.5);
      expect(info.transferFunction, 'pq');
      expect(info.audioGainDb, -3);
      expect(info.withGeneration(9).generation, 9);
      expect(info.withGeneration(9).diagnostics?.generation, 9);
      expect(info.withGeneration(9).avSyncSeconds, -.125);
    },
  );

  test(
    'missing, nonfinite, negative and unsafe values stay unavailable',
    () async {
      final info = await sampleNativePlaybackInformation(
        read: (name) async => switch (name) {
          'hwdec-current' => 'https://host/?token=private',
          'video-format' => 'Cookie: secret',
          'container-fps' => 'NaN',
          'estimated-vf-fps' => 'Infinity',
          'audio-bitrate' => '-1',
          'frame-drop-count' => '-2',
          'cache-speed' => throw StateError('native property unavailable'),
          _ => null,
        },
        diagnostics: diagnostics,
        audioGainDb: 0,
      );
      expect(info.hardwareDecoder, isNull);
      expect(info.videoCodec, isNull);
      expect(info.sourceFps, isNull);
      expect(info.outputFps, isNull);
      expect(info.audioBitrate, isNull);
      expect(info.frameDrops, isNull);
      expect(info.cacheSpeed, isNull);
    },
  );

  testWidgets(
    'one stalled property is bounded and does not hide other values',
    (tester) async {
      final stalled = Completer<String?>();
      PlayerPlaybackInformation? result;
      final sampling = sampleNativePlaybackInformation(
        read: (name) => name == 'hwdec-current'
            ? stalled.future
            : Future.value(name == 'frame-drop-count' ? '5' : null),
        diagnostics: diagnostics,
        audioGainDb: 0,
      ).then((info) => result = info);
      await tester.pump(const Duration(seconds: 1));
      await sampling;
      expect(result?.hardwareDecoder, isNull);
      expect(result?.frameDrops, 5);
      stalled.complete(null);
    },
  );
}
