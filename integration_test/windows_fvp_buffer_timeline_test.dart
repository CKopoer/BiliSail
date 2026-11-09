import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final rate in [1.0, 2.0]) {
    testWidgets(
      'fvp $rate buffer endpoint stays stable while packets are decoded',
      (tester) async {
        final directory = Platform.environment['BILI_TEST_BUFFER_DIR'];
        expect(
          directory,
          isNotNull,
          reason: 'Use tool/test-windows-buffer.ps1',
        );
        final files = {
          '/video.mp4': await File('$directory/video.mp4').readAsBytes(),
          '/audio.m4a': await File('$directory/audio.m4a').readAsBytes(),
        };
        final closing = Completer<void>();
        var holdNetwork = false;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          closing.complete();
          await server.close(force: true);
        });
        server.listen((request) async {
          try {
            final bytes = files[request.uri.path]!;
            final range = RegExp(r'^bytes=(\d+)-(\d*)$')
                .firstMatch(request.headers.value('range') ?? '');
            final start = int.parse(range?[1] ?? '0');
            final end = math.min(
              int.tryParse(range?[2] ?? '') ?? bytes.length - 1,
              bytes.length - 1,
            );
            request.response
              ..bufferOutput = false
              ..statusCode = 206
              ..headers.set('Accept-Ranges', 'bytes')
              ..headers.set(
                'Content-Range',
                'bytes $start-$end/${bytes.length}',
              )
              ..contentLength = end - start + 1;
            for (var offset = start; offset <= end; offset += 16 * 1024) {
              if (holdNetwork) {
                await closing.future;
                return;
              }
              request.response.add(
                bytes.sublist(offset, math.min(offset + 16 * 1024, end + 1)),
              );
              await request.response.flush();
              await Future.any([
                closing.future,
                Future<void>.delayed(const Duration(milliseconds: 20)),
              ]);
              if (closing.isCompleted) return;
            }
            await request.response.close();
          } on SocketException {
            // Source disposal cancels the paused response.
          } on HttpException {
            // Native preparation and disposal can cancel a Range request.
          }
        });
        final engine = FvpEngine();
        addTearDown(engine.dispose);
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        MediaTrack track(String name) => MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}/$name'),
          requestPolicy: MediaRequestPolicy(),
        );
        await engine.open(
          DashPairSource(video: track('video.mp4'), audio: track('audio.m4a')),
          OpenOptions(play: true, volume: 0, rate: rate),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (engine.currentSnapshot.buffered -
                    engine.currentSnapshot.position <
                const Duration(seconds: 30) &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          engine.currentSnapshot.buffered - engine.currentSnapshot.position,
          greaterThan(const Duration(seconds: 30)),
        );
        holdNetwork = true;
        final samples = <PlaybackSnapshot>[];
        final subscription = engine.snapshots.listen(samples.add);
        await tester.pump(const Duration(seconds: 8));
        await subscription.cancel();
        final regressions = <int>[];
        for (var i = 1; i < samples.length; i++) {
          final previous = samples[i - 1];
          final current = samples[i];
          if (current.position >= previous.position &&
              current.buffered < previous.buffered) {
            regressions.add(
              (previous.buffered - current.buffered).inMilliseconds,
            );
          }
        }
        debugPrint(
          'FVP_BUFFER rate=$rate samples=${samples.length} regressions=$regressions',
        );
        expect(samples.length, greaterThan(20));
        expect(regressions, isEmpty);
        expect(
          engine.currentSnapshot.position,
          greaterThan(samples.first.position),
        );
        expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
        await engine.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
