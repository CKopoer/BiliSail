import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/dependencies.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'support/multi_view_binding.dart';
import 'support/native_playback_window.dart';

void main() {
  final binding =
      MultiViewIntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final withPlayback in [false, true]) {
    testWidgets('main close drains dependencies with playback=$withPlayback', (
      tester,
    ) async {
      binding.forwardNativeExitRequests = true;
      addTearDown(() => binding.forwardNativeExitRequests = false);
      final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(
        fixtures,
        isNotNull,
        reason: 'Use tool/test-windows-main-close.ps1',
      );
      final database = _DelayedCloseDatabase();
      final dependencies = await AppDependencies.create(
        credentials: _EmptyCredentials(),
        databaseOverride: database,
      );
      final session = dependencies.playback.acquire('close-probe');
      final engine = session.engine;
      var engineClosed = false;
      final subscription = engine.snapshots.listen(
        (_) {},
        onDone: () => engineClosed = true,
      );
      DetachedPlaybackWindow? playback;
      final showPlayback = ValueNotifier(withPlayback);
      var playbackCloseRequests = 0;
      Future<void>? closing;
      var requests = 0;
      var completedRequests = 0;
      var reusedCleanup = true;
      final lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          requests++;
          final next = dependencies.close();
          if (closing != null) reusedCleanup &= identical(next, closing);
          closing = next;
          await next;
          completedRequests++;
          // Observe the full native close path without terminating the test host.
          return AppExitResponse.cancel;
        },
      );
      try {
        await tester.pumpWidget(
          ValueListenableBuilder<bool>(
            valueListenable: showPlayback,
            builder: (_, visible, _) => DesktopPlaybackWindow(
              controller: dependencies.playbackWindow,
              windowFactory: ({required title, required onCloseRequested}) =>
                  playback = DetachedPlaybackWindow.create(
                    title: title,
                    onCloseRequested: onCloseRequested,
                  ),
              playback: !visible
                  ? null
                  : MaterialApp(
                      home: Scaffold(body: VideoSurface(engine: engine)),
                    ),
              onCloseRequested: () {
                playbackCloseRequests++;
                showPlayback.value = false;
              },
              onError: (error) => fail('Playback window failed: $error'),
              child: const MaterialApp(
                home: Scaffold(body: Text('Close probe')),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => tester.binding.renderViews.length == (withPlayback ? 2 : 1),
        );
        if (withPlayback) {
          final policy = MediaRequestPolicy();
          var opened = false;
          final opening = engine
              .open(
                DashPairSource(
                  video: MediaTrack(
                    uri: File('$fixtures/video.mp4').uri,
                    requestPolicy: policy,
                  ),
                  audio: MediaTrack(
                    uri: File('$fixtures/audio.m4a').uri,
                    requestPolicy: policy,
                  ),
                ),
                const OpenOptions(play: true, volume: 0),
              )
              .whenComplete(() => opened = true);
          await _until(tester, () => opened);
          await opening;
          await _until(
            tester,
            () => engine.currentSnapshot.position > Duration.zero,
          );
          final firstWindow = playback!;
          NativePlaybackWindow(firstWindow.viewId).close();
          await _until(tester, () => !firstWindow.isOpen);
          expect(playbackCloseRequests, 1);
          expect(requests, 0);
          showPlayback.value = true;
          await _until(
            tester,
            () =>
                playback != firstWindow &&
                playback!.isOpen &&
                tester.binding.renderViews.length == 2,
          );
        }
        expect(await windowManager.isPreventClose(), isFalse);

        // Send WM_CLOSE to the actual implicit main HWND. In the playback case
        // the second SDK window and native DASH audio/video are still alive.
        await windowManager.close();
        await _until(tester, () => database.closing);
        expect(requests, greaterThanOrEqualTo(1));
        expect(engineClosed, isTrue);
        if (withPlayback) expect(playback!.isOpen, isFalse);
        expect(tester.binding.renderViews.length, 1);
        expect(await windowManager.isPreventClose(), isFalse);
        expect(completedRequests, 0);
        expect(dependencies.close(), same(closing));
        await windowManager.close();
        await windowManager.close();
        await tester.pump(const Duration(milliseconds: 200));
        expect(completedRequests, 0);
        expect(database.closeCalls, 1);
        if (withPlayback) expect(playback!.isOpen, isFalse);
        expect(reusedCleanup, isTrue);

        database.allowClose.complete();
        await _until(tester, () => completedRequests == requests);
        expect(await windowManager.isPreventClose(), isFalse);
        expect(database.closeCalls, 1);
        expect(tester.takeException(), isNull);
        expect(reusedCleanup, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        if (withPlayback) await _until(tester, () => !playback!.isOpen);
        expect(tester.takeException(), isNull);
      } finally {
        if (!database.allowClose.isCompleted) database.allowClose.complete();
        await dependencies.close();
        lifecycle.dispose();
        await subscription.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        showPlayback.dispose();
      }
    });
  }
}

class _DelayedCloseDatabase extends AppDatabase {
  _DelayedCloseDatabase() : super(NativeDatabase.memory());

  final allowClose = Completer<void>();
  bool closing = false;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    closing = true;
    await allowClose.future;
    await super.close();
  }
}

class _EmptyCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'Native close regression timed out');
}
