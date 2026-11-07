import 'package:fvp/mdk.dart' as mdk;

import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';

/// Copies only allowlisted scalar metadata; MDK maps and borrowed byte views
/// must not escape the native boundary (including the retired audio probe).
PlayerPlaybackInformation sampleFvpPlaybackInformation({
  required mdk.MediaInfo media,
  mdk.AudioCodecParameters? externalAudio,
  required bool silent,
  required bool videoDecoded,
  required bool audioDecoded,
  required bool videoRendered,
  String? videoDecoder,
  bool directSurface = false,
  VideoDimensions? outputDimensions,
  required int generation,
  required int positionMilliseconds,
  required int bufferedMilliseconds,
  required double audioGainDb,
}) {
  final video = media.video?.firstOrNull?.codec;
  final audio = silent
      ? null
      : externalAudio ?? media.audio?.firstOrNull?.codec;
  final (primaries, transfer) = switch (video?.colorSpace) {
    mdk.ColorSpace.bt709 => ('bt.709', 'bt.709'),
    mdk.ColorSpace.bt2100PQ => ('bt.2020', 'smpte2084'),
    mdk.ColorSpace.bt2100hlg => ('bt.2020', 'arib-std-b67'),
    mdk.ColorSpace.scrgb => ('bt.709', 'linear'),
    _ => (null, null),
  };
  final videoCodec = _identifier(video?.codec);
  final audioCodec = _identifier(audio?.codec);
  return PlayerPlaybackInformation(
    generation: generation,
    backend: 'fvp / MDK',
    diagnostics: PlayerDiagnostics(
      generation: generation,
      position: Duration(milliseconds: positionMilliseconds.clamp(0, 1 << 53)),
      hasDecodedVideo: videoDecoded,
      hasDecodedAudio: !silent && audioDecoded,
      hasVideoOutput: videoRendered,
      videoWidth: _positiveInt(video?.width),
      videoHeight: _positiveInt(video?.height),
      outputWidth: outputDimensions?.width,
      outputHeight: outputDimensions?.height,
      audioChannels: _positiveInt(audio?.channels),
      audioSampleRate: _positiveInt(audio?.sampleRate),
      videoCodec: videoCodec,
      audioCodec: audioCodec,
    ),
    hardwareDecoder: videoDecoded ? fvpDecoderName(videoDecoder) : null,
    videoCodec: videoCodec,
    audioCodec: audioCodec,
    sourceFps: _positiveNumber(video?.frameRate),
    videoNominalBitrate: _positiveNumber(video?.bitRate),
    audioNominalBitrate: _positiveNumber(audio?.bitRate),
    // media.bitRate belongs to the main demuxer, not an individual track.
    // Only a single-stream source can attribute it to video or audio.
    videoBitrate: media.streams == 1 && video != null
        ? _positiveNumber(media.bitRate)
        : null,
    audioBitrate: media.streams == 1 && video == null && audio != null
        ? _positiveNumber(media.bitRate)
        : null,
    pixelFormat: _identifier(video?.formatName),
    colorPrimaries: primaries,
    transferFunction: transfer,
    videoOutput: outputDimensions == null
        ? null
        : directSurface
        ? 'MediaCodec → Flutter.Texture (direct)'
        : 'Flutter.Texture',
    cacheSeconds: bufferedMilliseconds < 0 ? null : bufferedMilliseconds / 1000,
    audioGainDb: audioGainDb.isFinite ? audioGainDb : null,
  );
}

/// Decoder names come from successful decoder.video events, never preferences
/// or arbitrary native error messages. MFT identifies the decoder, not 0-copy.
String? fvpDecoderName(String? name) => switch (name) {
  'FFmpeg' || 'dav1d' => 'no',
  'MFT' ||
  'D3D11' ||
  'DXVA' ||
  'AMediaCodec' ||
  'VT' ||
  'VAAPI' ||
  'CUDA' ||
  'VDPAU' => name,
  _ => null,
};

String? _identifier(String? value) =>
    value != null && RegExp(r'^[A-Za-z0-9._+-]{1,64}$').hasMatch(value)
    ? value
    : null;

int? _positiveInt(int? value) => value != null && value > 0 ? value : null;
double? _positiveNumber(num? value) =>
    value != null && value.isFinite && value > 0 ? value.toDouble() : null;
