import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/gpu_device_catalog.dart';

final class NativeGpuDeviceCatalog implements GpuDeviceCatalog {
  const NativeGpuDeviceCatalog();

  static const channel = MethodChannel('bilisail/gpu_devices');

  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<List<GpuDevice>> loadDevices() async {
    if (!supported) return const [];
    final result = await channel
        .invokeMethod<Object?>('listDevices')
        .timeout(const Duration(seconds: 5));
    if (result is! List) throw const FormatException('Invalid GPU catalog');
    final devices = <GpuDevice>[];
    final ids = <String>{};
    for (final entry in result) {
      if (entry
          case {
            'id': final String id,
            'name': final String name,
            'index': final int index,
          }
          when id.isNotEmpty && name.isNotEmpty && index >= 0 && ids.add(id)) {
        devices.add(GpuDevice(id: id, name: name, index: index));
      } else {
        throw const FormatException('Invalid GPU device');
      }
    }
    return List.unmodifiable(devices);
  }
}
