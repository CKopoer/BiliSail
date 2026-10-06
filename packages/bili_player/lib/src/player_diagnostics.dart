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
      'videoWidth: $videoWidth, videoHeight: $videoHeight, '
      'audioChannels: $audioChannels, audioSampleRate: $audioSampleRate, '
      'videoCodec: $videoCodec, audioCodec: $audioCodec)';
}

enum PlayerDiagnosticKind {
  openStarted,
  openReady,
  nativeLog,
  nativeError,
  recovered,
  failed,
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

/// Raw native text never leaves the adapter. Only known categories and a
/// three-digit HTTP status may cross into local diagnostics.
final class NativeErrorSummary {
  const NativeErrorSummary(
    this.cause, {
    this.httpStatus,
    this.component = 'other',
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
          when value.contains('hwdec') ||
              value.contains('hardware') ||
              value.contains('d3d11') ||
              value.contains('dxva') =>
        NativeErrorCause.hardwareDecoder,
      _ when value.contains('decode') || prefix == 'vd' || prefix == 'ad' =>
        NativeErrorCause.decoder,
      _ when value.contains('property not found') =>
        NativeErrorCause.unsupportedProperty,
      _ when value.contains('failed to open') => NativeErrorCause.openFailed,
      _ when value.contains('not found') || value.contains('no such file') =>
        NativeErrorCause.missingFile,
      _ when value.contains('input/output') || value.contains('i/o error') =>
        NativeErrorCause.inputOutput,
      _ => NativeErrorCause.unknown,
    };
    return NativeErrorSummary(cause, httpStatus: status, component: component);
  }

  final NativeErrorCause cause;
  final int? httpStatus;
  final String component;
}

final class PlayerDiagnosticEvent {
  PlayerDiagnosticEvent({
    required this.kind,
    required this.snapshot,
    this.nativeError,
    this.failureKind,
    this.severity,
  }) : timestamp = DateTime.now().toUtc();

  final DateTime timestamp;
  final PlayerDiagnosticKind kind;
  final PlaybackSnapshot snapshot;
  final NativeErrorSummary? nativeError;
  final PlayerFailureKind? failureKind;
  final NativeLogSeverity? severity;

  Map<String, Object?> toJson() => {
    'time': timestamp.toIso8601String(),
    'event': kind.name,
    'generation': snapshot.generation,
    'phase': snapshot.phase.name,
    'positionMs': snapshot.position.inMilliseconds,
    'durationMs': snapshot.duration.inMilliseconds,
    'bufferedMs': snapshot.buffered.inMilliseconds,
    'desiredPlaying': snapshot.desiredPlaying,
    'buffering': snapshot.isBuffering,
    'seeking': snapshot.isSeeking,
    'rate': snapshot.rate,
    'severity': ?severity?.name,
    if (nativeError case final error?) ...{
      'component': error.component,
      'cause': error.cause.name,
      'httpStatus': ?error.httpStatus,
    },
    if (failureKind case final failure?) 'failure': failure.name,
  };
}
