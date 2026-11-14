import 'dart:async';
import 'dart:convert';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_buffering_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'samples fixed properties and discards private fields and native text',
    () async {
      final values = <String, String>{
        'core-idle': 'yes',
        'paused-for-cache': 'no',
        'demuxer-cache-state':
            '{"idle":false,"eof":false,"fw-bytes":4096,"private":"SECRET"}',
        'cache-speed': '8192',
        'demuxer-cache-duration': '4.5',
        'audio-pts': '12.25',
        'time-pos': '12',
        'avsync': '-0.25',
        'frame-drop-count': '3',
        'decoder-frame-drop-count': '2',
        'hwdec-current': 'd3d11va',
        'video-format': 'h264',
        'audio-codec-name': 'aac',
      };
      final seen = <String>[];
      final state = await sampleNativeBufferingState((name) async {
        seen.add(name);
        return values[name];
      });
      final json = state.toJson();
      expect(json['pausedForCache'], false);
      expect(json['coreIdle'], true);
      expect(json['cacheBytes'], 4096);
      expect(json['cacheDurationMs'], 4500);
      expect(json['avSyncMs'], -250);
      expect(json['audioPositionMs'], 12250);
      expect(json['hardwareDecoder'], 'd3d11va');
      expect(seen, hasLength(13));
      expect(jsonEncode(json), isNot(contains('SECRET')));
    },
  );
  test('invalid, unsupported and sensitive values stay unknown', () async {
    for (final bad in [
      'NaN',
      'Infinity',
      '-123',
      'https://private/?token=SECRET',
      '1e100',
    ]) {
      final state = await sampleNativeBufferingState((_) async => bad);
      final json = state.toJson();
      expect(json['cacheBytes'], isNull);
      expect(json['cacheSpeedBytesPerSecond'], isNull);
      expect(json['hardwareDecoder'], isNull);
      expect(json['videoCodec'], isNull);
      expect(jsonEncode(json), isNot(contains('SECRET')));
    }
    final state = await sampleNativeBufferingState(
      (_) => Future.error(StateError('SECRET')),
    );
    expect(state.toJson(), isEmpty);
  });
  testWidgets(
    'native reads have one bounded in-flight sample and stale results are dropped',
    (tester) async {
      final blocked = Completer<String?>();
      final events = <PlayerDiagnosticEvent>[];
      var current = true, reads = 0;
      final diagnostics = NativeBufferingDiagnostics(
        read: (_) {
          reads++;
          return blocked.future;
        },
        snapshot: () =>
            const PlaybackSnapshot(phase: PlaybackPhase.playing, generation: 1),
        isCurrent: () => current,
        emit: events.add,
      );
      diagnostics.capture();
      diagnostics.capture(force: true);
      expect(reads, 13);
      current = false;
      blocked.complete('SECRET');
      await tester.pump();
      expect(events, isEmpty);
      diagnostics.dispose();
      diagnostics.capture();
      expect(reads, 13);
    },
  );
  testWidgets(
    'a stuck native property is unavailable after the shared read window',
    (tester) async {
      final events = <PlayerDiagnosticEvent>[];
      var reads = 0;
      final diagnostics = NativeBufferingDiagnostics(
        read: (_) {
          reads++;
          return Completer<String?>().future;
        },
        snapshot: () =>
            const PlaybackSnapshot(phase: PlaybackPhase.playing, generation: 1),
        isCurrent: () => true,
        emit: events.add,
      );
      diagnostics.capture();
      await tester.pump(const Duration(milliseconds: 400));
      expect(events.single.nativeState!.toJson(), isEmpty);
      diagnostics.capture(force: true);
      await tester.pump(const Duration(seconds: 1));
      expect(
        reads,
        13,
        reason: 'Timed-out native reads must not accumulate new batches',
      );
      diagnostics.dispose();
    },
  );
  testWidgets(
    'buffering pulses are hidden and sustained episodes have boundary samples',
    (tester) async {
      var snapshot = const PlaybackSnapshot(
        phase: PlaybackPhase.buffering,
        generation: 1,
        desiredPlaying: true,
        isBuffering: true,
      );
      final events = <PlayerDiagnosticEvent>[];
      final diagnostics = NativeBufferingDiagnostics(
        read: (_) async => null,
        snapshot: () => snapshot,
        isCurrent: () => true,
        emit: events.add,
      );
      diagnostics.bufferingChanged(true);
      await tester.pump(const Duration(milliseconds: 200));
      snapshot = snapshot.copyWith(
        isBuffering: false,
        phase: PlaybackPhase.playing,
      );
      diagnostics.bufferingChanged(false);
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
      snapshot = snapshot.copyWith(
        isBuffering: true,
        phase: PlaybackPhase.buffering,
      );
      diagnostics.bufferingChanged(true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        events.where((e) => e.kind == PlayerDiagnosticKind.bufferingStarted),
        hasLength(1),
      );
      expect(
        events.where((e) => e.kind == PlayerDiagnosticKind.nativeState),
        hasLength(1),
      );
      snapshot = snapshot.copyWith(
        isBuffering: false,
        phase: PlaybackPhase.playing,
      );
      diagnostics.bufferingChanged(false);
      await tester.pump();
      expect(
        events.where((e) => e.kind == PlayerDiagnosticKind.bufferingEnded),
        hasLength(1),
      );
      diagnostics.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
