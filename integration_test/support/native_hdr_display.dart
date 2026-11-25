import 'package:bili_player/bili_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _hdrChannel = MethodChannel('bilisail/hdr_video');

/// Keep the existing pixel comparison deterministic even on HDR desktops.
void simulateSdrDisplay(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _hdrChannel,
    (_) async => null,
  );
}

Future<void> checkNativeHdrDisplay(
  WidgetTester tester,
  MediaKitEngine engine,
  ResolvedMediaSource source,
  Future<void> Function(WidgetTester, Future<void>) withFrames,
) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _hdrChannel,
    null,
  );
  final String? transfer;
  try {
    transfer = await _hdrChannel.invokeMethod<String>('supported', {
      'view': tester.view.viewId,
    });
  } on MissingPluginException {
    return;
  }
  if (transfer == null) return;
  await withFrames(
    tester,
    engine.open(source, const OpenOptions(play: false, volume: 0)),
  );
  final config = await engine.inspectNativeOutputConfiguration();
  expect(config['nativeHdrSurface'], isTrue);
  expect(config['videoOutput'], 'gpu-next');
  expect(config['videoOutputMatrix'], 'dolbyvision');
  expect(config['targetTransfer'], transfer);
  await withFrames(tester, engine.seek(const Duration(seconds: 1)));
  expect(engine.currentSnapshot.desiredPlaying, isFalse);
}
