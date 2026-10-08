import 'dart:convert';
import 'dart:io';

import 'package:bili_mux/bili_mux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing asset is unavailable without affecting the process', () async {
    final muxer = NativeMuxer(libraryPath: '/missing/bili_mux_library');
    expect(muxer.available, isFalse);
    await expectLater(
      muxer.merge(
        videoPath: '/video',
        audioPath: '/audio',
        outputPath: '/output',
        cancellation: MuxCancellation(),
      ),
      throwsA(
        isA<MuxException>().having(
          (e) => e.failure,
          'failure',
          MuxFailure.unavailable,
        ),
      ),
    );
  });
  test('pre-cancelled work does not need a native library', () async {
    final token = MuxCancellation()..cancel();
    await expectLater(
      NativeMuxer(libraryPath: '/missing/library').merge(
        videoPath: '/video',
        audioPath: '/audio',
        outputPath: '/output',
        cancellation: token,
      ),
      throwsA(
        isA<MuxException>().having(
          (e) => e.failure,
          'failure',
          MuxFailure.cancelled,
        ),
      ),
    );
  });

  final library = Platform.environment['BILI_MUX_LIBRARY'];
  final ffprobe = Platform.environment['BILI_MUX_FFPROBE'];
  group(
    'actual native library',
    () {
      late Directory temp;
      late NativeMuxer muxer;
      final fixtures = Directory('test/fixtures').absolute;
      setUp(() async {
        temp = await Directory.systemTemp.createTemp('bili_mux_中文_');
        muxer = NativeMuxer(libraryPath: library);
        expect(muxer.available, isTrue);
      });
      tearDown(() async => temp.delete(recursive: true));

      for (final codec in ['h264', 'hevc', 'av1']) {
        test(
          '$codec + AAC preserves both streams and their shared timeline',
          () async {
            final video = '${fixtures.path}/$codec.m4s';
            final audio = '${fixtures.path}/audio.m4a';
            final output = '${temp.path}/合并.mp4';
            var progress = 0.0;
            await muxer.merge(
              videoPath: video,
              audioPath: audio,
              outputPath: output,
              cancellation: MuxCancellation(),
              onProgress: (value) => progress = value,
            );
            expect(progress, 1);
            expect(await File(output).length(), greaterThan(0));
            if (ffprobe != null) {
              final beforeVideo = await _packets(ffprobe, video, 'v:0');
              final beforeAudio = await _packets(ffprobe, audio, 'a:0');
              final afterVideo = await _packets(ffprobe, output, 'v:0');
              final afterAudio = await _packets(ffprobe, output, 'a:0');
              _compare(beforeVideo, afterVideo);
              _compare(beforeAudio, afterAudio);
              final originalOffset =
                  _time(beforeAudio.first, 'pts_time') -
                  _time(beforeVideo.first, 'pts_time');
              final mergedOffset =
                  _time(afterAudio.first, 'pts_time') -
                  _time(afterVideo.first, 'pts_time');
              expect(mergedOffset, closeTo(originalOffset, 0.0001));
            }
          },
        );
      }
      test('cancellation waits for native file handles to close', () async {
        final token = MuxCancellation();
        final output = File('${temp.path}/cancel.mp4');
        final future = muxer.merge(
          videoPath: '${fixtures.path}/h264.m4s',
          audioPath: '${fixtures.path}/audio.m4a',
          outputPath: output.path,
          cancellation: token,
        );
        token.cancel();
        await expectLater(
          future,
          throwsA(
            isA<MuxException>().having(
              (e) => e.failure,
              'failure',
              MuxFailure.cancelled,
            ),
          ),
        );
        if (await output.exists()) await output.delete();
        expect(await output.exists(), isFalse);
      });
      test(
        'ordinary MP4 inputs can be remuxed without losing either track',
        () async {
          final first = '${temp.path}/first.mp4';
          final second = '${temp.path}/second.mp4';
          await muxer.merge(
            videoPath: '${fixtures.path}/h264.m4s',
            audioPath: '${fixtures.path}/audio.m4a',
            outputPath: first,
            cancellation: MuxCancellation(),
          );
          await muxer.merge(
            videoPath: first,
            audioPath: first,
            outputPath: second,
            cancellation: MuxCancellation(),
          );
          if (ffprobe != null) {
            for (final track in ['v:0', 'a:0']) {
              _compare(
                await _packets(ffprobe, first, track),
                await _packets(ffprobe, second, track),
              );
            }
          }
        },
      );
      test('invalid input fails and never overwrites an input', () async {
        final bad = File('${temp.path}/bad.m4s');
        await bad.writeAsBytes([1, 2, 3]);
        for (final output in [bad.path, '${temp.path}/output.mp4']) {
          await expectLater(
            muxer.merge(
              videoPath: bad.path,
              audioPath: '${fixtures.path}/audio.m4a',
              outputPath: output,
              cancellation: MuxCancellation(),
            ),
            throwsA(isA<MuxException>()),
          );
          expect(await bad.readAsBytes(), [1, 2, 3]);
        }
      });
      test(
        'concurrent merges own separate contexts and cancellation',
        () async {
          await Future.wait([
            for (var i = 0; i < 3; i++)
              muxer.merge(
                videoPath: '${fixtures.path}/h264.m4s',
                audioPath: '${fixtures.path}/audio.m4a',
                outputPath: '${temp.path}/$i.mp4',
                cancellation: MuxCancellation(),
              ),
          ]);
          expect(await temp.list().length, 3);
        },
      );
    },
    skip: library == null ? 'Set BILI_MUX_LIBRARY to run native tests' : false,
  );
}

Future<List<Map<String, Object?>>> _packets(
  String probe,
  String path,
  String track,
) async {
  final result = await Process.run(probe, [
    '-v',
    'error',
    '-select_streams',
    track,
    '-show_packets',
    '-show_data_hash',
    'sha256',
    '-show_entries',
    'packet=data_hash,pts_time,dts_time,duration_time',
    '-of',
    'json',
    path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final value = jsonDecode(result.stdout as String) as Map<String, Object?>;
  return (value['packets'] as List).cast<Map<String, Object?>>();
}

double _time(Map<String, Object?> packet, String key) {
  final value = packet[key];
  final time = value is String ? double.tryParse(value) : null;
  if (time == null || !time.isFinite) {
    fail(
      'ffprobe returned a missing or invalid $key ($value). '
      'Use the FFmpeg version pinned by bili_mux for native regression tests.',
    );
  }
  return time;
}

void _compare(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after,
) {
  expect(after.length, before.length);
  expect(after.map((e) => e['data_hash']), before.map((e) => e['data_hash']));
  for (var i = 0; i < before.length; i++) {
    for (final key in ['pts_time', 'dts_time', 'duration_time']) {
      expect(_time(after[i], key), closeTo(_time(before[i], key), 0.0001));
    }
  }
}
