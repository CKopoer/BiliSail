import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/playback/application/playback_information_controller.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';
import '../../support/video_card_fake_engine.dart';

final class _Engine extends CardFakeEngine implements PlayerInformationSource {
  int samples = 0;
  Completer<PlayerPlaybackInformation?>? pending;
  PlayerPlaybackInformation? information;
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async {
    samples++;
    if (pending case final gate?) return gate.future;
    if (information case final info?) {
      return info.withGeneration(currentSnapshot.generation);
    }
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
        builder: AppNoticeHost.builder,
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
    'copies native fields, nominal bitrate fallback and unavailable metrics',
    (tester) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (call.arguments case {'text': final String text}) copied = text;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final engine = _Engine()
        ..information = const PlayerPlaybackInformation(
          generation: 1,
          backend: 'media_kit / mpv',
          videoCodec: 'h264',
          audioCodec: 'aac',
          hardwareDecoder: 'd3d11va',
          sourceFps: 24,
          videoNominalBitrate: 2000000,
          audioNominalBitrate: 128000,
          cacheSeconds: 2.5,
          diagnostics: PlayerDiagnostics(
            generation: 1,
            position: Duration.zero,
            hasDecodedVideo: true,
            hasDecodedAudio: true,
            hasVideoOutput: true,
            videoWidth: 320,
            videoHeight: 180,
            outputWidth: 320,
            outputHeight: 180,
            audioSampleRate: 48000,
            audioChannels: 2,
          ),
        );
      final session = _session(engine);
      session.media = PlaybackMedia(
        video: PlaybackTrack(
          urls: [Uri.parse('https://example.com/video')],
          codec: '',
          bandwidth: 0,
        ),
        audio: PlaybackTrack(
          urls: [Uri.parse('https://example.com/audio')],
          codec: '',
          bandwidth: 0,
        ),
        quality: 16,
        qualities: const [16],
        duration: const Duration(seconds: 20),
        headers: const {},
      );
      addTearDown(session.close);
      await _show(tester, session: session);
      await tester.tap(find.text('复制全部信息'));
      await tester.pump();
      expect(copied, contains('播放后端：media_kit / mpv'));
      expect(copied, contains('源帧率：24.00 fps'));
      expect(copied, contains('解码尺寸：320 × 180'));
      expect(copied, contains('采样率：48000 Hz'));
      expect(copied, contains('声道数：2'));
      expect(copied, contains('视频码率（标称）：2.00 Mbps'));
      expect(copied, contains('音频码率（标称）：128.00 kbps'));
      expect(copied, contains('原生缓存时长：2.50 s'));
      expect(copied, contains('音画差（A−V）：—'));
      expect(copied, contains('输出丢帧（累计）：—'));
      expect(copied, contains('帧率为播放器估算值'));
    },
  );
  testWidgets(
    'copy includes all fields, offscreen sections and the displayed sample',
    (tester) async {
      final copies = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (call.arguments case {'text': final String text}) copies.add(text);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final engine = _Engine();
      final session = _session(engine);
      addTearDown(session.close);
      await _show(tester, session: session);
      final samples = engine.samples;
      await tester.tap(find.text('复制全部信息'));
      await tester.pump();
      expect(engine.samples, samples);
      expect(copies, hasLength(1));
      final first = copies.single;
      expect(first, startsWith('实时播放信息\n'));
      expect(first, contains('播放状态\n播放后端：media_kit / libmpv'));
      expect(first, contains('播放位置：00:00:10'));
      expect(first, contains('视频与输出\n视频编码：avc1'));
      expect(first, contains('实际硬解：d3d11va'));
      expect(first, contains('视频码率（实时）：12.00 Mbps'));
      expect(first, contains('音频\n音频编码：mp4a'));
      expect(first, contains('缓存与同步\n缓冲至：00:00:30'));
      expect(first, contains('音画差（A−V）：-25.00 ms'));
      expect(first, contains('解码丢帧（累计）：—'));
      expect(
        first.split('\n').where((line) => line.contains('：')),
        hasLength(46),
      );
      expect(first, endsWith('丢帧计数随媒体源重建而重置。'));
      expect(find.text('播放信息已复制'), findsOneWidget);

      engine.advance(const Duration(seconds: 42));
      await tester.pump(const Duration(seconds: 1));
      final list = find.byKey(
        const PageStorageKey('player-information-scroll'),
      );
      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.text('解码丢帧（累计）'),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.text('复制全部信息'));
      await tester.pump();
      expect(copies, hasLength(2));
      expect(copies.last, contains('播放位置：00:00:42'));
      expect(copies.last, contains('输出丢帧（累计）：${engine.samples}'));
      expect(first, contains('播放位置：00:00:10'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('clipboard failure reports failure without claiming success', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'clipboard_unavailable');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final engine = _Engine();
    final session = _session(engine);
    addTearDown(session.close);
    await _show(tester, session: session);
    await tester.tap(find.text('复制全部信息'));
    await tester.pump();
    expect(find.text('复制失败，请重试'), findsOneWidget);
    expect(find.text('播放信息已复制'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
