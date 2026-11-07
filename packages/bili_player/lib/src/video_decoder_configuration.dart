import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_contract.dart';

/// Prefer Android's MediaCodec path, with mpv's safe decoder fallback. A usable
/// Surface must be attached in on_load before the decoder is created.
/// The actual decoder still depends on the device and source codec.
mkv.VideoControllerConfiguration videoDecoderConfiguration({
  required bool isAndroid,
  required VideoDecodingMode decoding,
  AndroidVideoOutputMode androidOutput = AndroidVideoOutputMode.renderedTexture,
  bool Function()? usesDolbyVisionRenderer,
}) => isAndroid && usesDolbyVisionRenderer != null
    ? _AndroidSourceVideoConfiguration(
        decoding,
        androidOutput,
        usesDolbyVisionRenderer,
      )
    : mkv.VideoControllerConfiguration(
        // Software decoding still uses the GPU video output. Desktop defaults remain
        // owned by the SDK; Android follows PiliPlus's MediaCodec preference order.
        hwdec: decoding == VideoDecodingMode.software
            ? 'no'
            : isAndroid
            ? 'mediacodec,auto-safe'
            : null,
        vo:
            isAndroid &&
                decoding == VideoDecodingMode.automatic &&
                androidOutput == AndroidVideoOutputMode.directTexture
            ? 'mediacodec_embed'
            : null,
        androidAttachSurfaceAfterVideoParameters:
            isAndroid && decoding == VideoDecodingMode.automatic ? false : null,
      );

/// The pinned Android controller reads vo again when video parameters arrive.
/// Its configuration must follow the demuxed source before it sets up output.
final class _AndroidSourceVideoConfiguration
    extends mkv.VideoControllerConfiguration {
  _AndroidSourceVideoConfiguration(
    VideoDecodingMode decoding,
    this.androidOutput,
    this.usesDolbyVisionRenderer,
  ) : direct =
          decoding == VideoDecodingMode.automatic &&
          androidOutput == AndroidVideoOutputMode.directTexture,
      super(
        hwdec: decoding == VideoDecodingMode.software
            ? 'no'
            : 'mediacodec,auto-safe',
        // Keep the Surface available to the pre-decoder color hook, including
        // sources that will use software HEVC with gpu-next.
        androidAttachSurfaceAfterVideoParameters: false,
      );

  final bool Function() usesDolbyVisionRenderer;
  final AndroidVideoOutputMode androidOutput;
  final bool direct;

  @override
  String? get vo => usesDolbyVisionRenderer()
      ? 'gpu-next'
      : direct
      ? 'mediacodec_embed'
      : null;
}
