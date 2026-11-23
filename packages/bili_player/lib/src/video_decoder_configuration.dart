import 'package:flutter/foundation.dart' show kDebugMode;
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
  bool debugMode = kDebugMode,
}) => isAndroid && usesDolbyVisionRenderer != null
    ? _AndroidSourceVideoConfiguration(
        decoding,
        androidOutput,
        usesDolbyVisionRenderer,
        debugMode,
      )
    : mkv.VideoControllerConfiguration(
        // Software decoding still uses the GPU video output. Desktop defaults remain
        // owned by the SDK; Android follows PiliPlus's MediaCodec preference order.
        enableAndroidSurfaceProducer: false,
        hwdec: decoding == VideoDecodingMode.software
            ? 'no'
            : isAndroid
            ? debugMode
                  ? 'auto-safe'
                  : 'mediacodec,auto-safe'
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
    bool debugMode,
  ) : direct =
          decoding == VideoDecodingMode.automatic &&
          androidOutput == AndroidVideoOutputMode.directTexture,
      super(
        enableAndroidSurfaceProducer: false,
        hwdec: decoding == VideoDecodingMode.software
            ? 'no'
            : debugMode
            ? 'auto-safe'
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

  @override
  mkv.VideoControllerConfiguration copyWith({
    String? vo,
    String? hwdec,
    double? scale,
    int? width,
    int? height,
    bool? enableHardwareAcceleration,
    bool? enableAndroidSurfaceProducer,
    bool? androidAttachSurfaceAfterVideoParameters,
  }) => _ResolvedAndroidConfiguration(
    usesDolbyVisionRenderer,
    super.copyWith(
      vo: vo,
      hwdec: hwdec,
      scale: scale,
      width: width,
      height: height,
      enableHardwareAcceleration: enableHardwareAcceleration,
      enableAndroidSurfaceProducer: enableAndroidSurfaceProducer,
      androidAttachSurfaceAfterVideoParameters:
          androidAttachSurfaceAfterVideoParameters,
    ),
  );
}

/// The SDK resolves its GPU default during controller creation. Keep the
/// demuxed Dolby Vision choice available when the surface is later rebound.
final class _ResolvedAndroidConfiguration
    extends mkv.VideoControllerConfiguration {
  _ResolvedAndroidConfiguration(
    this.useDolby,
    mkv.VideoControllerConfiguration base,
  ) : super(
        vo: base.vo,
        hwdec: base.hwdec,
        width: base.width,
        height: base.height,
        scale: base.scale,
        enableHardwareAcceleration: base.enableHardwareAcceleration,
        enableAndroidSurfaceProducer: base.enableAndroidSurfaceProducer,
        androidAttachSurfaceAfterVideoParameters:
            base.androidAttachSurfaceAfterVideoParameters,
      );
  final bool Function() useDolby;
  @override
  String? get vo => useDolby() ? 'gpu-next' : super.vo;
}
