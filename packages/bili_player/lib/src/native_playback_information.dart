import 'player_diagnostics.dart';
import 'player_playback_information.dart';

/// Fixed property allowlist: never expose raw native text or arbitrary maps.
Future<PlayerPlaybackInformation> sampleNativePlaybackInformation({
  required Future<String?> Function(String) read,
  required PlayerDiagnostics diagnostics,
  required double audioGainDb,
}) async {
  const properties = [
    'hwdec-current',
    'video-format',
    'audio-codec-name',
    'container-fps',
    'estimated-vf-fps',
    'video-bitrate',
    'audio-bitrate',
    'video-params/pixelformat',
    'video-params/hw-pixelformat',
    'video-params/colormatrix',
    'video-params/colorlevels',
    'video-params/primaries',
    'video-params/gamma',
    'current-vo',
    'current-ao',
    'avsync',
    'audio-pts',
    'video-pts',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'demuxer-cache-state/fw-bytes',
    'cache-speed',
    'demuxer-cache-duration',
  ];
  final values = await Future.wait([
    for (final name in properties)
      () async {
        try {
          return await read(name).timeout(const Duration(seconds: 1));
        } on Object {
          // Unsupported properties and closing native handles are unavailable.
          return null;
        }
      }(),
  ]);
  final data = Map.fromIterables(properties, values);
  String? identifier(String name) {
    final value = data[name];
    return value != null && RegExp(r'^[A-Za-z0-9._+-]{1,64}$').hasMatch(value)
        ? value
        : null;
  }

  double? number(String name, {bool signed = false}) {
    final value = double.tryParse(data[name] ?? '');
    return value != null && value.isFinite && (signed || value >= 0)
        ? value
        : null;
  }

  int? count(String name) {
    final value = int.tryParse(data[name] ?? '');
    return value != null && value >= 0 ? value : null;
  }

  return PlayerPlaybackInformation(
    generation: diagnostics.generation,
    backend: 'media_kit / libmpv',
    diagnostics: diagnostics,
    hardwareDecoder: identifier('hwdec-current'),
    videoCodec: identifier('video-format'),
    audioCodec: identifier('audio-codec-name'),
    sourceFps: number('container-fps'),
    outputFps: number('estimated-vf-fps'),
    videoBitrate: number('video-bitrate'),
    audioBitrate: number('audio-bitrate'),
    pixelFormat: identifier('video-params/pixelformat'),
    hardwarePixelFormat: identifier('video-params/hw-pixelformat'),
    colorMatrix: identifier('video-params/colormatrix'),
    colorLevels: identifier('video-params/colorlevels'),
    colorPrimaries: identifier('video-params/primaries'),
    transferFunction: identifier('video-params/gamma'),
    videoOutput: identifier('current-vo'),
    audioOutput: identifier('current-ao'),
    avSyncSeconds: number('avsync', signed: true),
    audioPositionSeconds: number('audio-pts'),
    videoPositionSeconds: number('video-pts'),
    frameDrops: count('frame-drop-count'),
    decoderDrops: count('decoder-frame-drop-count'),
    cacheBytes: count('demuxer-cache-state/fw-bytes'),
    cacheSpeed: number('cache-speed'),
    cacheSeconds: number('demuxer-cache-duration'),
    audioGainDb: audioGainDb,
  );
}
