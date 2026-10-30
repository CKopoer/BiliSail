import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:bilisail/core/platform/audio_service_media_controls.dart';
import 'package:bilisail/core/platform/system_media_controls.dart';
import 'package:bilisail/core/platform/windows_media_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SystemMediaState state({bool live = false, bool playing = true}) =>
    SystemMediaState(
      id: 'fixture:1',
      title: 'title',
      artist: 'author',
      phase: SystemMediaPhase.ready,
      playing: playing,
      position: const Duration(seconds: 4),
      duration: const Duration(seconds: 20),
      buffered: const Duration(seconds: 10),
      rate: 1.5,
      isLive: live,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'audio handler exposes play/pause, stop and VOD seek and clears to idle',
    () async {
      final controls = AudioServiceMediaControls();
      addTearDown(controls.close);
      final commands = <SystemMediaCommand>[];
      controls.onCommand = (command) async => commands.add(command);
      controls.publish(state());
      expect(controls.handler.mediaItem.value?.title, 'title');
      expect(
        controls.handler.playbackState.value.controls.map((e) => e.action),
        [MediaAction.pause, MediaAction.stop],
      );
      expect(
        controls.handler.playbackState.value.systemActions,
        contains(MediaAction.seek),
      );
      expect(controls.handler.playbackState.value.speed, 1.5);
      await controls.handler.pause();
      await controls.handler.play();
      await controls.handler.seek(const Duration(seconds: 8));
      await controls.handler.stop();
      expect(commands.map((c) => c.action), [
        SystemMediaAction.pause,
        SystemMediaAction.play,
        SystemMediaAction.seek,
        SystemMediaAction.stop,
      ]);
      expect(commands[2].position, const Duration(seconds: 8));
      controls.publish(null);
      expect(controls.handler.mediaItem.value, isNull);
      expect(
        controls.handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      await controls.handler.play();
      expect(commands.length, 4);
    },
  );

  test(
    'live disables seek, task removal stops the owner, close rejects actions',
    () async {
      final controls = AudioServiceMediaControls();
      final commands = <SystemMediaCommand>[];
      controls.onCommand = (command) async => commands.add(command);
      controls.publish(state(live: true, playing: false));
      expect(controls.handler.mediaItem.value?.isLive, isTrue);
      expect(controls.handler.mediaItem.value?.duration, isNull);
      expect(controls.handler.playbackState.value.systemActions, isEmpty);
      expect(
        controls.handler.playbackState.value.updatePosition,
        Duration.zero,
      );
      await controls.handler.seek(const Duration(seconds: 8));
      expect(commands, isEmpty);
      await controls.handler.onTaskRemoved();
      expect(commands.single.action, SystemMediaAction.stopAll);
      await controls.close();
      await controls.handler.play();
      expect(commands.length, 1);
    },
  );

  test('Windows serializes native updates and clear; callback carries source identity', () async {
    const channel = MethodChannel('bilisail/test_system_media');
    final calls = <MethodCall>[];
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'update') await gate.future;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final controls = WindowsMediaControls(channel: channel);
    final commands = <SystemMediaCommand>[];
    controls.onCommand = (command) async => commands.add(command);
    controls.publish(state());
    await Future<void>.delayed(Duration.zero);
    Future<void> send(String id) async {
      final done = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('command', {'id': id, 'action': 'pause'}),
            ),
            (_) => done.complete(),
          );
      await done.future;
    }

    await send('old-source');
    expect(commands, isEmpty);
    await send('fixture:1');
    expect(commands.single.action, SystemMediaAction.pause);
    final closing = controls.close();
    expect(calls.length, 1);
    gate.complete();
    await closing;
    expect(calls.map((c) => c.method), ['update', 'clear']);
    expect(controls.onCommand, isNull);
  });
}
