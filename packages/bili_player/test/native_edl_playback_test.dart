import 'dart:io';

import 'package:bili_player/src/native_load_observer.dart';
import 'package:bili_player/src/native_media_options.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

// Opt-in SDK/libmpv contract probe; no display or real audio device required.
// Fixtures: video.mp4 (video-only) and audio.m4a, both at least three seconds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['BILI_TEST_NATIVE_MPV'];
  final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
  test(
    'EDL loads both tracks with headers and reuses the SDK event route',
    () async {
      mk.MediaKit.ensureInitialized(libmpv: library);
      final files = {
        '/video.mp4': await File('$directory/video.mp4').readAsBytes(),
        '/audio.m4a': await File('$directory/audio.m4a').readAsBytes(),
      };
      final local = await Directory.systemTemp.createTemp('bilisail-edl-');
      final localVideo = await File('$directory/video.mp4')
          .copy('${local.path}/视频;1.mp4');
      final localAudio = await File('$directory/audio.m4a')
          .copy('${local.path}/音频,2.m4a');
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final bytes = files[request.uri.path];
        if (bytes == null ||
            request.headers.value('X-Playback-Test') != 'pair') {
          request.response.statusCode = HttpStatus.forbidden;
        } else {
          requests.add(request.uri.path);
          final range = request.headers.value('Range');
          final start = range == null
              ? 0
              : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          if (start >= bytes.length) {
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
          } else {
            request.response.headers.set('Accept-Ranges', 'bytes');
            if (range != null) {
              request.response.statusCode = HttpStatus.partialContent;
              request.response.headers.set(
                'Content-Range',
                'bytes $start-${bytes.length - 1}/${bytes.length}',
              );
            }
            request.response.contentLength = bytes.length - start;
            request.response.add(bytes.sublist(start));
          }
        }
        await request.response.close();
      });
      final player = await createNativePlayer();
      final failures = <int>[];
      final observer = await NativeLoadObserver.attach(
        player.native,
        onFailure: failures.add,
      );
      try {
        await player.setPropertyAsync('vo', 'null');
        await player.setPropertyAsync('ao', 'null');
        await player.setPropertyAsync('vid', 'auto');
        await player.setVolume(0);
        final handle = player.nativeHandle;
        Uri uri(String path) =>
            Uri.parse('http://127.0.0.1:${server.port}$path?signature=a;b,c');
        for (final (video, audio, start, headers) in [
          (
            uri('/video.mp4'),
            uri('/audio.m4a'),
            Duration.zero,
            const {'X-Playback-Test': 'pair'},
          ),
          (
            uri('/video.mp4'),
            uri('/audio.m4a'),
            const Duration(seconds: 1),
            const {'X-Playback-Test': 'pair'},
          ),
          (
            localVideo.uri,
            localAudio.uri,
            Duration.zero,
            const <String, String>{},
          ),
        ]) {
          await player.open(
            mk.Media(
              nativeMediaUri(video, audio),
              httpHeaders: headers,
              nativeOptions: const {'force-media-title': 'EDL contract test'},
              start: start,
            ),
            play: false,
          );
          await waitForNativeState(
            ready: () =>
                observer.state.tracksReady &&
                player.state.tracks.video.any(
                  (t) => t.id != 'no' && t.id != 'auto',
                ) &&
                player.state.tracks.audio.any(
                  (t) => t.id != 'no' && t.id != 'auto',
                ),
            superseded: () => false,
            changes: [observer.state.changes, player.stream.tracks],
            failure: () => observer.state.errorCode,
            timeout: const Duration(seconds: 8),
          );
          expect(player.nativeHandle, handle);
          expect(await player.getPropertyAsync('audio-files'), isEmpty);
          expect(player.state.playing, false);
          await player.stop();
          await observer.waitUntilIdle();
          await observer.reset();
          expect(observer.state.tracksReady, false);
        }
        expect(requests, containsAll(['/video.mp4', '/audio.m4a']));
        expect(failures, isEmpty);
      } finally {
        await observer.dispose();
        await player.dispose();
        await serving.cancel();
        await server.close(force: true);
        await local.delete(recursive: true);
      }
    },
    skip: library == null || directory == null
        ? 'Set BILI_TEST_NATIVE_MPV and BILI_TEST_MEDIA_DIR for native EDL validation'
        : false,
  );
}
