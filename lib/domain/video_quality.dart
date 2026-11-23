const videoQualityOptions = <int, String>{
  16: '360P',
  32: '480P',
  64: '720P',
  74: '720P60',
  80: '1080P',
  112: '1080P+',
  116: '1080P60',
  120: '4K',
  125: 'HDR',
  126: '杜比视界',
  127: '8K',
};

String videoQualityLabel(int quality) =>
    videoQualityOptions[quality] ?? '$quality';

/// Quality tiers whose stream is HDR or Dolby Vision rather than SDR.
///
/// The player has to tone-map these frames; on devices without reliable HDR
/// output they look washed out and cost extra power. Selection skips them when
/// the user turns on the SDR preference, falling back to the highest SDR tier
/// the server actually returned.
const hdrVideoQualities = <int>{125, 126, 129};
