import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/android_video_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = VideoDimensions(3840, 2160);

  test('4K decode needs only a 1080p texture on the landscape phone', () {
    expect(
      androidVideoViewport(source, physicalWidth: 2400, physicalHeight: 1080),
      const VideoDimensions(1920, 1080),
    );
    expect(source, const VideoDimensions(3840, 2160));
  });

  test('portrait and square sources retain their own aspect ratio', () {
    expect(
      androidVideoViewport(
        const VideoDimensions(2160, 3840),
        physicalWidth: 1080,
        physicalHeight: 2400,
      ),
      const VideoDimensions(1080, 1920),
    );
    expect(
      androidVideoViewport(
        const VideoDimensions(2160, 2160),
        physicalWidth: 2400,
        physicalHeight: 1080,
      ),
      const VideoDimensions(1080, 1080),
    );
  });

  test(
    'a zoomed surface reserves its paint pixels up to source resolution',
    () {
      for (final scale in [1, 2]) {
        expect(
          androidVideoViewport(
            source,
            physicalWidth: 3840.0 * scale,
            physicalHeight: 2160.0 * scale,
          ),
          source,
        );
      }
      expect(
        androidVideoViewport(
          const VideoDimensions(640, 360),
          physicalWidth: 2400,
          physicalHeight: 1080,
        ),
        const VideoDimensions(640, 360),
      );
    },
  );

  test(
    'fractional pixels round upwards without losing more than one pixel',
    () {
      expect(
        androidVideoViewport(
          source,
          physicalWidth: 1920.1,
          physicalHeight: 1080.1,
        ),
        const VideoDimensions(1921, 1081),
      );
    },
  );

  for (final invalid in [0.0, -1.0, 1.0, double.nan, double.infinity]) {
    test('unavailable viewport $invalid retains valid startup dimensions', () {
      expect(
        androidVideoViewport(
          source,
          physicalWidth: invalid,
          physicalHeight: 1080,
        ),
        source,
      );
      expect(
        androidVideoViewport(
          source,
          physicalWidth: 1920,
          physicalHeight: invalid,
        ),
        source,
      );
    });
  }

  test(
    'queued obsolete layouts are skipped and duplicate requests coalesce',
    () async {
      final writes = <VideoDimensions>[];
      final sizer = AndroidVideoSurfaceSizer(
        apply: (size) async => writes.add(size),
        isCurrent: () => true,
      );
      final small = sizer.request(const VideoDimensions(640, 360));
      final large = sizer.request(const VideoDimensions(1920, 1080));
      final duplicate = sizer.request(const VideoDimensions(1920, 1080));
      await Future.wait([small, large, duplicate]);
      expect(writes, [const VideoDimensions(1920, 1080)]);
      expect(sizer.applied, const VideoDimensions(1920, 1080));
    },
  );

  test(
    'a resize already in native code is followed by the latest layout',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final writes = <VideoDimensions>[];
      final sizer = AndroidVideoSurfaceSizer(
        isCurrent: () => true,
        apply: (size) async {
          writes.add(size);
          if (writes.length == 1) {
            started.complete();
            await release.future;
          }
        },
      );
      final first = sizer.request(const VideoDimensions(640, 360));
      await started.future;
      final last = sizer.request(const VideoDimensions(1920, 1080));
      release.complete();
      await Future.wait([first, last]);
      expect(writes, [
        const VideoDimensions(640, 360),
        const VideoDimensions(1920, 1080),
      ]);
      expect(sizer.applied, const VideoDimensions(1920, 1080));
    },
  );

  test(
    'source invalidation prevents queued work and stale applied dimensions',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var current = true;
      var writes = 0;
      final sizer = AndroidVideoSurfaceSizer(
        isCurrent: () => current,
        apply: (_) async {
          writes++;
          started.complete();
          await release.future;
        },
      );
      final first = sizer.request(source);
      await started.future;
      final queued = sizer.request(const VideoDimensions(1920, 1080));
      current = false;
      sizer.invalidate();
      release.complete();
      await Future.wait([first, queued]);
      expect(writes, 1);
      expect(sizer.applied, isNull);
    },
  );

  test(
    'failed resize reports its error and permits a retry of the same size',
    () async {
      var attempts = 0;
      final sizer = AndroidVideoSurfaceSizer(
        isCurrent: () => true,
        apply: (_) async {
          if (++attempts == 1) throw StateError('native output unavailable');
        },
      );
      await expectLater(sizer.request(source), throwsStateError);
      await sizer.request(source);
      expect(attempts, 2);
      expect(sizer.applied, source);
    },
  );

  test(
    'a new owner must reapply the buffer even when its cap is unchanged',
    () async {
      var writes = 0;
      final sizer = AndroidVideoSurfaceSizer(
        isCurrent: () => true,
        apply: (_) async => writes++,
      );
      await sizer.request(source);
      sizer.invalidate();
      expect(sizer.applied, isNull);
      await sizer.request(source);
      expect(writes, 2);
      expect(sizer.applied, source);
    },
  );

  test(
    'upstream decoded-size reset can force restoration of the same cap',
    () async {
      var writes = 0;
      final sizer = AndroidVideoSurfaceSizer(
        isCurrent: () => true,
        apply: (_) async => writes++,
      );
      await sizer.request(source);
      await sizer.request(source);
      await sizer.request(source, force: true);
      expect(writes, 2);
    },
  );
}
