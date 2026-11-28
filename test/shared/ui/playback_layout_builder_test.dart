import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/shared/ui/playback_layout_builder.dart';
import 'package:bilisail/shared/ui/collapsed_playback_header.dart';
import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/playback_layout_session_fake.dart';

void main() {
  testWidgets('only stopped on-demand media offers a collapsed play action', (
    tester,
  ) async {
    final session = PlaybackLayoutSessionFake();
    addTearDown(session.dispose);
    CollapsedPlaybackAction? action;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: PlaybackLayoutSnapshot(
          allowCollapse: true,
          builder: (_, _, value) {
            action = value;
            return Consumer(
              builder: (_, ref, _) {
                ref.read(playbackSessionProvider);
                return const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
    Future<void> publish(
      PlaybackPhase phase, {
      bool playing = false,
      int generation = 1,
    }) async {
      session.snapshots.value = PlaybackSnapshot(
        phase: phase,
        desiredPlaying: playing,
        generation: generation,
      );
      await tester.pump();
    }

    expect(action, isNull);
    await publish(PlaybackPhase.paused);
    expect(action, CollapsedPlaybackAction.play);
    await publish(PlaybackPhase.buffering, playing: true);
    expect(action, isNull);
    await publish(PlaybackPhase.playing, playing: true);
    expect(action, isNull);
    await publish(PlaybackPhase.paused);
    expect(action, CollapsedPlaybackAction.resume);
    session.isResolving = true;
    session.publishMetadata();
    await tester.pump();
    expect(action, isNull);
    session.isResolving = false;
    session.error = '加载失败';
    session.publishMetadata();
    await tester.pump();
    expect(action, isNull);
    session.error = null;
    await publish(PlaybackPhase.ended);
    expect(action, CollapsedPlaybackAction.replay);
    await publish(PlaybackPhase.ready, generation: 2);
    expect(action, CollapsedPlaybackAction.play);
  });

  testWidgets('decoded dimensions are discovered lazily and ignore position', (
    tester,
  ) async {
    final session = PlaybackLayoutSessionFake();
    addTearDown(session.dispose);
    var builds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: MaterialApp(
          home: PlaybackLayoutSnapshot(
            builder: (context, dimensions, _) {
              builds++;
              return Consumer(
                builder: (context, ref, _) {
                  ref.read(playbackSessionProvider);
                  return Text('${dimensions?.width}×${dimensions?.height}');
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = builds;
    for (var i = 1; i <= 100; i++) {
      session.snapshots.value = session.snapshots.value.copyWith(
        position: Duration(milliseconds: i * 100),
      );
      await tester.pump();
    }
    expect(builds, initial);
    session.snapshots.value = session.snapshots.value.copyWith(
      videoDimensions: const VideoDimensions(1080, 1920),
    );
    await tester.pump();
    expect(builds, initial + 1);
    expect(find.text('1080×1920'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.hasSnapshotListeners, isFalse);
  });

  testWidgets('placeholder layout never creates a playback session', (
    tester,
  ) async {
    var creates = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackSessionProvider.overrideWith((ref) {
            creates++;
            throw StateError('A placeholder must not create an engine');
          }),
        ],
        child: MaterialApp(
          home: PlaybackLayoutBuilder(
            builder: (context, bounds, listening) => Text('$listening'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(creates, 0);
    expect(find.text('false'), findsOneWidget);
  });

  testWidgets(
    'discovers a child-created session and only rebuilds on mode changes',
    (tester) async {
      final session = PlaybackLayoutSessionFake();
      addTearDown(session.dispose);
      var builds = 0;
      var creates = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackSessionProvider.overrideWith((ref) {
              creates++;
              return session;
            }),
          ],
          child: MaterialApp(
            home: PlaybackLayoutBuilder(
              builder: (context, bounds, listening) {
                builds++;
                return Consumer(
                  builder: (context, ref, _) {
                    ref.read(playbackSessionProvider);
                    return Text('$listening');
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(creates, 1);
      final initial = builds;
      for (var i = 0; i < 100; i++) {
        session.publishMetadata();
        await tester.pump();
      }
      expect(builds, initial);
      await session.setAudioOnly(true);
      await tester.pumpAndSettle();
      expect(find.text('true'), findsOneWidget);
      expect(builds, initial + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(session.hasLayoutListeners, isFalse);
    },
  );

  test(
    'listening height uses half the available page with a compact minimum',
    () {
      expect(PlaybackLayoutBuilder.listeningHeight(800), 400);
      expect(PlaybackLayoutBuilder.listeningHeight(600), 300);
      expect(PlaybackLayoutBuilder.listeningHeight(300), 180);
      expect(PlaybackLayoutBuilder.listeningHeight(150), 150);
    },
  );
}
