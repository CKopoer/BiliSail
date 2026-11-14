import 'dart:convert';

import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video bitstream errors enter stall checking and keep only fixed subcategories', () {
    for (final (message, detail) in [
      (
        'Invalid NAL unit size 999 https://cdn/?token=SECRET',
        NativeErrorDetail.invalidBitstream,
      ),
      (
        'Reference picture missing during reorder',
        NativeErrorDetail.missingReference,
      ),
      ('Packet corrupt (stream = 0)', NativeErrorDetail.corruptPacket),
      ('Non-monotonous DTS in output stream', NativeErrorDetail.timestamp),
      ('Error decoding video frame', NativeErrorDetail.decoderFailure),
      ('Unrecognized native decoder message', NativeErrorDetail.unknown),
    ]) {
      final summary = NativeErrorSummary.classify(
        message,
        prefix: 'ffmpeg/video',
      );
      expect(summary.isVideoDecodeError, true);
      expect(summary.detail, detail);
      expect(summary.cause, NativeErrorCause.decoder);
      expect(
        jsonEncode(
          PlayerDiagnosticEvent(
            kind: PlayerDiagnosticKind.nativeLog,
            snapshot: const PlaybackSnapshot(
              phase: PlaybackPhase.playing,
              generation: 1,
            ),
            nativeError: summary,
          ).toJson(),
        ),
        isNot(contains('SECRET')),
      );
    }
    expect(
      NativeErrorSummary.classify(
        'HTTP error 403',
        prefix: 'ffmpeg/video',
      ).isVideoDecodeError,
      false,
    );
  });
  test(
    'hardware advice and desync hints are not hardware decoder failures',
    () {
      for (final message in [
        'Consider trying --profile=fast and/or --hwdec=auto as they may help.',
        'Audio/Video desynchronisation detected! Possible reasons include too slow hardware.',
        'hardware, temporary CPU spikes, broken drivers, and broken files.',
      ]) {
        expect(
          NativeErrorSummary.classify(message, prefix: 'cplayer').cause,
          isNot(NativeErrorCause.hardwareDecoder),
        );
      }
      expect(
        NativeErrorSummary.classify(
          'Failed D3D11 hardware decoder',
          prefix: 'vd',
        ).isVideoDecodeError,
        true,
      );
    },
  );
  test('enrichment preserves capture identity, timing and sanitized state', () {
    final event = PlayerDiagnosticEvent(
      kind: PlayerDiagnosticKind.nativeState,
      snapshot: const PlaybackSnapshot(
        phase: PlaybackPhase.buffering,
        generation: 3,
      ),
      bufferingDuration: const Duration(seconds: 2),
      nativeState: const NativePlaybackState(
        coreIdle: true,
        pausedForCache: false,
        hardwareDecoder: 'SECRET',
        videoCodec: 'https://private/?token=SECRET',
      ),
    );
    final first = event.withContext(
      playerId: 7,
      sourceKind: DiagnosticSourceKind.liveManifest,
    );
    final second = event.withContext(playerId: 8);
    expect(first.timestamp, event.timestamp);
    expect(first.toJson()['playerId'], 7);
    expect(second.toJson()['playerId'], 8);
    expect(first.toJson()['sourceKind'], 'liveManifest');
    expect(first.toJson()['bufferingDurationMs'], 2000);
    expect(jsonEncode(first.toJson()), isNot(contains('SECRET')));
  });
  test('stall diagnostics record safe clocks and the detection deadline', () {
    final json = PlayerDiagnosticEvent(
      kind: PlayerDiagnosticKind.playbackStalled,
      snapshot: const PlaybackSnapshot(
        phase: PlaybackPhase.playing,
        generation: 2,
      ),
      stallReason: PlaybackStallReason.playbackClock,
      stalledFor: const Duration(seconds: 8),
      audioPosition: const Duration(seconds: 28),
    ).toJson();
    expect(json['stallReason'], 'playbackClock');
    expect(json['stalledForMs'], 8000);
    expect(json['audioPositionMs'], 28000);
  });

  test('readiness diagnostics expose only stage and media readiness flags', () {
    final event = PlayerDiagnosticEvent(
      kind: PlayerDiagnosticKind.failed,
      snapshot: const PlaybackSnapshot(
        phase: PlaybackPhase.opening,
        generation: 2,
      ),
      readinessStage: NativeReadinessStage.videoDecode,
      diagnostics: const PlayerDiagnostics(
        generation: 2,
        position: Duration.zero,
        hasDecodedVideo: false,
        hasDecodedAudio: true,
        videoCodec: 'https://private.example/?token=SECRET',
      ),
    );
    final json = event.toJson();
    expect(json['readinessStage'], 'videoDecode');
    expect(json['hasDecodedVideo'], false);
    expect(json['hasDecodedAudio'], true);
    expect(json['hasVideoOutput'], false);
    expect(jsonEncode(json), isNot(contains('SECRET')));
    expect(jsonEncode(json), isNot(contains('private.example')));
  });

  test('native text is classified without retaining URLs or credentials', () {
    final summary = NativeErrorSummary.classify(
      'HTTP error 403 Forbidden: https://cdn.example/private?token=SECRET '
      'Cookie: SESSDATA=SECRET Authorization: Bearer SECRET',
      prefix: 'ffmpeg',
    );
    final event = PlayerDiagnosticEvent(
      kind: PlayerDiagnosticKind.nativeLog,
      snapshot: const PlaybackSnapshot(
        phase: PlaybackPhase.playing,
        generation: 4,
      ),
      nativeError: summary,
    );
    expect(summary.cause, NativeErrorCause.http);
    expect(summary.httpStatus, 403);
    expect(
      NativeErrorSummary.classify('http: HTTP error 403 Forbidden').httpStatus,
      403,
    );
    final json = jsonEncode(event.toJson());
    expect(json, contains('ffmpeg'));
    expect(json, isNot(contains('SECRET')));
    expect(json, isNot(contains('cdn.example')));
    expect(json, isNot(contains('SESSDATA')));
  });

  test('unknown messages and module names cannot escape the whitelist', () {
    final summary = NativeErrorSummary.classify(
      'secret-value',
      prefix: 'token=secret',
    );
    expect(summary.cause, NativeErrorCause.unknown);
    expect(summary.component, 'other');
    expect(summary.httpStatus, isNull);
    expect(
      NativeErrorSummary.classify('Failed to decode frame', prefix: 'vd').cause,
      NativeErrorCause.decoder,
    );
    expect(
      NativeErrorSummary.classify('tcp: Connection timed out').cause,
      NativeErrorCause.timeout,
    );
    expect(
      NativeErrorSummary.classify('Failed D3D11 hardware decoder').cause,
      NativeErrorCause.hardwareDecoder,
    );
  });

  test('audio decoding errors retain the sanitized decoder category', () {
    final summary = NativeErrorSummary.classify(
      'Error decoding audio.',
      prefix: 'ffmpeg/audio',
    );
    expect(summary.component, 'ffmpeg/audio');
    expect(summary.cause, NativeErrorCause.decoder);
  });

  test('premature HTTP reads and TLS pull failures retain no source text', () {
    for (final message in [
      'Stream ends prematurely at 100, should be 200',
      'Error in the pull function. https://private.test/?token=SECRET',
    ]) {
      final summary = NativeErrorSummary.classify(message, prefix: 'ffmpeg');
      expect(summary.cause, NativeErrorCause.inputOutput);
      expect(summary.httpStatus, isNull);
    }
  });
}
