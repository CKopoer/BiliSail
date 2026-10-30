import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/app_icon.dart';

final class NativeAppIconService implements AppIconService {
  const NativeAppIconService();
  static const channel = MethodChannel('bilisail/app_icon');

  @override
  AppIconSurface get surface => kIsWeb
      ? AppIconSurface.unsupported
      : switch (defaultTargetPlatform) {
          TargetPlatform.android ||
          TargetPlatform.iOS => AppIconSurface.launcher,
          TargetPlatform.windows ||
          TargetPlatform.linux => AppIconSurface.window,
          TargetPlatform.macOS => AppIconSurface.dock,
          TargetPlatform.fuchsia => AppIconSurface.unsupported,
        };

  @override
  Future<AppIconPreference> restore(AppIconPreference saved) async {
    if (surface == AppIconSurface.unsupported) return saved;
    if (surface == AppIconSurface.launcher) {
      // The OS retains mobile icons. Reading avoids an iOS change alert on launch
      // and recovers a change interrupted before its SQLite commit.
      final name = await channel
          .invokeMethod<String>('getIcon')
          .timeout(const Duration(seconds: 5));
      return AppIconPreference.values.firstWhere(
        (icon) => icon.name == name,
        orElse: () => throw const FormatException('Invalid application icon'),
      );
    }
    await apply(saved);
    return saved;
  }

  @override
  Future<void> apply(AppIconPreference icon) async {
    if (surface == AppIconSurface.unsupported) {
      throw UnsupportedError('Application icons are unavailable');
    }
    await channel
        .invokeMethod<void>('setIcon', {
          'icon': icon.name,
          if (surface == AppIconSurface.dock ||
              defaultTargetPlatform == TargetPlatform.linux)
            'image': (await rootBundle.load(icon.asset)).buffer.asUint8List(),
        })
        .timeout(const Duration(seconds: 15));
  }
}
