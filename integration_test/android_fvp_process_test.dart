import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bilisail/core/logging/playback_diagnostic_log.dart';

/// Serve test/fixtures/media over an adb-reversed, local-only fixture server.
/// The host sends SIGSEGV only to the debuggable test package's :fvp_player.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('native worker crashes leave the UI and explicit reopen alive', (
    tester,
  ) async {
    const port = int.fromEnvironment(
      'BILI_FVP_FIXTURE_PORT',
      defaultValue: 18764,
    );
    final logs = <PlayerDiagnosticEvent>[];
    final diagnosticLog = await PlaybackDiagnosticLog.create();
    void record(PlayerDiagnosticEvent event) {
      logs.add(event);
      diagnosticLog?.record(event, backend: 'fvp');
    }

    var engine = FvpEngine(onDiagnostic: record);
    StreamSubscription<PlayerFailure>? failureSubscription;
    final source = DashPairSource(
      video: MediaTrack(
        uri: Uri.parse('http://127.0.0.1:$port/video.mp4'),
        requestPolicy: MediaRequestPolicy(),
      ),
      audio: MediaTrack(
        uri: Uri.parse('http://127.0.0.1:$port/audio.m4a'),
        requestPolicy: MediaRequestPolicy(),
      ),
    );
    var taps = 0;
    Widget page() => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(child: VideoSurface(engine: engine)),
            TextButton(onPressed: () => taps++, child: const Text('alive')),
          ],
        ),
      ),
    );
    Future<void> marker(String phase) async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/$phase'),
        );
        final body = utf8.encode(jsonEncode({'pid': pid}));
        request.contentLength = body.length;
        request.add(body);
        await (await request.close()).drain<void>();
      } finally {
        client.close(force: true);
      }
    }

    try {
      await tester.pumpWidget(page());
      await engine.open(source, const OpenOptions(play: true, volume: 0));
      expect(engine.currentSnapshot.videoDimensions, isNotNull);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
      final failed = Completer<PlayerFailure>();
      failureSubscription = engine.failures.listen((failure) {
        if (failure.kind == PlayerFailureKind.nativeProcessExited &&
            !failed.isCompleted) {
          failed.complete(failure);
        }
      });
      await marker('playing');
      await failed.future.timeout(const Duration(seconds: 30));
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      await tester.tap(find.text('alive'));
      expect(taps, 1);
      expect(
        logs.where((e) => e.kind == PlayerDiagnosticKind.nativeProcessExited),
        hasLength(1),
      );
      await engine.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      engine = FvpEngine(onDiagnostic: record);
      await tester.pumpWidget(page());
      await engine.open(source, const OpenOptions(play: true, volume: 0));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      await marker('reopened');
      binding.reportData = {
        'fvpProcess': {
          'uiPid': pid,
          'events': logs.map((e) => e.toJson()).toList(),
        },
      };
    } finally {
      await failureSubscription?.cancel();
      await engine.dispose();
      await diagnosticLog?.close();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
