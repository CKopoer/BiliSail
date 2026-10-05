/// Source preferences; decoder availability still depends on the device.
enum VideoCodecPreference {
  h264,
  hevc,
  av1;

  static VideoCodecPreference? fromCodec(String codec) {
    final value = codec.toLowerCase();
    if (value.startsWith('avc1') ||
        value.startsWith('avc3') ||
        value == 'h264' ||
        value == 'avc') {
      return h264;
    }
    if (value.startsWith('hev1') ||
        value.startsWith('hvc1') ||
        value == 'hevc' ||
        value == 'h265') {
      return hevc;
    }
    if (value.startsWith('av01') || value == 'av1') return av1;
    return null;
  }
}

enum VideoDecodingPreference { automatic, software }
