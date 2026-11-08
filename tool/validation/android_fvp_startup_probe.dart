import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

/// Known, visibly nonblack local DASH fixture; no account or saved settings.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<Object?> request(String path, [Map<String, Object?>? body]) async {
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:18965$path'),
    );
    if (body != null) {
      req.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final response = await req.close().timeout(const Duration(seconds: 20));
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) throw StateError('Fixture request failed');
    return jsonDecode(text);
  }

  try {
    final rows = await request('/config') as List<Object?>;
    for (final row in rows) {
      final config = Map<String, Object?>.from(row as Map);
      final stage = config['name'] as String;
      final direct = config['direct'] == true;
      final play = config['play'] != false;
      final rate = (config['rate'] as num? ?? 1).toDouble();
      final start = Duration(seconds: config['startSeconds'] as int? ?? 0);
      MediaTrack track(String name) => MediaTrack(
        uri: Uri.parse(config[name] as String),
        requestPolicy: MediaRequestPolicy(
          headers: switch (config['headers']) {
            final Map values => Map<String, String>.from(values),
            _ => const {},
          },
        ),
      );
      if (config['backend'] != 'fvp') {
        throw StateError('Unsupported startup probe backend');
      }
      final engine = FvpEngine();
      final PlayerInformationSource information = engine;
      try {
        runApp(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Column(
                children: [
                  Text(stage, style: const TextStyle(color: Colors.white)),
                  Expanded(child: VideoSurface(engine: engine)),
                ],
              ),
            ),
          ),
        );
        await engine.open(
          config['progressive'] == true
              ? ProgressiveSource(track('video'))
              : DashPairSource(
                  video: track('video'),
                  audio: track('audio'),
                  duration: Duration(
                    seconds: config['durationSeconds'] as int? ?? 180,
                  ),
                ),
          OpenOptions(
            play: play,
            volume: 0,
            rate: rate,
            startPosition: start,
            androidVideoOutput: direct
                ? AndroidVideoOutputMode.directTexture
                : AndroidVideoOutputMode.renderedTexture,
          ),
        );
        final info = await information.inspectPlaybackInformation();
        if (info?.diagnostics?.hasVideoOutput != true ||
            info?.diagnostics?.hasDecodedAudio != true ||
            info?.videoOutput?.contains('(direct)') != direct ||
            engine.currentSnapshot.desiredPlaying != play) {
          throw StateError('Output or playback intent was not confirmed');
        }
        final openedAt = engine.currentSnapshot.position;
        for (final phase in ['opened', 'resumed']) {
          if (phase == 'resumed') await engine.play();
          await Future<void>.delayed(const Duration(seconds: 2));
          if (phase == 'resumed' &&
              engine.currentSnapshot.position <= openedAt) {
            throw StateError('Playback clock did not advance after playing');
          }
          final pixels = await request('/startup', {
            'stage': stage,
            'phase': phase,
          });
          await request('/event', {
            'type': 'startup-frame',
            'stage': stage,
            'phase': phase,
            'positionMs': engine.currentSnapshot.position.inMilliseconds,
            'videoOutput': info?.videoOutput,
            'hardwareDecoder': info?.hardwareDecoder,
            'pixels': pixels,
          });
        }
      } finally {
        await engine.dispose();
        runApp(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    await request('/event', {'type': 'complete'});
  } catch (error, stack) {
    debugPrint('$error\n$stack');
    await request('/event', {'type': 'failed', 'reason': error.toString()});
  } finally {
    client.close(force: true);
  }
}
