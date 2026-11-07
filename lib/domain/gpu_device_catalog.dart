/// A hardware adapter identity, resolved to its current DXGI index on each open.
final class GpuDevice {
  const GpuDevice({required this.id, required this.name, required this.index});

  final String id;
  final String name;
  final int index;
}

abstract interface class GpuDeviceCatalog {
  bool get supported;
  Future<List<GpuDevice>> loadDevices();
}

final class UnavailableGpuDeviceCatalog implements GpuDeviceCatalog {
  const UnavailableGpuDeviceCatalog();

  @override
  bool get supported => false;
  @override
  Future<List<GpuDevice>> loadDevices() async => const [];
}
