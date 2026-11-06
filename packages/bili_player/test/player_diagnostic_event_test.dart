import 'dart:convert';

import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
