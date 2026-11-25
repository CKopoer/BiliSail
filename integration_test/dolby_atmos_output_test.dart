import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('DD+ JOC reaches the selected audio renderer', (tester) async {
    const directory = String.fromEnvironment('ATMOS_FIXTURES');
    expect(directory, isNotEmpty);
    final engine = MediaKitEngine();
    MediaTrack track(String name, [String? codec]) => MediaTrack(
      uri: File('$directory/$name').uri,
      codec: codec,
      requestPolicy: MediaRequestPolicy(),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    const referer = 'https://fixture.example/';
    final served = <String>{};
    var ranged = false;
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      final response = request.response;
      if (request.headers.value('referer') != referer ||
          !const {'video.mp4', 'joc.m4a'}.contains(name)) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      if (request.uri.path.startsWith('/redirect/')) {
        await response.redirect(base.resolve('/data/$name'));
        return;
      }
      final bytes = await File('$directory/$name').readAsBytes();
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range ?? '');
      final start = match == null ? 0 : int.parse(match.group(1)!);
      final end = (int.tryParse(match?.group(2) ?? '') ?? bytes.length - 1)
          .clamp(0, bytes.length - 1);
      if (start > end) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }
      served.add(name);
      ranged |= start > 0;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (match != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${bytes.length}',
        );
      }
      response.contentLength = end - start + 1;
      try {
        response.add(bytes.sublist(start, end + 1));
        await response.close();
      } on SocketException {
        // The native demuxer can abandon this read to seek to another offset.
      }
    });
    MediaTrack network(String name, String codec) => MediaTrack(
      uri: base.resolve('/redirect/$name'),
      codec: codec,
      requestPolicy: MediaRequestPolicy(headers: const {'Referer': referer}),
    );
    final windowsCarrier =
        Platform.isWindows &&
        await const MethodChannel('bilisail/audio_passthrough')
                .invokeMethod<bool>('acceptsEac3') ==
            true;
    Future<void> settling(Future<void> operation) async {
      var done = false;
      Object? failure;
      final future = operation.then(
        (_) => done = true,
        onError: (Object e) {
          failure = e;
          done = true;
        },
      );
      while (!done) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await future;
      if (failure case final error?) throw error;
    }

    try {
      initializePlayerBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      for (final (name, source, atmos) in <(String, ResolvedMediaSource, bool)>[
        (
          'dash',
          DashPairSource(
            video: track('video.mp4'),
            audio: track('joc.m4a', 'ec-3'),
          ),
          true,
        ),
        ('mkv', ProgressiveSource(track('joc.mkv')), true),
        (
          'http-dash',
          DashPairSource(
            video: network('video.mp4', 'avc1'),
            audio: network('joc.m4a', 'ec-3'),
          ),
          true,
        ),
        if (Platform.isAndroid)
          ('p5-joc', ProgressiveSource(track('p5-joc.mp4', 'dvh1')), true),
        (
          'audio-only',
          ProgressiveSource(track('joc.m4a', 'ec-3'), isAudioOnly: true),
          true,
        ),
        (
          'ordinary',
          DashPairSource(
            video: track('video.mp4'),
            audio: track('ddp.m4a', 'ec-3'),
          ),
          false,
        ),
        (
          'aac',
          DashPairSource(
            video: track('video.mp4'),
            audio: track('aac.m4a', 'mp4a.40.2'),
          ),
          false,
        ),
      ]) {
        await settling(
          engine.open(
            source,
            OpenOptions(play: true, volume: Platform.isWindows ? 100 : 2),
          ),
        );
        final watch = Stopwatch()..start();
        while (engine.currentSnapshot.position <
                const Duration(milliseconds: 450) &&
            watch.elapsed < const Duration(seconds: 8)) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
        final info = await engine.inspectPlaybackInformation();
        // These fields come exclusively from the selected renderer and are safe to record.
        debugPrint(
          'Dolby sample $name: ${info?.backend} / ${info?.audioCodec} / ${info?.audioDecoder} / ${info?.audioOutput} / ${info?.audioOutputFormat} / channels=${info?.diagnostics?.audioChannels} / JOC=${info?.atmosSource}',
        );
        expect(info?.atmosSource, atmos);
        if (Platform.isAndroid && atmos) {
          expect(info?.backend, 'Android Media3');
          expect(info?.audioCodec, 'audio/eac3-joc');
          expect(info?.audioOutputFormat, isNotNull);
          if (name == 'p5-joc') expect(info?.videoCodec, 'video/dolby-vision');
        }
        if (Platform.isWindows && name == 'dash') {
          expect(info?.audioOutputFormat?.startsWith('spdif'), windowsCarrier);
        }
        if (name == 'http-dash') {
          expect(served, {'video.mp4', 'joc.m4a'});
          // mpv can retain this entire short sample in its demux cache.
          if (Platform.isAndroid) expect(ranged, isTrue);
        }
        await settling(engine.pause());
        await settling(engine.seek(const Duration(seconds: 2)));
        expect(engine.currentSnapshot.desiredPlaying, false);
        await settling(engine.setVolume(0));
        await settling(engine.setRate(1.5));
        await settling(engine.play());
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await engine.dispose();
      await server.close(force: true);
    }
  });
}
