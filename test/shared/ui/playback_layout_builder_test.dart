import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/shared/ui/playback_layout_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/playback_layout_session_fake.dart';

void main() {
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
