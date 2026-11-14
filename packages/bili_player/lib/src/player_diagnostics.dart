import 'player_contract.dart';

/// Sanitized read-only evidence from the native decoder.
/// Codec fields may be null when the backend has not reported a selected track.
final class PlayerDiagnostics {
  const PlayerDiagnostics({
    required this.generation,
    required this.position,
    required this.hasDecodedVideo,
    required this.hasDecodedAudio,
    this.hasVideoOutput = false,
    this.outputWidth,
    this.outputHeight,
    this.videoWidth,
    this.videoHeight,
    this.audioChannels,
    this.audioSampleRate,
    this.videoCodec,
    this.audioCodec,
  });

  final int generation;
  final Duration position;
  final bool hasDecodedVideo;
  final bool hasDecodedAudio;

  /// Native output dimensions are ready, independently of decoder metadata.
  final bool hasVideoOutput;
  final int? outputWidth;
  final int? outputHeight;
  final int? videoWidth;
  final int? videoHeight;
  final int? audioChannels;
  final int? audioSampleRate;
  final String? videoCodec;
  final String? audioCodec;

  @override
  String toString() =>
      'PlayerDiagnostics('
      'generation: $generation, position: $position, '
      'hasDecodedVideo: $hasDecodedVideo, hasDecodedAudio: $hasDecodedAudio, '
      'hasVideoOutput: $hasVideoOutput, '
      'outputWidth: $outputWidth, outputHeight: $outputHeight, '
      'videoWidth: $videoWidth, videoHeight: $videoHeight, '
      'audioChannels: $audioChannels, audioSampleRate: $audioSampleRate, '
      'videoCodec: $videoCodec, audioCodec: $audioCodec)';
}

enum PlayerDiagnosticKind {
  openStarted,
  openReady,
  openStageChanged,
  openTerminated,
  videoInterrupted,
  playbackStalled,
  nativeLog,
  nativeError,
  recovered,
  failed,
  bufferingStarted,
  bufferingEnded,
  nativeState,
}

enum NativeErrorCause {
  http,
  timeout,
  connection,
  tls,
  hardwareDecoder,
  decoder,
  missingFile,
  inputOutput,
  openFailed,
  unsupportedProperty,
  unknown,
}

enum NativeLogSeverity { warning, error, fatal }

enum PlaybackStallReason {
  playbackClock,
  audioClock,
  videoBuffer,
  videoClock,
  repeatedDecoderBuffering,
}

enum NativeErrorDetail {
  invalidBitstream,
  missingReference,
  timestamp,
  corruptPacket,
  prematureRead,
  segmentRead,
  avDesync,
  hardwareAdvice,
  decoderFailure,
  unknown,
}

enum DiagnosticSourceKind {
  dash,
  preview,
  liveManifest,
  liveProgressive,
  other,
}

/// The bounded source-open step, without media URLs or native log text.
enum NativeReadinessStage { tracks, externalAudio, videoDecode, videoOutput }

/// Raw native text never leaves the adapter. Only known categories and a
/// three-digit HTTP status may cross into local diagnostics.
final class NativeErrorSummary {
  const NativeErrorSummary(
    this.cause, {
    this.httpStatus,
    this.component = 'other',
    this.detail = NativeErrorDetail.unknown,
  });

