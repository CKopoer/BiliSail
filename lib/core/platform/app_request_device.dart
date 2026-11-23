import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads public Android OS facts without hardware IDs or new plugin dependencies.
final class AppRequestDevice {
  const AppRequestDevice();
  static const _channel = MethodChannel('dev.bilisail/app_request_device');

  Future<Map<String, Object?>?> _read({
    Duration timeout = const Duration(seconds: 2),
  }) => _channel.invokeMapMethod<String, Object?>('read').timeout(timeout);

  Future<bool?> usesWifi() async {
    final facts = await _read(timeout: const Duration(seconds: 1));
    return facts == null ? null : facts['network'] == 'wifi';
  }

  /// Loads the App request profile. [fakeWifi] changes only its declared
  /// network type; it neither changes nor hides the real OS network state.
  Future<AppDeviceInfo> load({bool fakeWifi = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AppDeviceInfo();
    }
    AppDeviceInfo unavailable() => AppDeviceInfo(
      model: 'android',
      osVersion: '',
      network: fakeWifi ? 'wifi' : '',
    );
    try {
      final data = await _read();
      String value(String key, String fallback) {
        final text = data?[key];
        return text is String &&
                text.isNotEmpty &&
                text.length <= 100 &&
                !RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)
            ? text
            : fallback;
      }

      final network = value('network', '');
      return AppDeviceInfo(
        model: value('model', 'android'),
        osVersion: value('osVersion', ''),
        network: fakeWifi
            ? 'wifi'
            : const {'wifi', 'mobile'}.contains(network)
            ? network
            : '',
      );
    } on MissingPluginException {
      return unavailable();
    } on TimeoutException {
      return unavailable();
    } on PlatformException {
      return unavailable();
    }
  }
}
