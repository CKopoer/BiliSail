import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/src/native_media_options.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['BILI_TEST_NATIVE_MPV'];
  final directory = Platform.environment['BILI_TEST_HTTP_AUDIO_DIR'];
  final fixture = Platform.environment['BILI_TEST_TLS_SERVER'];
  for (final track in ['audio', 'video']) {
    for (final legacy in [true, false]) {
      test(
        '${legacy ? 'control hangs' : 'native reconnect recovers'} '
        'after an incomplete $track TLS record',
        () async {
          mk.MediaKit.ensureInitialized(libmpv: library);
          final server = await Process.start('python', [
            fixture!,
            directory!,
            track,
          ]);
          final ready = Completer<int>();
          final requests = <Map<String, Object?>>[];
          final output = server.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                final value = jsonDecode(line) as Map<String, Object?>;
                if (value['port'] case final int port) {
                  ready.complete(port);
                } else {
                  requests.add(value);
                }
              });
          final errors = server.stderr.drain<void>();
          mk.Player? player;
          try {
            final port = await ready.future.timeout(
              const Duration(seconds: 10),
            );
            player = await createNativePlayer();
            await player.setPropertyAsync('vo', 'null');
            await player.setPropertyAsync('ao', 'null');
            await player.setPropertyAsync('vid', 'auto');
            // Only this isolated loopback fixture uses a self-signed cert.
            // No system trust-store or production verification changes.
            await player.setPropertyAsync('tls-verify', 'no');
            if (legacy) {
              await player.setPropertyAsync('stream-lavf-o', '');
            } else {
              expect(
                await player.getPropertyAsync('stream-lavf-o'),
                'rw_timeout=5000000',
              );
            }
            await player.setRate(4);
            await player.setVolume(0);
            Uri uri(String name) => Uri.parse('https://127.0.0.1:$port/$name');
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
            while (player.state.position < const Duration(seconds: 35) &&
                watch.elapsed < Duration(seconds: legacy ? 12 : 20)) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            final retries = requests.where(
              (request) =>
                  request['track'] == track && request['truncated'] == false,
            );
            if (legacy) {
              expect(
                player.state.position,
                lessThan(const Duration(seconds: 35)),
              );
              expect(await player.getPropertyAsync('paused-for-cache'), 'yes');
              expect(await player.getPropertyAsync('eof-reached'), 'no');
              expect(retries, isEmpty);
            } else {
              expect(
                player.state.position,
                greaterThanOrEqualTo(const Duration(seconds: 35)),
              );
              expect(retries, isNotEmpty);
              expect(retries.first['offset'], greaterThan(0));
              expect(await player.getPropertyAsync('paused-for-cache'), 'no');
              final audio = double.tryParse(
                await player.getPropertyAsync('audio-pts'),
              );
              expect(audio, isNotNull);
              expect(audio!, greaterThan(34));
              expect(
                (audio - player.state.position.inMicroseconds / 1e6).abs(),
                lessThan(0.5),
              );
            }
            // Reconnection stays inside the original native playlist entry.
            expect(await player.getPropertyAsync('playlist-count'), '1');
            expect(await player.getPropertyAsync('playlist/0/id'), '1');
          } finally {
            await player?.dispose();
            await server.stdin.close();
            try {
              expect(
                await server.exitCode.timeout(const Duration(seconds: 5)),
                0,
              );
            } on TimeoutException {
              server.kill();
              rethrow;
            } finally {
              await output.cancel();
              await errors;
            }
          }
        },
        timeout: const Timeout(Duration(seconds: 40)),
        skip: library == null || directory == null || fixture == null
            ? 'Use tool/test-windows-http-audio.ps1'
            : false,
      );
    }
  }
}
