import 'package:bili_player/src/native_video_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, String> properties(
    List<int?> profiles, {
    String hwdec = 'auto',
  }) => {
    'track-list/count': '${profiles.length}',
    'hwdec': hwdec,
    'vf': '',
    'vo': 'gpu',
    'option-info/vf': '{"choices":["libplacebo"]}',
    'option-info/vo': '{"choices":["gpu","gpu-next"]}',
    for (var i = 0; i < profiles.length; i++) ...{
      'track-list/$i/type': profiles[i] == null ? 'audio' : 'video',
      'track-list/$i/dolby-vision-profile': '${profiles[i]}',
    },
  };

  test('demuxed Profile 5 is converted before the embedded renderer', () {
    final values = properties([null, 5]);
    configureNativeVideoColor(
      read: (key) => values[key] ?? '',
      write: (key, value) => values[key] = value,
    );
    expect(values['hwdec'], 'auto-copy');
    expect(values['vf'], dolbyVisionSdrFilter);
  });

  test('explicit software decoding remains software for Profile 5', () {
    final values = properties([5], hwdec: 'no');
    configureNativeVideoColor(
      read: (key) => values[key] ?? '',
      write: (key, value) => values[key] = value,
    );
    expect(values['hwdec'], 'no');
    expect(values['vf'], dolbyVisionSdrFilter);
  });

  test(
    'Android retains RPU with native HEVC and a source-specific gpu-next',
    () {
      for (final requested in ['mediacodec,auto-safe', 'no']) {
        final values = properties([5], hwdec: requested);
        var configured = false;
        expect(
          configureNativeVideoColor(
            read: (key) => values[key] ?? '',
            write: (key, value) => values[key] = value,
            isAndroid: true,
            onAndroidDolbyVision: () => configured = true,
          ),
          isTrue,
        );
        expect(configured, isTrue);
        expect(values['hwdec'], 'no');
        expect(values['vo'], 'gpu-next');
        expect(values['vf'], isEmpty);
      }
    },
  );

  test(
    'missing native conversion choices fail before mutating video output',
    () {
      for (final isAndroid in [false, true]) {
        final values = properties([5]);
        values['option-info/vf'] = '{"choices":["lavfi"]}';
        values['option-info/vo'] = '{"choices":["gpu","libmpv"]}';
        expect(
          () => configureNativeVideoColor(
            read: (key) => values[key] ?? '',
            write: (_, _) =>
                fail('Unsupported output must not decode the base layer'),
            isAndroid: isAndroid,
          ),
          throwsStateError,
        );
      }
    },
  );

  test(
    'older demuxers use a DV codec hint, while known Profile 8 stays direct',
    () {
      for (final profile in ['', '8']) {
        final values = properties([8])
          ..['track-list/0/dolby-vision-profile'] = profile;
        final mapped = configureNativeVideoColor(
          read: (key) => values[key] ?? '',
          write: (key, value) => values[key] = value,
          codecHint: 'dvh1.05.06',
        );
        expect(mapped, profile.isEmpty);
        expect(values['hwdec'], profile.isEmpty ? 'auto-copy' : 'auto');
      }
    },
  );

  test('SDR, HDR10, Profile 8 and audio retain the direct hardware path', () {
    for (final profiles in <List<int?>>[
      [],
      [null],
      [0],
      [8],
      [null, 8],
    ]) {
      final values = properties(profiles);
      configureNativeVideoColor(
        read: (key) => values[key] ?? '',
        write: (_, _) => fail('Compatible media must not be reconfigured'),
      );
    }
  });

  test('cover art is not treated as a Profile 5 video', () {
    final values = properties([5])..['track-list/0/albumart'] = 'yes';
    configureNativeVideoColor(
      read: (key) => values[key] ?? '',
      write: (_, _) => fail('Cover art must not change video processing'),
    );
  });

  test('unavailable decoder or filter cannot silently claim conversion', () {
    for (final failedProperty in ['hwdec', 'vf']) {
      final values = properties([5]);
      expect(
        () => configureNativeVideoColor(
          read: (key) => values[key] ?? '',
          write: (key, value) {
            if (key != failedProperty) values[key] = value;
          },
        ),
        throwsStateError,
      );
    }
  });
}
