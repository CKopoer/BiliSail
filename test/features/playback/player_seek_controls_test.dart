import 'dart:async';

import 'package:bilisail/features/playback/domain/playback_timeline.dart';
import 'package:bilisail/features/playback/presentation/player_seek_controls.dart';
import 'package:bilisail/shared/ui/storyboard_thumbnail.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('relative preview follows the finger and seeks once on release', (
    tester,
  ) async {
    final state = _State();
    await tester.pumpWidget(_app(state));
    final drag = await tester.startGesture(const Offset(100, 100));
    await drag.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(state.preview.value, const Duration(seconds: 90));
    expect(find.text('01:30 / 10:00'), findsOneWidget);
    final card = tester.getRect(
      find.byKey(const ValueKey('player-swipe-seek-preview')),
    );
    expect(card.center, const Offset(200, 100));
    expect(state.seeks, isEmpty);

    // Playback keeps advancing independently; the gesture retains its anchor.
    state.position = const Duration(seconds: 65);
    await drag.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(state.preview.value, const Duration(seconds: 78));
    expect(state.requests, 1);
    expect(state.seeks, isEmpty);
    await drag.up();
    await tester.pump();
    expect(state.seeks, [const Duration(seconds: 78)]);
    expect(state.preview.value, isNull);
    expect(
      find.byKey(const ValueKey('player-swipe-seek-preview')),
      findsNothing,
    );
  });

  testWidgets('short clips use their duration and clamp at both endpoints', (
    tester,
  ) async {
    final state = _State()..position = const Duration(seconds: 10);
    await tester.pumpWidget(_app(state, duration: const Duration(seconds: 30)));
    final drag = await tester.startGesture(const Offset(200, 100));
    await drag.moveBy(const Offset(-400, 0));
    await tester.pump();
    expect(state.preview.value, Duration.zero);
    await drag.moveBy(const Offset(500, 0));
    await tester.pump();
    expect(state.preview.value, const Duration(milliseconds: 17500));
    await drag.moveBy(const Offset(1000, 0));
    await tester.pump();
    expect(state.preview.value, const Duration(seconds: 30));
    await drag.up();
    expect(state.seeks, [const Duration(seconds: 30)]);
  });

  testWidgets('many small events retain precision without rebuilding picture', (
    tester,
  ) async {
    final state = _State();
    var builds = 0;
    await tester.pumpWidget(
      _app(
        state,
        picture: Builder(
          builder: (_) {
            builds++;
            return const ColoredBox(color: Colors.blue);
          },
        ),
      ),
    );
    final before = builds;
    final drag = await tester.startGesture(const Offset(100, 100));
    await drag.moveBy(const Offset(20, 0));
    for (var i = 0; i < 100; i++) {
      await drag.moveBy(const Offset(.1, 0));
      await tester.pump();
    }
    expect(state.preview.value, const Duration(seconds: 69));
    expect(state.requests, 1);
    expect(state.seeks, isEmpty);
    expect(builds, before);
    await drag.up();
    expect(state.seeks, [const Duration(seconds: 69)]);
  });

  testWidgets('returning to the anchor does not send a redundant seek', (
    tester,
  ) async {
    final state = _State();
    await tester.pumpWidget(_app(state));
    final drag = await tester.startGesture(const Offset(100, 100));
    await drag.moveBy(const Offset(60, 0));
    await drag.moveBy(const Offset(-60, 0));
    await drag.up();
    await tester.pump();
    expect(state.seeks, isEmpty);
    expect(state.preview.value, isNull);
  });

  for (final releaseSecond in [false, true]) {
    testWidgets(
      'an older seek cannot clear a newer ${releaseSecond ? 'seek' : 'drag'} preview',
      (tester) async {
        final state = _State();
        final firstSeek = Completer<void>();
        state.nextSeek = firstSeek;
        await tester.pumpWidget(_app(state));
        final first = await tester.startGesture(const Offset(100, 100));
        await first.moveBy(const Offset(100, 0));
        await first.up();
        await tester.pump();
        expect(state.preview.value, const Duration(seconds: 90));
        expect(
          find.byKey(const ValueKey('player-swipe-seek-preview')),
          findsNothing,
        );

        final secondSeek = Completer<void>();
        final second = await tester.startGesture(const Offset(100, 100));
        await second.moveBy(const Offset(60, 0));
        if (releaseSecond) {
          state.nextSeek = secondSeek;
          await second.up();
        }
        await tester.pump();
        firstSeek.complete();
        await tester.pump();
        expect(state.preview.value, const Duration(seconds: 78));
        expect(
          find.byKey(const ValueKey('player-swipe-seek-preview')),
          releaseSecond ? findsNothing : findsOneWidget,
        );
        if (releaseSecond) {
          secondSeek.complete();
        } else {
          await second.up();
        }
        await tester.pump();
        expect(state.preview.value, isNull);
        expect(state.seeks, [
          const Duration(seconds: 90),
          const Duration(seconds: 78),
        ]);
      },
    );
  }

  for (final action in ['source', 'disabled', 'background', 'dispose']) {
    testWidgets('$action invalidates a pending seek preview', (tester) async {
      final state = _State();
      final pendingSeek = Completer<void>();
      state.nextSeek = pendingSeek;
      await tester.pumpWidget(_app(state));
      final drag = await tester.startGesture(const Offset(100, 100));
      await drag.moveBy(const Offset(100, 0));
      await drag.up();
      await tester.pump();
      expect(state.preview.value, const Duration(seconds: 90));
      switch (action) {
        case 'source':
          await tester.pumpWidget(_app(state, generation: 2));
        case 'disabled':
          await tester.pumpWidget(_app(state, enabled: false));
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
          // The presenting view owns and disposes the notifier.
          state.preview.dispose();
      }
      await tester.pump();
      if (action != 'dispose') expect(state.preview.value, isNull);
      pendingSeek.complete();
      await tester.pump();
      if (action != 'dispose') expect(state.preview.value, isNull);
      expect(state.seeks, [const Duration(seconds: 90)]);
      expect(tester.takeException(), isNull);
      if (action == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'a second finger before recognition blocks until all fingers lift',
    (tester) async {
      final state = _State();
      await tester.pumpWidget(_app(state));
      final first = await tester.startGesture(const Offset(100, 100));
      final second = await tester.startGesture(
        const Offset(200, 100),
        pointer: 2,
      );
      await second.up();
      await first.moveBy(const Offset(80, 0));
      await first.up();
      expect(state.requests, 0);
      expect(state.seeks, isEmpty);
      await tester.dragFrom(const Offset(100, 100), const Offset(80, 0));
      expect(state.seeks, [const Duration(seconds: 84)]);
    },
  );

  for (final action in [
    'disabled',
    'zero duration',
    'mouse',
    'trackpad',
    'vertical',
    'jitter',
  ]) {
    testWidgets('$action does not preview or seek', (tester) async {
      final state = _State();
      await tester.pumpWidget(
        _app(
          state,
          enabled: action != 'disabled',
          duration: action == 'zero duration'
              ? Duration.zero
              : const Duration(minutes: 10),
        ),
      );
      final drag = await tester.startGesture(
        const Offset(100, 100),
        kind: switch (action) {
          'mouse' => PointerDeviceKind.mouse,
          'trackpad' => PointerDeviceKind.trackpad,
          _ => PointerDeviceKind.touch,
        },
      );
      await drag.moveBy(switch (action) {
        'vertical' => const Offset(0, 50),
        'jitter' => const Offset(2, 0),
        _ => const Offset(100, 0),
      });
      await drag.up();
      await tester.pump();
      expect(state.preview.value, isNull);
      expect(state.requests, 0);
      expect(state.seeks, isEmpty);
    });
  }

  for (final action in [
    'disabled',
    'source',
    'duration',
    'resize',
    'background',
    'cancel',
    'second finger',
    'modal',
    'dispose',
  ]) {
    testWidgets('$action discards the gesture without a seek', (tester) async {
      final state = _State();
      await tester.pumpWidget(_app(state));
      final drag = await tester.startGesture(const Offset(100, 100));
      await drag.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(state.preview.value, isNotNull);
      switch (action) {
        case 'disabled':
          await tester.pumpWidget(_app(state, enabled: false));
        case 'source':
          await tester.pumpWidget(_app(state, generation: 2));
        case 'duration':
          await tester.pumpWidget(
            _app(state, duration: const Duration(minutes: 5)),
          );
        case 'resize':
          await tester.pumpWidget(_app(state, width: 300));
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        case 'cancel':
          await drag.cancel();
        case 'second finger':
          final second = await tester.startGesture(
            const Offset(200, 100),
            pointer: 2,
          );
          await second.up();
        case 'modal':
          final context = tester.element(find.byType(PlayerSeekControls));
          showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('Modal')),
          );
          await tester.pump();
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      if (action != 'cancel') {
        await drag.moveBy(const Offset(20, 0));
        await drag.up();
      }
      await tester.pump();
      expect(state.seeks, isEmpty);
      if (action != 'dispose') expect(state.preview.value, isNull);
      if (action == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('player-swipe-seek-preview')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'late storyboard uses the current target without restarting drag',
    (tester) async {
      final state = _State();
      await tester.pumpWidget(_app(state));
      final drag = await tester.startGesture(const Offset(100, 100));
      await drag.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(find.byType(StoryboardThumbnail), findsNothing);
      final storyboard = VideoStoryboard(
        columns: 2,
        rows: 1,
        tileWidth: 160,
        tileHeight: 90,
        images: [Uri.parse('https://i0.hdslb.com/test.jpg')],
        times: const [Duration.zero, Duration(seconds: 80)],
      );
      await tester.pumpWidget(_app(state, storyboard: storyboard));
      final thumbnail = tester.widget<StoryboardThumbnail>(
        find.byType(StoryboardThumbnail),
      );
      expect(thumbnail.frame.column, 1);
      expect(thumbnail.frame.row, 0);
      expect(thumbnail.width, 100);
      final time = tester.getRect(
        find.byKey(const ValueKey('player-swipe-seek-time')),
      );
      final image = tester.getRect(find.byType(StoryboardThumbnail));
      expect(time.left, closeTo(image.left, .01));
      expect(time.right, closeTo(image.right, .01));
      expect(find.text('01:30 / 10:00'), findsOneWidget);
      expect(state.requests, 1);
      await drag.up();
      expect(state.seeks, [const Duration(seconds: 90)]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(90, 200), const Size(180, 70)]) {
    testWidgets('preview fits $size while preserving image proportions', (
      tester,
    ) async {
      final state = _State();
      final storyboard = VideoStoryboard(
        columns: 1,
        rows: 1,
        tileWidth: 160,
        tileHeight: 90,
        images: [Uri.parse('https://i0.hdslb.com/test.jpg')],
        times: const [Duration.zero],
      );
      await tester.pumpWidget(
        _app(
          state,
          width: size.width,
          height: size.height,
          storyboard: storyboard,
        ),
      );
      final drag = await tester.startGesture(Offset(20, size.height / 2));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      final image = tester.getRect(find.byType(StoryboardThumbnail));
      final time = tester.getRect(
        find.byKey(const ValueKey('player-swipe-seek-time')),
      );
      final preview = tester.getRect(
        find.byKey(const ValueKey('player-swipe-seek-preview')),
      );
      expect(image.width, lessThanOrEqualTo(100));
      expect(image.width / image.height, closeTo(16 / 9, .001));
      expect(time.left, closeTo(image.left, .01));
      expect(time.right, closeTo(image.right, .01));
      expect(preview.left, greaterThanOrEqualTo(0));
      expect(preview.right, lessThanOrEqualTo(size.width));
      expect(preview.top, greaterThanOrEqualTo(0));
      expect(preview.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await drag.up();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('small picture and enlarged text keep the time within bounds', (
    tester,
  ) async {
    final state = _State();
    await tester.pumpWidget(_app(state, width: 180, height: 70, textScale: 2));
    final drag = await tester.startGesture(const Offset(20, 30));
    await drag.moveBy(const Offset(50, 0));
    await tester.pump();
    final card = tester.getRect(
      find.byKey(const ValueKey('player-swipe-seek-preview')),
    );
    expect(const Rect.fromLTWH(0, 0, 180, 70).contains(card.topLeft), isTrue);
    expect(card.bottom, lessThanOrEqualTo(70));
    expect(
      find.byKey(const ValueKey('player-swipe-seek-time')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await drag.up();
  });
}

class _State {
  final preview = ValueNotifier<Duration?>(null);
  final seeks = <Duration>[];
  Duration position = const Duration(minutes: 1);
  int requests = 0;
  Completer<void>? nextSeek;
}

Widget _app(
  _State state, {
  bool enabled = true,
  int generation = 1,
  Duration duration = const Duration(minutes: 10),
  double width = 400,
  double height = 200,
  double textScale = 1,
  VideoStoryboard? storyboard,
  Widget? picture,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: PlayerSeekControls(
            enabled: enabled,
            sourceGeneration: generation,
            position: () => state.position,
            duration: duration,
            preview: state.preview,
            onSeek: (position) async {
              state.seeks.add(position);
              final gate = state.nextSeek;
              state.nextSeek = null;
              if (gate != null) await gate.future;
            },
            onPreviewRequest: () => state.requests++,
            storyboard: storyboard,
            child: picture ?? const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    ),
  ),
);
