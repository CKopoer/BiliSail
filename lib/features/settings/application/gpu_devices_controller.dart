import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/gpu_device_catalog.dart';

final gpuDeviceCatalogProvider = Provider<GpuDeviceCatalog>(
  (ref) => const UnavailableGpuDeviceCatalog(),
);

final gpuDevicesProvider = FutureProvider.autoDispose<List<GpuDevice>>(
  (ref) => ref.watch(gpuDeviceCatalogProvider).loadDevices(),
);

/// Missing adapters use the backend default without discarding the preference.
/// Discovery failure must remain visible to the caller, rather than selecting
/// an adapter with a stale enumeration index.
Future<int?> resolveFvpGpuDevice(GpuDeviceCatalog catalog, String id) async {
  if (!catalog.supported || id.isEmpty) return null;
  final devices = await catalog.loadDevices();
  return devices.where((device) => device.id == id).firstOrNull?.index;
}
