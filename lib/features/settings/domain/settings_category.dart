enum SettingsCategory {
  appearance('外观'),
  cache('缓存'),
  shortcuts('快捷键'),
  playback('播放'),
  danmaku('弹幕'),
  subtitles('字幕'),
  sponsorBlock('空降助手'),
  about('关于');

  const SettingsCategory(this.label);
  final String label;

  static SettingsCategory fromName(String? name) =>
      values.where((category) => category.name == name).firstOrNull ??
      appearance;
}
