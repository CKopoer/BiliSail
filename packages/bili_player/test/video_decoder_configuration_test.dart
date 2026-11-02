import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/video_decoder_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android source color mode changes before late video parameter setup',
    () {
      for (final decoding in VideoDecodingMode.values) {
        var dolby = false;
        final configuration = videoDecoderConfiguration(
          isAndroid: true,
          decoding: decoding,
          usesDolbyVisionRenderer: () => dolby,
        );
        expect(configuration.vo, isNull);
        expect(
          configuration.hwdec,
          decoding == VideoDecodingMode.automatic
              ? 'mediacodec,auto-safe'
              : 'no',
        );
        expect(configuration.androidAttachSurfaceAfterVideoParameters, isFalse);
        dolby = true;
        expect(configuration.vo, 'gpu-next');
      }
      final nextSource = videoDecoderConfiguration(
        isAndroid: true,
        decoding: VideoDecodingMode.automatic,
        usesDolbyVisionRenderer: () => false,
      );
      expect(nextSource.vo, isNull);
      expect(nextSource.hwdec, 'mediacodec,auto-safe');
    },
  );

  test('Android automatic decoding attaches before decoder creation', () {
    final configuration = videoDecoderConfiguration(
      isAndroid: true,
      decoding: VideoDecodingMode.automatic,
    );
    expect(configuration.hwdec, 'mediacodec,auto-safe');
    expect(configuration.androidAttachSurfaceAfterVideoParameters, isFalse);
    expect(configuration.enableHardwareAcceleration, isTrue);
    expect(configuration.vo, isNull);
  });

  test(
    'software decoding retains the GPU output and deferred Surface size',
    () {
      for (final isAndroid in [true, false]) {
        final configuration = videoDecoderConfiguration(
          isAndroid: isAndroid,
          decoding: VideoDecodingMode.software,
        );
        expect(configuration.hwdec, 'no');
        expect(configuration.vo, isNull);
        expect(configuration.enableHardwareAcceleration, isTrue);
        expect(configuration.androidAttachSurfaceAfterVideoParameters, isNull);
      }
    },
  );

  test('desktop automatic decoding retains SDK defaults', () {
    final configuration = videoDecoderConfiguration(
      isAndroid: false,
      decoding: VideoDecodingMode.automatic,
    );
    expect(configuration.hwdec, isNull);
    expect(configuration.vo, isNull);
    expect(configuration.androidAttachSurfaceAfterVideoParameters, isNull);
  });
}
