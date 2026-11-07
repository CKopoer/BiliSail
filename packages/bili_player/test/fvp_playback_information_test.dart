import 'package:bili_player/src/fvp_playback_information.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;

void main() {
  late mdk.MediaInfo media;
  setUp(() {
    media = mdk.MediaInfo()
      ..streams = 1
      ..bitRate = 2400000
      ..video = [
        mdk.VideoStreamInfo()
          ..codec = (mdk.VideoCodecParameters()
            ..codec = 'h264'
            ..width = 1920
            ..height = 1080
            ..frameRate = 59.94
            ..bitRate = 2000000
            ..formatName = 'yuv420p'
            ..colorSpace = mdk.ColorSpace.bt2100PQ),
      ];
  });

  PlayerPlaybackInformation sample({
    mdk.AudioCodecParameters? audio,
    bool silent = false,
    int buffered = 2500,
  }) => sampleFvpPlaybackInformation(
    media: media,
    externalAudio: audio,
    silent: silent,
    videoDecoded: true,
    audioDecoded: audio != null,
    videoRendered: true,
    videoDecoder: 'D3D11',
    outputDimensions: const VideoDimensions(1080, 1920),
    generation: 7,
    positionMilliseconds: 1250,
    bufferedMilliseconds: buffered,
    audioGainDb: -3,
  );

  test('copies native metadata, readiness, texture size and buffer units', () {
    final info = sample();
    expect(info.generation, 7);
    expect(info.hardwareDecoder, 'D3D11');
    expect(info.videoCodec, 'h264');
    expect(info.sourceFps, 59.94);
    expect(info.videoBitrate, 2400000);
    expect(info.videoNominalBitrate, 2000000);
    expect(info.pixelFormat, 'yuv420p');
    expect(info.colorPrimaries, 'bt.2020');
    expect(info.transferFunction, 'smpte2084');
    expect(info.cacheSeconds, 2.5);
    expect(info.videoOutput, 'Flutter.Texture');
    expect(info.diagnostics?.position, const Duration(milliseconds: 1250));
    expect(info.diagnostics?.videoWidth, 1920);
    expect(info.diagnostics?.outputWidth, 1080);
    expect(info.diagnostics?.hasDecodedVideo, true);
    expect(info.diagnostics?.hasVideoOutput, true);
    expect(info.audioGainDb, -3);
    // Unsupported observations must remain unavailable, not made-up zeros.
    expect(info.outputFps, isNull);
    expect(info.cacheBytes, isNull);
    expect(info.cacheSpeed, isNull);
    expect(info.avSyncSeconds, isNull);
    expect(info.audioPositionSeconds, isNull);
    expect(info.videoPositionSeconds, isNull);
    expect(info.frameDrops, isNull);
    expect(info.decoderDrops, isNull);
  });

  test(
    'DASH keeps companion metadata distinct from the main demux bitrate',
    () {
      final audio = mdk.AudioCodecParameters()
        ..codec = 'aac'
        ..channels = 2
        ..sampleRate = 48000
        ..bitRate = 128000;
      final info = sample(audio: audio);
      expect(info.audioCodec, 'aac');
      expect(info.audioNominalBitrate, 128000);
      expect(info.audioBitrate, isNull);
      expect(info.diagnostics?.audioChannels, 2);
      expect(info.diagnostics?.audioSampleRate, 48000);
      expect(info.diagnostics?.hasDecodedAudio, true);
      final remapped = info.withGeneration(8);
      expect(remapped.videoNominalBitrate, 2000000);
      expect(remapped.audioNominalBitrate, 128000);
      expect(remapped.diagnostics?.generation, 8);
      final muted = sample(audio: audio, silent: true);
      expect(muted.audioCodec, isNull);
      expect(muted.diagnostics?.audioSampleRate, isNull);
      expect(muted.diagnostics?.hasDecodedAudio, false);
    },
  );

  test('audio-only and multiplexed media do not invent per-track bitrates', () {
    media.audio = [mdk.AudioStreamInfo()..codec.codec = 'aac'];
    media.streams = 2;
    expect(sample().videoBitrate, isNull);
    expect(sample().audioBitrate, isNull);
    media.video = null;
    media.streams = 1;
    final info = sample();
    expect(info.videoCodec, isNull);
    expect(info.audioCodec, 'aac');
    expect(info.videoBitrate, isNull);
    expect(info.audioBitrate, 2400000);
  });

  test('rejects invalid numbers and native text, preserves zero buffer', () {
    final video = media.video!.single.codec
      ..codec = 'https://example.com/private?token=secret'
      ..formatName = 'private/path'
      ..frameRate = double.nan
      ..bitRate = -1
      ..width = 0
      ..colorSpace = mdk.ColorSpace.unknown;
    media.metadata['url'] = 'https://private.invalid';
    final info = sample(buffered: 0);
    expect(info.videoCodec, isNull);
    expect(info.pixelFormat, isNull);
    expect(info.sourceFps, isNull);
    expect(info.videoNominalBitrate, isNull);
    expect(info.diagnostics?.videoWidth, isNull);
    expect(info.colorPrimaries, isNull);
    expect(info.transferFunction, isNull);
    expect(info.cacheSeconds, 0);
    expect(sample(buffered: -1).cacheSeconds, isNull);
    video.frameRate = double.infinity;
    expect(sample().sourceFps, isNull);
    expect(fvpDecoderName('FFmpeg'), 'no');
    expect(fvpDecoderName('dav1d'), 'no');
    expect(fvpDecoderName('MFT'), 'MFT');
    expect(fvpDecoderName('open'), isNull);
    expect(fvpDecoderName('https://private.invalid'), isNull);
  });
}
