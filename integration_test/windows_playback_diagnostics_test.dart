import 'dart:io';
import 'dart:convert';

import 'package:bilisail/core/logging/playback_diagnostic_log.dart';
import 'package:bilisail/features/settings/data/diagnostic_log_export_repository.dart';
import 'package:archive/archive.dart';
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

  testWidgets('native clocks and rate recovery survive the settings ZIP export', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixture = Directory(Platform.environment['BILI_TEST_MEDIA_DIR']!);
    final directory = await Directory.systemTemp.createTemp(
      'bilisail_performance_',
    );
    final log = PlaybackDiagnosticLog(directory);
    final events = <PlayerDiagnosticEvent>[];
    final engine = MediaKitEngine(
      onDiagnostic: (event) {
        events.add(event);
        log.record(event);
      },
    );
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      MediaTrack track(String file) => MediaTrack(
        uri: File('${fixture.path}/$file').uri,
        requestPolicy: MediaRequestPolicy(),
      );
      await engine.open(
        DashPairSource(video: track('video.mp4'), audio: track('audio.m4a')),
        const OpenOptions(play: true, volume: 0),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      engine.markPlaybackDiagnostic(
        PlayerDiagnosticMarker.temporaryRateBegin,
        targetRate: 2,
      );
      await engine.setRate(2);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      engine.markPlaybackDiagnostic(
        PlayerDiagnosticMarker.temporaryRateEnd,
        targetRate: 1,
      );
      await engine.setRate(1);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await engine.pause();
      await Future<void>.delayed(const Duration(seconds: 10));
      final samples = events
          .where((e) => e.kind == PlayerDiagnosticKind.performanceSample)
          .toList();
      expect(
        samples.any(
          (e) =>
              e.rateContext == 'normal' && e.nativeSample?.values['speed'] == 1,
        ),
        isTrue,
      );
      expect(
        samples.any(
          (e) =>
              e.rateContext == 'held' && e.nativeSample?.values['speed'] == 2,
        ),
        isTrue,
      );
      expect(
        samples.any(
          (e) =>
              e.rateContext == 'afterRelease' &&
              e.nativeSample?.values['speed'] == 1,
        ),
        isTrue,
      );
      expect(
        samples.any(
          (e) =>
              e.rateContext == 'afterRelease' &&
              e.snapshot.phase == PlaybackPhase.paused,
        ),
        isTrue,
      );
      expect(
        samples.any(
          (e) => e.nativeSample?.values.containsKey('hwdec-current') == true,
        ),
        isTrue,
      );
      expect(
        samples.any(
          (e) => e.nativeSample?.values.containsKey('avsync') == true,
        ),
        isTrue,
      );
      expect(
        samples.any(
          (e) => e.flutterFrames != null && e.flutterFrames!.frames > 0,
        ),
        isTrue,
      );
      final count = samples.length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        events.where((e) => e.kind == PlayerDiagnosticKind.performanceSample),
        hasLength(count),
      );
      late List<int> zip;
      await DiagnosticLogExportRepository(
        logDirectory: () async => directory,
        flush: log.flush,
        metadata: () async => {
          'platform': 'windows',
          'playbackDiagnosticVersion': 2,
        },
        save: (bytes, _) async {
          zip = bytes;
          return 'probe.zip';
        },
      ).export();
      final archive = ZipDecoder().decodeBytes(zip, verify: true);
      final text = archive.files
          .where((f) => f.name.startsWith('logs/'))
          .map((f) => utf8.decode(f.content))
          .join();
      expect(text, contains('"hwdec-current"'));
      expect(text, contains('"avsync"'));
      expect(text, contains('"temporaryRateEnd"'));
      expect(text, isNot(contains(fixture.path)));
      final output = Directory(
        '${fixture.parent.parent.parent.path}/build/validation/issue-69',
      )..createSync(recursive: true);
      await File('${output.path}/native-diagnostics.zip').writeAsBytes(zip);
      debugPrint(
        'NATIVE_PERFORMANCE_DIAGNOSTICS samples=$count baseline=true held=true afterRelease=true zip=true',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
      await log.close();
      await directory.delete(recursive: true);
    }
  });
}
