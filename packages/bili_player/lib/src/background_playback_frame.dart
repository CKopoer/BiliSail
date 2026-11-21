import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Runs pending playback work that depends on a frame while mobile vsync is
/// suspended. Call only for a source transition or a required initialization.
void requestBackgroundPlaybackFrame() {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  final binding = WidgetsBinding.instance;
  bool needsFrame() =>
      !binding.framesEnabled &&
      (binding.lifecycleState == AppLifecycleState.hidden ||
          binding.lifecycleState == AppLifecycleState.paused);
  if (!needsFrame()) return;
  // A provider update can arrive during build or a post-frame callback.
  // Schedule after the current frame so the binding can accept the request.
  scheduleMicrotask(() {
    if (needsFrame()) binding.scheduleWarmUpFrame();
  });
}
