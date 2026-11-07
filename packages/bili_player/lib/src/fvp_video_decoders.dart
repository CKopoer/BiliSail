import 'player_contract.dart';

/// Decoder device indices belong to their own API. DXGI indices must never be
/// passed to DXVA's D3D9 adapters or CUDA's independently enumerated devices.
List<String> fvpVideoDecoders({
  required String operatingSystem,
  required VideoDecodingMode decoding,
  int? windowsAdapterIndex,
}) {
  if (decoding == VideoDecodingMode.software) return ['FFmpeg', 'dav1d'];
  return switch (operatingSystem) {
    'windows' when windowsAdapterIndex != null && windowsAdapterIndex >= 0 => [
      'MFT:d3d=11:adapter=$windowsAdapterIndex',
      'D3D11:hwdevice=$windowsAdapterIndex',
      'FFmpeg',
      'dav1d',
    ],
    'windows' => ['MFT:d3d=11', 'D3D11', 'DXVA', 'FFmpeg', 'dav1d'],
    'android' => ['AMediaCodec', 'FFmpeg', 'dav1d'],
    'macos' || 'ios' => ['VT', 'FFmpeg', 'dav1d'],
    'linux' => ['VAAPI', 'CUDA', 'VDPAU', 'FFmpeg', 'dav1d'],
    _ => ['FFmpeg', 'dav1d'],
  };
}