  factory NativeErrorSummary.classify(String text, {String prefix = 'other'}) {
    final value = text.toLowerCase();
    final component =
        const {
          'ffmpeg',
          'ffmpeg/video',
          'ffmpeg/audio',
          'ffmpeg/demuxer',
          'lavf',
          'vd',
          'ad',
          'cplayer',
          'stream',
          'file',
          'demux',
          'ao',
          'vo',
          'media_kit',
        }.contains(prefix)
        ? prefix
        : 'other';
    final match = RegExp(
      r'\b(?:http(?: error)?|server returned)\s*:?\s*([45]\d{2})\b',
    ).firstMatch(value);
    final status = match == null ? null : int.tryParse(match.group(1) ?? '');
    final detail = switch (value) {
      _ when value.contains('consider trying') && value.contains('hwdec') =>
        NativeErrorDetail.hardwareAdvice,
      _ when value.contains('audio/video desynchronisation') =>
        NativeErrorDetail.avDesync,
      _
          when value.contains('reference picture') ||
              value.contains('missing reference') ||
              value.contains('non-existing pps') ||
              value.contains('pps id out of range') =>
        NativeErrorDetail.missingReference,
      _
          when value.contains('nal unit') ||
              value.contains('slice_header') ||
              value.contains('invalid bitstream') ||
              value.contains('error splitting') =>
        NativeErrorDetail.invalidBitstream,
      _
          when value.contains('packet corrupt') ||
              value.contains('corrupt input packet') =>
        NativeErrorDetail.corruptPacket,
      _
          when value.contains('timestamp') ||
              value.contains('pts') ||
              value.contains('non-monoton') ||
              value.contains('dts') =>
        NativeErrorDetail.timestamp,
      _
          when value.contains('stream ends prematurely') ||
              value.contains('partial file') =>
        NativeErrorDetail.prematureRead,
      _
          when value.contains('failed to open segment') ||
              value.contains('failed to reload playlist') =>
        NativeErrorDetail.segmentRead,
      _
          when value.contains('error decoding') ||
              value.contains('failed to decode') =>
        NativeErrorDetail.decoderFailure,
      _ => NativeErrorDetail.unknown,
    };
    final cause = switch (value) {
      _ when status != null => NativeErrorCause.http,
      _ when value.contains('timed out') || value.contains('timeout') =>
        NativeErrorCause.timeout,
      _
          when value.contains('tls') ||
              value.contains('certificate') ||
              value.contains('ssl') =>
        NativeErrorCause.tls,
      _
          when value.contains('connection') ||
              value.startsWith('tcp:') ||
              value.contains('resolve') =>
        NativeErrorCause.connection,
      _
          when detail != NativeErrorDetail.hardwareAdvice &&
              detail != NativeErrorDetail.avDesync &&
              (value.contains('failed') ||
                  value.contains('error') ||
                  value.contains('unavailable') ||
                  value.contains('cannot') ||
                  value.contains('could not')) &&
              (value.contains('hwdec') ||
                  value.contains('hardware') ||
                  value.contains('d3d11') ||
                  value.contains('dxva')) =>
        NativeErrorCause.hardwareDecoder,
      _
          when value.contains('decode') ||
              value.contains('decoding') ||
              prefix == 'vd' ||
              prefix == 'ad' ||
              component == 'ffmpeg/video' ||
              component == 'ffmpeg/audio' =>
        NativeErrorCause.decoder,
      _ when value.contains('property not found') =>
        NativeErrorCause.unsupportedProperty,
      _ when value.contains('failed to open') => NativeErrorCause.openFailed,
      _ when value.contains('not found') || value.contains('no such file') =>
        NativeErrorCause.missingFile,
      _
          when value.contains('input/output') ||
              value.contains('i/o error') ||
              value.contains('stream ends prematurely') ||
              value.contains('error in the pull function') =>
        NativeErrorCause.inputOutput,
      _ => NativeErrorCause.unknown,
    };
    return NativeErrorSummary(
      cause,
      httpStatus: status,
      component: component,
      detail: detail,
    );
  }

  final NativeErrorCause cause;
  final int? httpStatus;
  final String component;
  final NativeErrorDetail detail;

  bool get isVideoDecodeError =>
      const {'vd', 'ffmpeg/video'}.contains(component) &&
      const {
        NativeErrorCause.decoder,
        NativeErrorCause.hardwareDecoder,
      }.contains(cause);
}

