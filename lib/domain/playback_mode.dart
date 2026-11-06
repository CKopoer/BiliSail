enum PlaybackMode {
  pause('播完暂停'),
  continuous('连续播放'),
  listLoop('列表循环'),
  singleLoop('单集循环');

  const PlaybackMode(this.label);
  final String label;
}
