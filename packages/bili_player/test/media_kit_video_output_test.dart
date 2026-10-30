import 'package:bili_player/src/media_kit_video_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

final class _Player extends mk.PlatformPlayer {
  _Player() : super(configuration: const mk.PlayerConfiguration());

  bool get hasWidthListener => widthController.hasListener;
  bool get hasHeightListener => heightController.hasListener;
  int pauses = 0, plays = 0;

  @override
  Future<void> pause() async {
    pauses++;
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> play() async {
    plays++;
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  void publishDimensions(int width, int height) {
    state = state.copyWith(width: width, height: height);
    widthController.add(width);
    heightController.add(height);
  }
}

final class _PlatformOutput extends mkv.PlatformVideoController {
  _PlatformOutput(mk.Player player, int textureId)
    : super(player, const mkv.VideoControllerConfiguration()) {
    id.value = textureId;
    rect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
  }

  @override
  Future<void> setSize({int? width, int? height}) async {}
}

final class _PlayerFacade extends Fake implements mk.Player {
  _PlayerFacade(this.platform);

  @override
  final mk.PlatformPlayer platform;

  @override
  mk.PlayerState get state => platform.state;

  @override
  mk.PlayerStream get stream => platform.stream;

  @override
  Future<void> pause() => platform.pause();

  @override
  Future<void> play() => platform.play();
}

final class _Controller extends Fake implements mkv.VideoController {
  _Controller(_Player backend, int textureId)
    : player = _PlayerFacade(backend) {
    output = _PlatformOutput(player, textureId);
    notifier = ValueNotifier(output);
  }

  @override
  final mk.Player player;
  late final _PlatformOutput output;
  @override
  late final ValueNotifier<mkv.PlatformVideoController?> notifier;

  void dispose() {
    notifier.dispose();
    output.dispose();
  }
}

final class _Harness {
  final output = MediaKitVideoOutput();
  late final surface = output.buildVideoSurface();

  // Inject native-free controllers through the production surface's binding.
  // All widget creation and visibility behavior still run the real output code.
  late final controllers =
      (surface as ValueListenableBuilder<mkv.VideoController?>).valueListenable
          as ValueNotifier<mkv.VideoController?>;

  Widget build() => MaterialApp(home: output.buildVideoSurface());
}

void main() {
  for (final playing in [true, false]) {
    testWidgets('surface leaves background playback and foreground intent to '
        'its session (playing=$playing)', (tester) async {
      final player = _Player();
      final controller = _Controller(player, 44);
      final harness = _Harness();
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        harness.output.dispose();
        controller.dispose();
        await player.dispose();
      });
      harness.controllers.value = controller;
      await tester.pumpWidget(harness.build());
      player.state = player.state.copyWith(playing: playing);
      // No pump between hidden/paused: Android can suspend Flutter frames while
      // the outgoing video surface is still observing the old native player.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(player.pauses, 0);
      expect(player.state.playing, playing);

      // A pause requested by the session while backgrounded must stay paused.
      await player.pause();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(player.state.playing, isFalse);
      expect(player.plays, 0);
    });
  }

  for (final dimensionsReadyBeforeSwap in [true, false]) {
    testWidgets('replacement displays its texture when dimensions are ready '
        '${dimensionsReadyBeforeSwap ? 'before' : 'after'} the swap', (
      tester,
    ) async {
      final oldPlayer = _Player();
      final newPlayer = _Player();
      final oldController = _Controller(oldPlayer, 11);
      final newController = _Controller(newPlayer, 22);
      final harness = _Harness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        harness.output.dispose();
        oldController.dispose();
        newController.dispose();
        await oldPlayer.dispose();
        await newPlayer.dispose();
      });

      harness.controllers.value = oldController;
      await tester.pumpWidget(harness.build());
      expect(find.byType(Texture), findsNothing);

      if (dimensionsReadyBeforeSwap) {
        newPlayer.publishDimensions(1920, 1080);
      }
      // A failed open can clear and replace the controller between frames.
      // Flutter may never build the intervening null value.
      harness.output.clearPlayer();
      harness.controllers.value = newController;
      await tester.pump();

      if (!dimensionsReadyBeforeSwap) {
        expect(find.byType(Texture), findsNothing);
        newPlayer.publishDimensions(1920, 1080);
        // Deliver the asynchronous size events, then paint their setState.
        await tester.pump();
        await tester.pump();
      }
      expect(find.byType(Texture), findsOneWidget);
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 22);
      expect(oldPlayer.hasWidthListener, isFalse);
      expect(oldPlayer.hasHeightListener, isFalse);
      expect(newPlayer.hasWidthListener, isTrue);
      expect(newPlayer.hasHeightListener, isTrue);

      // Late events from the old decoder must not hide the new video.
      oldPlayer.publishDimensions(0, 0);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 22);
    });
  }

  testWidgets('rebuilding the same controller preserves video state', (
    tester,
  ) async {
    final player = _Player()..publishDimensions(1920, 1080);
    final controller = _Controller(player, 33);
    final harness = _Harness();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      harness.output.dispose();
      controller.dispose();
      await player.dispose();
    });
    harness.controllers.value = controller;
    await tester.pumpWidget(harness.build());
    final state = tester.state(find.byType(mkv.Video));

    await tester.pumpWidget(harness.build());
    expect(identical(tester.state(find.byType(mkv.Video)), state), isTrue);
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 33);
  });
}
