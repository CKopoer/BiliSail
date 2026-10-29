enum AudioQualityPreference {
  aac64('AAC · 64K'),
  aac132('AAC · 132K'),
  aac192('AAC · 192K（默认）'),
  lossless('Hi-Res / FLAC 无损'),
  dolby('杜比音频');

  const AudioQualityPreference(this.label);
  final String label;

  static AudioQualityPreference? identify(int id, String codec) {
    final name = codec.toLowerCase();
    if (name == 'flac' || name.startsWith('flac.') || id == 30251) {
      return lossless;
    }
    if (const ['ec-3', 'ec+3', 'eac3', 'ac-3', 'ac3'].contains(name) ||
        id == 30250 ||
        id == 30255) {
      return dolby;
    }
    if (!name.startsWith('mp4a')) return null;
    return switch (id) {
      30216 => aac64,
      30232 => aac132,
      _ => aac192,
    };
  }

  /// Prefer the requested format, then ordinary AAC before other formats.
  List<AudioQualityPreference> get fallbackOrder => switch (this) {
    aac64 => [aac64, aac132, aac192, lossless, dolby],
    aac132 => [aac132, aac64, aac192, lossless, dolby],
    aac192 => [aac192, aac132, aac64, lossless, dolby],
    lossless => [lossless, aac192, aac132, aac64, dolby],
    dolby => [dolby, aac192, aac132, aac64, lossless],
  };
}
