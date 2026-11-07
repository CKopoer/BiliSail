import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/playback/application/playback_information_controller.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';
import '../../support/video_card_fake_engine.dart';

final class _Engine extends CardFakeEngine implements PlayerInformationSource {
  int samples = 0;
  Completer<PlayerPlaybackInformation?>? pending;
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async {
    samples++;
    if (pending case final gate?) return gate.future;
    return PlayerPlaybackInformation(
      generation: currentSnapshot.generation,
      backend: 'media_kit / libmpv',
      hardwareDecoder: 'd3d11va',
      frameDrops: samples,
      avSyncSeconds: -.025,
      cacheSpeed: 1048576,
      videoBitrate: 12000000,
    );
  }
}

final class _Repository extends Fake implements PlaybackRepository {}

final class _Progress extends Fake implements PlaybackProgressStore {}

PlaybackSession _session(_Engine engine) {
  final session = PlaybackSession(
    engine: engine,
    repository: _Repository(),
    progress: _Progress(),
    accountScope: () => 'guest',
  );
  session.media = cardPreviewMedia();
  engine.publish(
    const PlaybackSnapshot(
      phase: PlaybackPhase.playing,
      generation: 1,
      position: Duration(seconds: 10),
      duration: Duration(seconds: 120),
      buffered: Duration(seconds: 30),
      rate: 1.5,
      volume: 80,
    ),
  );
  return session;
}

Future<void> _show(
  WidgetTester tester, {
  PlaybackSession? session,
  int tab = 4,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          MemorySettingsRepository(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPlayerSettings(context, tab: tab, session: session),
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开设置'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'information tab samples only while selected and stops on close',
    (tester) async {
      final engine = _Engine();
      final session = _session(engine);
      addTearDown(session.close);
      await _show(tester, session: session, tab: 0);
      expect(engine.samples, 0);
      await tester.ensureVisible(find.text('实时播放信息'));
      await tester.tap(find.text('实时播放信息'));
      await tester.pumpAndSettle();
      expect(find.text('media_kit / libmpv'), findsOneWidget);
      expect(find.text('00:00:10'), findsOneWidget);
      expect(find.text('1.50×'), findsOneWidget);
      final first = engine.samples;
      await tester.pump(const Duration(seconds: 1));
      expect(engine.samples, greaterThan(first));
      await tester.ensureVisible(find.text('播放').first);
      await tester.tap(find.text('播放').first);
      await tester.pumpAndSettle();
      final stopped = engine.samples;
      await tester.pump(const Duration(seconds: 3));
      expect(engine.samples, stopped);
      await tester.ensureVisible(find.text('实时播放信息'));
      await tester.tap(find.text('实时播放信息'));
      await tester.pumpAndSettle();
      expect(engine.samples, greaterThan(stopped));
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      final closed = engine.samples;
      await tester.pump(const Duration(seconds: 3));
      expect(engine.samples, closed);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'narrow information tab shows native values and scrolls without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final engine = _Engine();
      final session = _session(engine);
      addTearDown(session.close);
      await _show(tester, session: session);
      final list = find.byKey(
        const PageStorageKey('player-information-scroll'),
      );
      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.text('视频码率（实时）'),
        240,
        scrollable: scrollable,
      );
      expect(find.text('12.00 Mbps'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('音画差（A−V）'),
        240,
        scrollable: scrollable,
      );
      expect(find.text('-25.00 ms'), findsOneWidget);
      expect(find.text('1.00 MiB/s'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('information tab works without a playback session', (
    tester,
  ) async {
    await _show(tester);
    expect(find.text('当前没有播放会话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'information sampling pauses in background and resumes in foreground',
    (tester) async {
      final engine = _Engine();
      final session = _session(engine);
      addTearDown(session.close);
      await _show(tester, session: session);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = engine.samples;
      await tester.pump(const Duration(seconds: 3));
      expect(engine.samples, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(engine.samples, greaterThan(paused));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('stale native sample is discarded and reads never overlap', (
    tester,
  ) async {
    final engine = _Engine()..pending = Completer<PlayerPlaybackInformation?>();
    final session = _session(engine);
    final controller = PlaybackInformationController(session);
    addTearDown(session.close);
    addTearDown(controller.dispose);
    controller.start();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(engine.samples, 1);
    engine.publish(engine.currentSnapshot.copyWith(generation: 2));
    engine.pending!.complete(
      const PlayerPlaybackInformation(generation: 1, backend: 'obsolete'),
    );
    engine.pending = null;
    await tester.pump();
    expect(controller.value?.native, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(engine.samples, 2);
    expect(controller.value?.native?.generation, 2);
    expect(controller.value?.native?.backend, 'media_kit / libmpv');
    controller.stop();
  });

  testWidgets('closing a pending sampler ignores its completion', (
    tester,
  ) async {
    final engine = _Engine()..pending = Completer<PlayerPlaybackInformation?>();
    final session = _session(engine);
    final controller = PlaybackInformationController(session);
    addTearDown(session.close);
    controller.start();
    controller.dispose();
    engine.pending!.complete(
      const PlayerPlaybackInformation(generation: 1, backend: 'obsolete'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(engine.samples, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no loaded source does not sample a previous native player', (
    tester,
  ) async {
    final engine = _Engine();
    final session = _session(engine)..media = null;
    final controller = PlaybackInformationController(session);
    addTearDown(session.close);
    controller.start();
    await tester.pump();
    expect(engine.samples, 0);
    expect(controller.value?.hasSource, false);
    expect(controller.value?.native, isNull);
    controller.dispose();
  });
}
