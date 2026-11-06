import 'dart:async';
import 'dart:convert';

import 'package:bili_player/src/native_playback_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> drainReads(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(Duration.zero);
  }
}

void main() {
  test(
    'fixed properties retain finite clocks, zero drops and decoder identity',
    () {
      final sample = NativePlaybackSample.fromProperties(
        {
          'speed': '2.0',
          'avsync': '-0.125',
          'frame-drop-count': '0',
          'hwdec-current': 'mediacodec',
          'mpv-version': 'mpv v0.40.0-SECRET/path',
          'ffmpeg-version': 'n8.0.1-private-SECRET',
          'video-format': 'h264',
          'audio-codec-name': 'aac',
          'pause': 'no',
          'video-pts': 'NaN',
          'audio-pts': 'Infinity',
          'filename': 'https://private.example/?token=SECRET',
          'hwdec': 'Cookie=SECRET',
          'current-vo': '/private/SECRET',
        },
        elapsedMs: 1000,
        durationMs: 12,
      );
      expect(sample.values['speed'], 2);
      expect(sample.values['avsync'], -0.125);
      expect(sample.values['frame-drop-count'], 0);
      expect(sample.values['hwdec-current'], 'mediacodec');
      expect(sample.values['pause'], false);
      expect(sample.values['mpv-version'], '0.40.0');
      expect(sample.values['ffmpeg-version'], '8.0.1');
      expect(
        NativePlaybackSample.fromProperties(
          {'ffmpeg-version': 'N-127388-gSECRET'},
          elapsedMs: 0,
          durationMs: 0,
        ).values['ffmpeg-version'],
        'N-127388',
      );
      expect(
        sample.unavailable,
        containsAll(['video-pts', 'audio-pts', 'hwdec', 'current-vo']),
      );
      expect(sample.values.containsKey('video-pts'), isFalse);
      expect(jsonEncode(sample.toJson()), isNot(contains('SECRET')));
      expect(() => sample.values['speed'] = 3, throwsUnsupportedError);
    },
  );

  testWidgets(
    'periodic baseline, held and restored native speed stay observable',
    (tester) async {
      var speed = '1';
      var active = true;
      final samples = <NativePlaybackSample>[];
      final sampler = NativePlaybackDiagnostics(
        read: (key) async => key == 'speed' ? speed : '',
        isCurrent: () => true,
        shouldSample: () => active,
        onSample: samples.add,
      );
      addTearDown(sampler.dispose);
      sampler.sample();
      await tester.pump();
      await drainReads(tester);
      speed = '2';
      await tester.pump(const Duration(seconds: 1));
      await drainReads(tester);
      speed = '1';
      await tester.pump(const Duration(seconds: 1));
      await drainReads(tester);
      expect(samples.map((s) => s.values['speed']), [1, 2, 1]);
      active = false;
      await tester.pump(const Duration(seconds: 3));
      expect(samples, hasLength(3));
      sampler.dispose();
    },
  );

  testWidgets(
    'timeout reports partial evidence without overlapping or growing reads',
    (tester) async {
      final hung = Completer<String>();
      final samples = <NativePlaybackSample>[];
      var reads = 0;
      final sampler = NativePlaybackDiagnostics(
        read: (key) {
          reads++;
          return key == 'avsync'
              ? hung.future
              : Future.value(key == 'speed' ? '2' : '');
        },
        isCurrent: () => true,
        shouldSample: () => true,
        onSample: samples.add,
      );
      addTearDown(sampler.dispose);
      sampler.sample();
      sampler.sample();
      await tester.pump();
      await drainReads(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(samples.single.timedOut, isTrue);
      expect(samples.single.values['speed'], 2);
      expect(samples.single.unavailable, contains('avsync'));
      await tester.pump(const Duration(seconds: 5));
      expect(reads, NativePlaybackSample.properties.length);
      expect(samples, hasLength(1));
      hung.complete('0.1');
      await tester.pump();
      expect(samples, hasLength(1));
      sampler.sample();
      await tester.pump();
      await drainReads(tester);
      expect(samples.last.values['avsync'], 0.1);
      sampler.dispose();
    },
  );

  testWidgets(
    'unsupported properties, source replacement and disposal are isolated',
    (tester) async {
      var current = true;
      final pending = Completer<String>();
      final samples = <NativePlaybackSample>[];
      final sampler = NativePlaybackDiagnostics(
        read: (key) => key == 'speed'
            ? pending.future
            : Future.error(StateError('SECRET')),
        isCurrent: () => current,
        shouldSample: () => true,
        onSample: samples.add,
      );
      sampler.sample();
      current = false;
      pending.complete('2');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(samples, isEmpty);
      sampler.dispose();
      sampler.sample();
      await tester.pump(const Duration(seconds: 2));
      expect(samples, isEmpty);
    },
  );
}
