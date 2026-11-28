/// Android PCM output selection. mpv tries the Auto list in order.
enum AndroidAudioDriver {
  auto('Auto', 'opensles,aaudio,audiotrack'),
  opensles('OpenSL ES', 'opensles'),
  aaudio('AAudio', 'aaudio'),
  audiotrack('AudioTrack', 'audiotrack');

  const AndroidAudioDriver(this.label, this.mpvValue);
  final String label;
  final String mpvValue;

  bool get mayUseOpenSl => this == auto || this == opensles;
}

enum OpenSlPerformanceMode {
  latency('LATENCY'),
  none('NONE'),
  latencyEffects('LATENCY_EFFECTS'),
  powerSaving('POWER_SAVING');

  const OpenSlPerformanceMode(this.label);
  final String label;
}

typedef AndroidAudioOutput = ({
  AndroidAudioDriver driver,
  OpenSlPerformanceMode mode,
});

const defaultAndroidAudioOutput = (
  driver: AndroidAudioDriver.auto,
  mode: OpenSlPerformanceMode.latency,
);
