import 'player_diagnostics.dart';

/// Optional, read-only sampling. It must not open media or change playback.
abstract interface class PlayerInformationSource {
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation();
}

/// Safe native measurements for one source generation. Missing values mean
/// unavailable, never zero. Contains no paths, URLs, headers or track IDs.
final class PlayerPlaybackInformation {
  const PlayerPlaybackInformation({
    required this.generation,
    required this.backend,
    this.diagnostics,
    this.hardwareDecoder,
    this.videoCodec,
    this.audioCodec,
    this.sourceFps,
    this.outputFps,
    this.videoBitrate,
    this.audioBitrate,
    this.videoNominalBitrate,
    this.audioNominalBitrate,
    this.pixelFormat,
    this.hardwarePixelFormat,
    this.colorMatrix,
    this.colorLevels,
    this.colorPrimaries,
    this.transferFunction,
    this.videoOutput,
    this.audioOutput,
    this.avSyncSeconds,
    this.audioPositionSeconds,
    this.videoPositionSeconds,
    this.frameDrops,
    this.decoderDrops,
    this.cacheBytes,
    this.cacheSpeed,
    this.cacheSeconds,
    this.audioGainDb,
  });

  final int generation;
  final String backend;
  final PlayerDiagnostics? diagnostics;
  final String? hardwareDecoder, videoCodec, audioCodec;
  final double? sourceFps, outputFps;
  final double? videoBitrate, audioBitrate;

  /// Native stream metadata, distinct from measured demuxer bitrates.
  final double? videoNominalBitrate, audioNominalBitrate;
  final String? pixelFormat, colorMatrix, colorPrimaries, transferFunction;
  final String? hardwarePixelFormat, colorLevels;
  final String? videoOutput, audioOutput;

  /// Native A−V difference and per-track timestamps, in seconds.
  final double? avSyncSeconds, audioPositionSeconds, videoPositionSeconds;
  final int? frameDrops, decoderDrops;

  /// Forward packet cache in bytes; read speed is bytes per second.
  final int? cacheBytes;
  final double? cacheSpeed, cacheSeconds;
  final double? audioGainDb;

  PlayerPlaybackInformation withGeneration(int generation) =>
      PlayerPlaybackInformation(
        generation: generation,
        backend: backend,
        diagnostics: switch (diagnostics) {
          final info? => PlayerDiagnostics(
            generation: generation,
            position: info.position,
            hasDecodedVideo: info.hasDecodedVideo,
            hasDecodedAudio: info.hasDecodedAudio,
            hasVideoOutput: info.hasVideoOutput,
            outputWidth: info.outputWidth,
            outputHeight: info.outputHeight,
            videoWidth: info.videoWidth,
            videoHeight: info.videoHeight,
            audioChannels: info.audioChannels,
            audioSampleRate: info.audioSampleRate,
            videoCodec: info.videoCodec,
            audioCodec: info.audioCodec,
          ),
          null => null,
        },
        hardwareDecoder: hardwareDecoder,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        sourceFps: sourceFps,
        outputFps: outputFps,
        videoBitrate: videoBitrate,
        audioBitrate: audioBitrate,
        videoNominalBitrate: videoNominalBitrate,
        audioNominalBitrate: audioNominalBitrate,
        pixelFormat: pixelFormat,
        hardwarePixelFormat: hardwarePixelFormat,
        colorMatrix: colorMatrix,
        colorLevels: colorLevels,
        colorPrimaries: colorPrimaries,
        transferFunction: transferFunction,
        videoOutput: videoOutput,
        audioOutput: audioOutput,
        avSyncSeconds: avSyncSeconds,
        audioPositionSeconds: audioPositionSeconds,
        videoPositionSeconds: videoPositionSeconds,
        frameDrops: frameDrops,
        decoderDrops: decoderDrops,
        cacheBytes: cacheBytes,
        cacheSpeed: cacheSpeed,
        cacheSeconds: cacheSeconds,
        audioGainDb: audioGainDb,
      );
}
