import 'dart:convert';

import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
