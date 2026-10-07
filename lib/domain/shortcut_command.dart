/// Key names are stable storage values; Flutter key IDs never enter domain data.
enum ShortcutAction {
  playPause('播放 / 暂停', ['Space']),
  fullscreen('切换全屏', ['F', 'F11', 'Enter']),
  exitFullscreen('退出全屏', ['Escape']),
  fullWindow('收起 / 展开视频信息', ['W', 'F12']),
  seekBack('后退', ['ArrowLeft']),
  seekForward('前进（长按临时倍速）', ['ArrowRight']),
  seekLarge('前进 90 秒', ['O', 'P']),
  volumeUp('提高音量', ['ArrowUp']),
  volumeDown('降低音量', ['ArrowDown']),
  mute('静音 / 恢复音量', []),
  danmaku('显示 / 隐藏弹幕', ['D', 'F9']),
  subtitles('开启 / 关闭字幕', ['F6']),
  slower('降低播放速度', ['F1', 'Semicolon']),
  faster('提高播放速度', ['F2', 'Quote']),
  toggleRate('切换 1 / 2 倍速', ['Ctrl+1']),
  previousPart('上一分 P', ['Z', 'N', 'Comma']),
  nextPart('下一分 P', ['X', 'M', 'Period']),
  newTab('新建浏览标签', ['Ctrl+T']),
  closeTab('关闭当前标签页', ['Ctrl+W']),
  refresh('刷新当前页面', ['Ctrl+R', 'F5']);

  const ShortcutAction(this.label, this.defaultKeys);
  final String label;
  final List<String> defaultKeys;
}

enum ReservedShortcut {
  nextTab,
  previousTab,
  imageClose,
  imagePrevious,
  imageNext,
  imageZoomIn,
  imageZoomOut,
}
