import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_request_device.dart';

/// Resolve the default qn once per new room. Explicit quality skips this read.
Future<int> defaultNetworkLiveQuality({bool fakeWifi = false}) async {
  if (fakeWifi) return 10000;
  const channel = MethodChannel('dev.bilisail/live_network');
  try {
    final preferOriginal = switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS => false,
      TargetPlatform.android => await const AppRequestDevice().usesWifi(),
      TargetPlatform.iOS || TargetPlatform.linux =>
        await channel
            .invokeMethod<bool>('preferOriginal')
            .timeout(const Duration(seconds: 1)),
      _ => true,
    };
    return preferOriginal == false ? 250 : 10000;
  } on PlatformException {
    return 10000;
  } on MissingPluginException {
    return 10000;
  } on TimeoutException {
    return 10000;
  }
}
