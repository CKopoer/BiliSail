import 'dart:io';
import 'dart:math' as math;

import 'package:bili_player/src/native_media_options.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

// Real SDK/libmpv regression; null outputs verify packet delivery and decoding.
// tool/test-windows-http-audio.ps1 generates the public, synthetic fixtures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['BILI_TEST_NATIVE_MPV'];
  final directory = Platform.environment['BILI_TEST_HTTP_AUDIO_DIR'];
  for (final legacyCurl in [true, false]) {
    test(
      legacyCurl
          ? 'control: unbounded curl responses exhaust retries and lose audio'
          : 'PiliPlus lavf path preserves audio across repeated partial responses',
      () async {
        mk.MediaKit.ensureInitialized(libmpv: library);
        final media = {
          '/video': await File('$directory/video.mp4').readAsBytes(),
          '/audio': await File('$directory/audio.m4a').readAsBytes(),
        };
        const cutoff = 1024 * 1024 + 32768;
        expect(media['/audio']!.length, greaterThan(cutoff * 6));
        final audioOffsets = <int>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final serving = server.listen((request) async {
          try {
            final bytes = media[request.uri.path]!;
            final range = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(
              request.headers.value(HttpHeaders.rangeHeader) ?? 'bytes=0-',
            )!;
            final start = int.parse(range[1]!);
            if (start >= bytes.length) {
              request.response.statusCode = 416;
              await request.response.close();
              return;
            }
            final end = math.min(
              int.tryParse(range[2] ?? '') ?? bytes.length - 1,
              bytes.length - 1,
            );
            final audio = request.uri.path == '/audio';
            if (audio) audioOffsets.add(start);
            request.response
              ..statusCode = 206
              ..contentLength = end - start + 1
              ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
              ..headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes $start-$end/${bytes.length}',
              );
            final socket = await request.response.detachSocket();
            // Advertise the full object, then interrupt every long audio read.
            // Neither native path sees a synthetic error/event injection.
            socket.add(
              bytes.sublist(
                start,
                math.min(end + 1, start + (audio ? cutoff : bytes.length)),
              ),
            );
            await socket.flush();
            await socket.close();
          } on IOException {
            // Source disposal cancels outstanding native reads.
          }
        });
        final player = await createNativePlayer();
        final logs = <mk.PlayerLog>[];
        final subscription = player.stream.log.listen(logs.add);
        try {
          await player.setPropertyAsync('vo', 'null');
          await player.setPropertyAsync('ao', 'null');
          await player.setPropertyAsync('vid', 'auto');
          if (legacyCurl) await player.setPropertyAsync('curl-enabled', 'yes');
          expect(
            await player.getPropertyAsync('curl-enabled'),
            legacyCurl ? 'yes' : 'no',
          );
          await player.setVolume(0);
          await player.setRate(4);
          Uri uri(String track) =>
              Uri.parse('http://127.0.0.1:${server.port}/$track');
          await player.open(
            mk.Media(
              nativeMediaUri(uri('video'), uri('audio')),
              nativeOptions: nativeCacheOptions(
                live: false,
                window: const Duration(seconds: 16),
                rate: 4,
              ),
            ),
          );
          final watch = Stopwatch()..start();
          const target = Duration(seconds: 230);
          while (player.state.position < target) {
            if (watch.elapsed > const Duration(seconds: 80)) {
              fail(
                'Native playback did not reach the audio regression window.',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          final audioPts = double.tryParse(
            await player.getPropertyAsync('audio-pts'),
          );
          final audioDecodeErrors = logs.where(
            (log) =>
                log.prefix == 'ad' && log.text.contains('Error decoding audio'),
          );
          if (legacyCurl) {
            expect(
              logs.any(
                (log) =>
                    log.prefix == 'curl' &&
                    log.text.startsWith('transfer failed:'),
              ),
              true,
            );
            expect(audioDecodeErrors, isNotEmpty);
            expect(audioPts, isNull);
          } else {
            expect(audioOffsets.length, greaterThan(6));
            expect(
              audioOffsets,
              containsAll([for (var i = 0; i < 7; i++) cutoff * i]),
            );
            expect(audioPts, isNotNull);
            expect(audioPts!, greaterThan(229));
            expect(audioDecodeErrors, isEmpty);
            expect(logs.any((log) => log.prefix == 'curl'), false);
          }
          expect(player.state.completed, false);
          expect(
            player.state.tracks.video.any(
              (track) => track.id != 'auto' && track.id != 'no',
            ),
            true,
          );
        } finally {
          await subscription.cancel();
          await player.dispose();
          await serving.cancel();
          await server.close(force: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: library == null || directory == null
          ? 'Use tool/test-windows-http-audio.ps1'
          : false,
    );
  }
}
