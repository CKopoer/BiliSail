import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/gpu_device_catalog.dart';
import 'package:bilisail/features/settings/application/gpu_devices_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Windows catalog and each fvp DXGI adapter open DASH with audio', (
    tester,
  ) async {
    initializePlayerBackend();
    const catalog = NativeGpuDeviceCatalog();
    expect(catalog.supported, true);
    final devices = await catalog.loadDevices();
    expect(devices, isNotEmpty);
    expect(devices.map((device) => device.id).toSet().length, devices.length);
    final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(fixtures, isNotNull);
    MediaTrack track(String name) => MediaTrack(
      uri: File('$fixtures/$name').uri,
      requestPolicy: MediaRequestPolicy(),
    );
    final source = DashPairSource(
      video: track('video.mp4'),
      audio: track('audio.m4a'),
    );
    for (final device in devices) {
      final index = await resolveFvpGpuDevice(catalog, device.id);
      expect(index, device.index);
      final engine = FvpEngine(windowsAdapterIndex: index);
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        await engine.open(source, const OpenOptions(play: true, volume: 0));
        await Future<void>.delayed(const Duration(seconds: 1));
        final information = await engine.inspectPlaybackInformation();
        expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
        expect(information?.videoCodec, 'h264');
        expect(information?.audioCodec, 'aac');
        expect(information?.diagnostics?.hasVideoOutput, true);
        expect(information?.diagnostics?.hasDecodedAudio, true);
        // Record the observed decoder, without treating a configured preference
        // as proof of the physical GPU or excluding a valid software fallback.
        debugPrint(
          'GPU selection: ${device.name}, DXGI=$index, decoder=${information?.hardwareDecoder}',
        );
        await engine.pause();
        await engine.seek(const Duration(seconds: 2));
        expect(engine.currentSnapshot.desiredPlaying, false);
      } finally {
        await engine.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    // Retained hardware selection must not re-enable a hardware decoder in
    // software mode, including a subsequent source replacement.
    final software = FvpEngine(windowsAdapterIndex: devices.first.index);
    try {
      await tester.pumpWidget(
        MaterialApp(home: VideoSurface(engine: software)),
      );
      await software.open(
        source,
        const OpenOptions(videoDecoding: VideoDecodingMode.software, volume: 0),
      );
      final information = await software.inspectPlaybackInformation();
      expect(information?.hardwareDecoder, 'no');
      expect(information?.diagnostics?.hasDecodedAudio, true);
    } finally {
      await software.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
