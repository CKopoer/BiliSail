import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's activity PiP uses the existing Flutter surface and media session.
final class PictureInPictureService {
  static final instance = PictureInPictureService();
  static const _channel = MethodChannel('bilisail/picture_in_picture');
  final active = ValueNotifier(false);
  bool _initialized = false;

  Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed' && call.arguments is bool) {
          active.value = call.arguments as bool;
        }
      });
    }
    return await _channel
            .invokeMethod<bool>('isSupported')
            .timeout(const Duration(seconds: 2)) ??
        false;
  }

  Future<bool> enter(double aspectRatio) async {
    if (!await isSupported()) return false;
    // Set before onPause so lifecycle observers keep this video surface alive.
    active.value = true;
    try {
      final entered =
          await _channel
              .invokeMethod<bool>('enter', {
                'aspectRatio': aspectRatio.isFinite
                    ? aspectRatio.clamp(1 / 2.39, 2.39)
                    : 16 / 9,
              })
              .timeout(const Duration(seconds: 3)) ??
          false;
      if (!entered) active.value = false;
      return entered;
    } catch (_) {
      active.value = false;
      rethrow;
    }
  }
}
