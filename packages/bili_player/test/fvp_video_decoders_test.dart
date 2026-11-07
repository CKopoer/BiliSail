import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_video_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a DXGI selection reaches both Windows decoders without D3D9 fallback',
    () {
      expect(
        fvpVideoDecoders(
          operatingSystem: 'windows',
          decoding: VideoDecodingMode.automatic,
          windowsAdapterIndex: 2,
        ),
        ['MFT:d3d=11:adapter=2', 'D3D11:hwdevice=2', 'FFmpeg', 'dav1d'],
      );
    },
  );

  test(
    'automatic device retains the original Windows decoder fallback order',
    () {
      expect(
        fvpVideoDecoders(
          operatingSystem: 'windows',
          decoding: VideoDecodingMode.automatic,
        ),
        ['MFT:d3d=11', 'D3D11', 'DXVA', 'FFmpeg', 'dav1d'],
      );
    },
  );

  test(
    'software and other platforms never receive a Windows adapter index',
    () {
      for (final os in ['windows', 'android', 'macos', 'ios', 'linux']) {
        expect(
          fvpVideoDecoders(
            operatingSystem: os,
            decoding: VideoDecodingMode.software,
            windowsAdapterIndex: 1,
          ),
          ['FFmpeg', 'dav1d'],
        );
        if (os != 'windows') {
          expect(
            fvpVideoDecoders(
              operatingSystem: os,
              decoding: VideoDecodingMode.automatic,
              windowsAdapterIndex: 1,
            ),
            fvpVideoDecoders(
              operatingSystem: os,
              decoding: VideoDecodingMode.automatic,
            ),
          );
        }
      }
    },
  );
}
