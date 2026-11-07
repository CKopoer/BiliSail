import 'player_diagnostics.dart';
import 'player_playback_information.dart';

/// The worker forwards the same allowlisted measurements as the local port.
Map<String, Object?> encodeFvpInformation(PlayerPlaybackInformation value) {
  final media = value.diagnostics;
  return {
    'generation': value.generation,
    'backend': value.backend,
    'hardwareDecoder': value.hardwareDecoder,
    'videoCodec': value.videoCodec,
    'audioCodec': value.audioCodec,
    'sourceFps': value.sourceFps,
    'outputFps': value.outputFps,
    'videoBitrate': value.videoBitrate,
    'audioBitrate': value.audioBitrate,
    'videoNominalBitrate': value.videoNominalBitrate,
    'audioNominalBitrate': value.audioNominalBitrate,
    'pixelFormat': value.pixelFormat,
    'hardwarePixelFormat': value.hardwarePixelFormat,
    'colorMatrix': value.colorMatrix,
    'colorLevels': value.colorLevels,
    'colorPrimaries': value.colorPrimaries,
    'transferFunction': value.transferFunction,
    'videoOutput': value.videoOutput,
    'audioOutput': value.audioOutput,
    'avSyncSeconds': value.avSyncSeconds,
    'audioPositionSeconds': value.audioPositionSeconds,
    'videoPositionSeconds': value.videoPositionSeconds,
    'frameDrops': value.frameDrops,
    'decoderDrops': value.decoderDrops,
    'cacheBytes': value.cacheBytes,
    'cacheSpeed': value.cacheSpeed,
    'cacheSeconds': value.cacheSeconds,
    'audioGainDb': value.audioGainDb,
    if (media != null)
      'diagnostics': {
        'position': media.position.inMilliseconds,
        'video': media.hasDecodedVideo,
        'audio': media.hasDecodedAudio,
        'output': media.hasVideoOutput,
        'outputWidth': media.outputWidth,
        'outputHeight': media.outputHeight,
        'videoWidth': media.videoWidth,
        'videoHeight': media.videoHeight,
        'audioChannels': media.audioChannels,
        'audioSampleRate': media.audioSampleRate,
      },
  };
}

PlayerPlaybackInformation? decodeFvpInformation(Object? value) {
  if (value is! Map || value['generation'] is! int) return null;
  double? number(String key) => switch (value[key]) {
    final num n when n.isFinite => n.toDouble(),
    _ => null,
  };
  String? string(String key) =>
      value[key] is String ? value[key] as String : null;
  int? integer(String key) => value[key] is int ? value[key] as int : null;
  final generation = value['generation'] as int;
  final media = value['diagnostics'];
  return PlayerPlaybackInformation(
    generation: generation,
    backend: 'fvp / MDK',
    diagnostics: media is Map
        ? PlayerDiagnostics(
            generation: generation,
            position: Duration(milliseconds: media['position'] as int? ?? 0),
            hasDecodedVideo: media['video'] == true,
            hasDecodedAudio: media['audio'] == true,
            hasVideoOutput: media['output'] == true,
            outputWidth: media['outputWidth'] as int?,
            outputHeight: media['outputHeight'] as int?,
            videoWidth: media['videoWidth'] as int?,
            videoHeight: media['videoHeight'] as int?,
            audioChannels: media['audioChannels'] as int?,
            audioSampleRate: media['audioSampleRate'] as int?,
            videoCodec: string('videoCodec'),
            audioCodec: string('audioCodec'),
          )
        : null,
    hardwareDecoder: string('hardwareDecoder'),
    videoCodec: string('videoCodec'),
    audioCodec: string('audioCodec'),
    sourceFps: number('sourceFps'),
    outputFps: number('outputFps'),
    videoBitrate: number('videoBitrate'),
    audioBitrate: number('audioBitrate'),
    videoNominalBitrate: number('videoNominalBitrate'),
    audioNominalBitrate: number('audioNominalBitrate'),
    pixelFormat: string('pixelFormat'),
    hardwarePixelFormat: string('hardwarePixelFormat'),
    colorMatrix: string('colorMatrix'),
    colorLevels: string('colorLevels'),
    colorPrimaries: string('colorPrimaries'),
    transferFunction: string('transferFunction'),
    videoOutput: string('videoOutput'),
    audioOutput: string('audioOutput'),
    avSyncSeconds: number('avSyncSeconds'),
    audioPositionSeconds: number('audioPositionSeconds'),
    videoPositionSeconds: number('videoPositionSeconds'),
    frameDrops: integer('frameDrops'),
    decoderDrops: integer('decoderDrops'),
    cacheBytes: integer('cacheBytes'),
    cacheSpeed: number('cacheSpeed'),
    cacheSeconds: number('cacheSeconds'),
    audioGainDb: number('audioGainDb'),
  );
}
