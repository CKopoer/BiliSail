import 'dart:io';

import 'package:bilisail/core/platform/windows_media_controls.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/system_media_playback_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Windows SMTC controls the existing DASH session and clears on stop',
    (tester) async {
      final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
      final script = Platform.environment['BILI_TEST_SYSTEM_MEDIA_SCRIPT'];
      expect(directory, isNotNull);
      expect(script, isNotNull);
      final engine = MediaKitEngine();
      final repository = SystemMediaFixtureRepository(directory: directory);
      final manager = PlaybackManager(
        systemMediaControls: WindowsMediaControls(),
        createSession: () => PlaybackSession(
          engine: engine,
          repository: repository,
          progress: SystemMediaFixtureProgress(),
          accountScope: () => 'guest',
        ),
      );
      addTearDown(manager.close);
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      final session = manager.acquire('fixture');
      await manager.updateWorkspace(
        allowConcurrent: true,
        activeTabId: 'fixture',
      );
      await session.open(
        systemMediaVideo('BiliSail system media fixture'),
        systemMediaPart,
      );
      expect(session.error, isNull);
      Future<void> until(bool Function() predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!predicate() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(predicate(), isTrue);
      }

      await until(
        () =>
            engine.inspectDiagnostics().hasDecodedAudio &&
            engine.inspectDiagnostics().hasDecodedVideo,
      );
      final generation = engine.currentSnapshot.generation;
      Future<String> command(String action) async {
        final result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script!,
          '-Action',
          action,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return result.stdout.toString();
      }

      await tester.pump(const Duration(seconds: 1));
      expect(await command('Read'), contains('BiliSail system media fixture'));
      await command('Pause');
      await until(() => !session.snapshots.value.desiredPlaying);
      await command('Seek');
      await until(
        () =>
            (session.snapshots.value.position.inMilliseconds - 3000).abs() <
            400,
      );
      await command('Play');
      await until(() => session.snapshots.value.desiredPlaying);
      expect(engine.currentSnapshot.generation, generation);
      await command('Stop');
      await until(() => session.media == null);
      await tester.pump(const Duration(milliseconds: 600));
      await command('Absent');
    },
  );
}
