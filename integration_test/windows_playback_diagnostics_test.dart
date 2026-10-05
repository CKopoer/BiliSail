import 'dart:io';

import 'package:bili_lite/core/logging/playback_diagnostic_log.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // This libmpv version routes FFmpeg logging through a process-global context.
  // Run the HTTP status assertion in a fresh process, before other players.
  testWidgets('Windows native HTTP failure leaves sanitized local diagnostics', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixturePath = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(fixturePath, isNotNull);
    final directory = Directory(
      '${Directory(fixturePath ?? '').parent.parent.parent.path}/artifacts/native-playback-diagnostics',
    );
    final log = PlaybackDiagnosticLog(directory);
    final events = <PlayerDiagnosticEvent>[];
    final engine = MediaKitEngine(
      onDiagnostic: (event) {
        events.add(event);
        log.record(event);
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 403;
      await request.response.close();
    });
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      final track = MediaTrack(
        uri: Uri.parse(
          'http://127.0.0.1:${server.port}/denied?token=synthetic-secret',
        ),
        requestPolicy: MediaRequestPolicy(),
      );
      await expectLater(
        engine.open(
          DashPairSource(video: track, audio: track),
          const OpenOptions(),
        ),
        throwsA(isA<PlayerFailure>()),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      expect(
        events.any((event) => event.nativeError?.httpStatus == 403),
        isTrue,
      );
      expect(
        events.any((event) => event.kind == PlayerDiagnosticKind.failed),
        isTrue,
      );
      await log.flush();
      final files = await directory
          .list()
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        final text = await file.readAsString();
        expect(text, isNot(contains('synthetic-secret')));
        expect(text, isNot(contains('127.0.0.1')));
      }
      debugPrint(
        'NATIVE_ERROR_DIAGNOSTICS httpStatus=403 phase=failed rawUrlRetained=false',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
      await log.close();
      await server.close(force: true);
    }
  });
}
