import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';

/// Exercises the same engine and mounted video surface as the playback page.
Future<void> verifyAppleJoc(MediaKitEngine engine, Uri base) async {
  final directory = await Directory.systemTemp.createTemp('bilisail-joc-');
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  MediaTrack local(String name) => MediaTrack(
    uri: File('${directory.path}/$name').uri,
    requestPolicy: MediaRequestPolicy(),
  );
  MediaTrack online(String name) => MediaTrack(
    uri: base.resolve('dash/$name'),
    requestPolicy: MediaRequestPolicy(
      headers: const {'Referer': 'https://fixture.example/'},
    ),
  );
  Future<PlayerPlaybackInformation> output(bool compressed) async {
    PlayerPlaybackInformation? info;
    for (var i = 0; i < 40; i++) {
      info = await engine.inspectPlaybackInformation();
      if (info != null &&
          (compressed
              ? info.audioOutput == 'apple-joc' &&
                    info.audioOutputFormat == 'E-AC-3 JOC' &&
                    (info.appleJocRenderedPackets ?? 0) >= 4
              : info.audioOutput != null &&
                    info.audioOutput != 'apple-joc' &&
                    info.audioOutputFormat != null &&
                    !info.encodedAudioOutput)) {
        return info;
      }
      await Future<void>.delayed(const Duration(milliseconds: 75));
    }
    throw StateError(
      'Unexpected audio output: AO=${info?.audioOutput}, '
      'format=${info?.audioOutputFormat}, rendered=${info?.appleJocRenderedPackets}',
    );
  }

  try {
    for (final name in [
      'video.mp4',
      'joc.m4a',
      'joc.mkv',
      'joc.mp4',
      'ddp.m4a',
      'audio.m4a',
    ]) {
      final response = await (await http.getUrl(base.resolve(name))).close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Fixture $name');
      }
      await response
          .pipe(File('${directory.path}/$name').openWrite())
          .timeout(const Duration(seconds: 20));
    }
    for (final (label, source, joc) in <(String, ResolvedMediaSource, bool)>[
      (
        'online DASH',
        DashPairSource(video: online('video.mp4'), audio: online('joc.m4a')),
        true,
      ),
      (
        'offline DASH',
        DashPairSource(video: local('video.mp4'), audio: local('joc.m4a')),
        true,
      ),
      ('offline MKV', ProgressiveSource(local('joc.mkv')), true),
      ('offline MP4', ProgressiveSource(local('joc.mp4')), true),
      (
        'ordinary DD+',
        DashPairSource(video: local('video.mp4'), audio: local('ddp.m4a')),
        false,
      ),
      (
        'AAC',
        DashPairSource(video: local('video.mp4'), audio: local('audio.m4a')),
        false,
      ),
    ]) {
      stdout.writeln('APPLE_JOC opening=$label');
      await engine.open(source, const OpenOptions(play: true, volume: 28));
      final before = await output(joc);
      if (before.atmosSource != joc) {
        throw StateError('Wrong source profile for $label');
      }
      await engine.pause();
      await engine.seek(const Duration(seconds: 2));
      if (engine.currentSnapshot.desiredPlaying) {
        throw StateError('Seek resumed $label');
      }
      await engine.play();
      final after = await output(joc);
      for (
        var i = 0;
        i < 60 && engine.currentSnapshot.position.inMilliseconds < 2450;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (engine.currentSnapshot.position.inMilliseconds < 2450 ||
          !engine.inspectDiagnostics().hasDecodedVideo) {
        throw StateError('Video or timeline did not resume for $label');
      }
      if (label == 'offline MP4') {
        // The 48 kHz fixture contains 1,536 samples per JOC access unit.
        // Observe several queue refills after seek, beyond the native preroll.
        final first = await output(true);
        final start = engine.currentSnapshot.position;
        await Future<void>.delayed(const Duration(seconds: 3));
        final last = await output(true);
        final packets =
            last.appleJocRenderedPackets! - first.appleJocRenderedPackets!;
        final elapsed = engine.currentSnapshot.position - start;
        if (packets < 60 || elapsed < const Duration(seconds: 2)) {
          throw StateError('JOC stopped advancing: $packets packets, $elapsed');
        }
        stdout.writeln('APPLE_JOC_CONTINUITY packets=$packets media=$elapsed');
      }
      if (label == 'offline MKV') {
        await engine.setVolume(0);
        await output(true);
        await engine.setVolume(45);
        await engine.setRate(1.25);
        await output(false);
        await engine.setRate(1);
        await output(true);
        await engine.setAudioGain(3);
        await output(false);
        await engine.setAudioGain(0);
        await output(true);
      }
      await engine.pause();
      stdout.writeln(
        'APPLE_JOC_PASSED $label output=${after.audioOutput} '
        'format=${after.audioOutputFormat} rendered=${after.appleJocRenderedPackets}',
      );
    }
  } finally {
    http.close(force: true);
    await directory.delete(recursive: true);
  }
}
