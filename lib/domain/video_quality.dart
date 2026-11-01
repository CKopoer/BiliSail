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
