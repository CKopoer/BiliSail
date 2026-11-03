import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_video_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, String> metadata() => {
    'track-list/count': '3',
    'track-list/0/type': 'audio',
    'track-list/1/type': 'video',
    'track-list/1/albumart': 'yes',
    'track-list/1/demux-w': '100',
    'track-list/1/demux-h': '100',
    'track-list/2/type': 'video',
    'track-list/2/demux-w': '1920',
    'track-list/2/demux-h': '1080',
  };

  test('startup dimensions skip audio and album artwork', () {
    final values = metadata();
    expect(
      nativeVideoSurfaceDimensions((name) => values[name] ?? ''),
      const VideoDimensions(1920, 1080),
    );
  });

  test('startup dimensions respect pixel aspect ratio and rotation', () {
    final values = metadata()
      ..['track-list/2/demux-w'] = '720'
      ..['track-list/2/demux-h'] = '576'
      ..['track-list/2/demux-par'] = '1.4222222222';
    for (final rotation in [0, 90, 180, 270, -90]) {
      values['track-list/2/demux-rotation'] = '$rotation';
      expect(
        nativeVideoSurfaceDimensions((name) => values[name] ?? ''),
        rotation % 180 == 90
            ? const VideoDimensions(576, 1024)
            : const VideoDimensions(1024, 576),
      );
    }
  });

  test('missing and invalid dimension hints use decoded parameters later', () {
    for (final invalid in ['', '0', '1', '-100', '16385', '1.5', 'NaN']) {
      for (final field in ['demux-w', 'demux-h']) {
        final values = metadata()..['track-list/2/$field'] = invalid;
        expect(
          nativeVideoSurfaceDimensions((name) => values[name] ?? ''),
          isNull,
        );
      }
    }
    for (final par in ['0', '-1', 'Infinity', 'NaN', '17']) {
      final values = metadata()..['track-list/2/demux-par'] = par;
      expect(
        nativeVideoSurfaceDimensions((name) => values[name] ?? ''),
        isNull,
      );
    }
  });

  test('untrusted track counts cannot cause an unbounded property walk', () {
    for (final count in ['0', '-1', '129', '9999999999', 'invalid']) {
      final reads = <String>[];
      expect(
        nativeVideoSurfaceDimensions((name) {
          reads.add(name);
          return name == 'track-list/count' ? count : '';
        }),
        isNull,
      );
      expect(reads, ['track-list/count']);
    }
  });
}