final class PlayerDiagnosticEvent {
  PlayerDiagnosticEvent({
    required this.kind,
    required this.snapshot,
    this.nativeError,
    this.failureKind,
    this.severity,
    this.nativeErrorCode,
    this.readinessStage,
    this.diagnostics,
    this.stallReason,
    this.stalledFor,
    this.audioPosition,
    this.playerId,
    this.sourceKind,
    this.bufferingDuration,
    this.nativeState,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  final DateTime timestamp;
  final PlayerDiagnosticKind kind;
  final PlaybackSnapshot snapshot;
  final NativeErrorSummary? nativeError;
  final PlayerFailureKind? failureKind;
  final NativeLogSeverity? severity;
  final int? nativeErrorCode;
  final NativeReadinessStage? readinessStage;
  final PlayerDiagnostics? diagnostics;
  final PlaybackStallReason? stallReason;
  final Duration? stalledFor;
  final Duration? audioPosition;
  final int? playerId;
  final DiagnosticSourceKind? sourceKind;
  final Duration? bufferingDuration;
  final NativePlaybackState? nativeState;

  PlayerDiagnosticEvent withContext({
    required int playerId,
    PlayerDiagnostics? diagnostics,
    NativeReadinessStage? readinessStage,
    DiagnosticSourceKind? sourceKind,
  }) => PlayerDiagnosticEvent(
    kind: kind,
    snapshot: snapshot,
    nativeError: nativeError,
    failureKind: failureKind,
    severity: severity,
    nativeErrorCode: nativeErrorCode,
    readinessStage: this.readinessStage ?? readinessStage,
    diagnostics: this.diagnostics ?? diagnostics,
    stallReason: stallReason,
    stalledFor: stalledFor,
    audioPosition: audioPosition,
    playerId: playerId,
    sourceKind: this.sourceKind ?? sourceKind,
    bufferingDuration: bufferingDuration,
    nativeState: nativeState,
    timestamp: timestamp,
  );

  Map<String, Object?> toJson() => {
    'time': timestamp.toIso8601String(),
    'event': kind.name,
    'generation': snapshot.generation,
    'playerId': ?playerId,
    'sourceKind': ?sourceKind?.name,
    'bufferingDurationMs': ?bufferingDuration?.inMilliseconds,
    'bufferAheadMs': (snapshot.buffered - snapshot.position).inMilliseconds,
    'phase': snapshot.phase.name,
    'positionMs': snapshot.position.inMilliseconds,
    'durationMs': snapshot.duration.inMilliseconds,
    'bufferedMs': snapshot.buffered.inMilliseconds,
    'desiredPlaying': snapshot.desiredPlaying,
    'buffering': snapshot.isBuffering,
    'seeking': snapshot.isSeeking,
    'rate': snapshot.rate,
    'stallReason': ?stallReason?.name,
    'stalledForMs': ?stalledFor?.inMilliseconds,
    'audioPositionMs': ?audioPosition?.inMilliseconds,
    'severity': ?severity?.name,
    'nativeErrorCode': ?nativeErrorCode,
    'readinessStage': ?readinessStage?.name,
    if (diagnostics case final media?) ...{
      'hasDecodedVideo': media.hasDecodedVideo,
      'hasDecodedAudio': media.hasDecodedAudio,
      'hasVideoOutput': media.hasVideoOutput,
      'videoWidth': ?media.videoWidth,
      'videoHeight': ?media.videoHeight,
    },
    if (nativeError case final error?) ...{
      'component': error.component,
      'cause': error.cause.name,
      'detail': error.detail.name,
      'httpStatus': ?error.httpStatus,
    },
    if (failureKind case final failure?) 'failure': failure.name,
    if (nativeState case final state?) 'nativeState': state.toJson(),
  };
}

/// Allowlisted scalars only; raw property values and native messages are discarded.
final class NativePlaybackState {
  static const hardwareDecoders = {
    'no',
    'd3d11va',
    'd3d11va-copy',
    'dxva2',
    'dxva2-copy',
    'mediacodec',
    'mediacodec-copy',
    'videotoolbox',
    'videotoolbox-copy',
    'vaapi',
    'vaapi-copy',
    'nvdec',
    'nvdec-copy',
    'vdpau',
    'drm',
    'vulkan',
  };
  static const videoCodecs = {
    'h264',
    'hevc',
    'av1',
    'vp8',
    'vp9',
    'mpeg2video',
    'mpeg4',
  };
  static const audioCodecs = {
    'aac',
    'mp3',
    'flac',
    'eac3',
    'ac3',
    'opus',
    'vorbis',
    'alac',
    'pcm_s16le',
  };
  const NativePlaybackState({
    this.coreIdle,
    this.pausedForCache,
    this.cacheReading,
    this.cacheEof,
    this.cacheBytes,
    this.cacheSpeed,
    this.cacheDurationMs,
    this.audioPositionMs,
    this.nativePositionMs,
    this.avSyncMs,
    this.frameDrops,
    this.decoderDrops,
    this.hardwareDecoder,
    this.videoCodec,
    this.audioCodec,
  });
  final bool? coreIdle, pausedForCache, cacheReading, cacheEof;
  final int? cacheBytes, cacheSpeed, cacheDurationMs;
  final int? audioPositionMs,
      nativePositionMs,
      avSyncMs,
      frameDrops,
      decoderDrops;
  final String? hardwareDecoder, videoCodec, audioCodec;

  Map<String, Object?> toJson() => {
    'coreIdle': ?coreIdle,
    'pausedForCache': ?pausedForCache,
    'cacheReading': ?cacheReading,
    'cacheEof': ?cacheEof,
    'cacheBytes': ?cacheBytes,
    'cacheSpeedBytesPerSecond': ?cacheSpeed,
    'cacheDurationMs': ?cacheDurationMs,
    'audioPositionMs': ?audioPositionMs,
    'nativePositionMs': ?nativePositionMs,
    'avSyncMs': ?avSyncMs,
    'frameDrops': ?frameDrops,
    'decoderDrops': ?decoderDrops,
    if (hardwareDecoders.contains(hardwareDecoder))
      'hardwareDecoder': hardwareDecoder,
    if (videoCodecs.contains(videoCodec)) 'videoCodec': videoCodec,
    if (audioCodecs.contains(audioCodec)) 'audioCodec': audioCodec,
  };
}
