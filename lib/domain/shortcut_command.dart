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
  volumeUpTen('提高音量 10%', [], addedKeys: ['Shift+ArrowUp']),
  volumeDownTen('降低音量 10%', [], addedKeys: ['Shift+ArrowDown']),
  mute('静音 / 恢复音量', []),
  danmaku('显示 / 隐藏弹幕', ['D', 'F9']),
  composeDanmaku('输入 / 发送弹幕', []),
  subtitles('开启 / 关闭字幕', ['F6']),
  slower('降低播放速度', ['F1', 'Semicolon'], addedKeys: ['Shift+ArrowLeft']),
  faster('提高播放速度', ['F2', 'Quote'], addedKeys: ['Shift+ArrowRight']),
  toggleRate('切换 1 / 2 倍速', ['Ctrl+1'], appleKeys: ['Meta+1']),
  normalRate('设为 1 倍速', [], addedKeys: ['Shift+1']),
  doubleRate('设为 2 倍速', [], addedKeys: ['Shift+2']),
  previousPart('上一分 P', ['Z', 'N', 'Comma'], addedKeys: ['BracketLeft']),
  nextPart('下一分 P', ['X', 'M', 'Period'], addedKeys: ['BracketRight']),
  likeVideo('点赞 / 取消点赞视频', [], addedKeys: ['Q']),
  coinVideo('为视频投币', []),
  favoriteVideo('收藏视频', [], addedKeys: ['E']),
  shareVideo('分享视频（复制链接）', [], addedKeys: ['V']),
  toggleVideoDescription('展开 / 收起视频简介', []),
  toggleVideoComments('打开 / 关闭视频评论', [], addedKeys: ['C']),
  previousPlayback('播放历史上一项', [], addedKeys: ['Shift+Comma']),
  nextPlayback('播放历史下一项', [], addedKeys: ['Shift+Period']),
  returnToBrowser('从播放返回主界面', [], addedKeys: ['A']),
  switchPlaybackWindow('在浏览窗和播放窗间切换', [], addedKeys: ['B']),
  toggleMaximized('最大化 / 还原窗口', [], addedKeys: ['G']),
  toggleMiniPlayer('进入 / 退出迷你小窗', [], addedKeys: ['S']),
  toggleSidebar('收起 / 展开侧边栏', ['Ctrl+B'], appleKeys: ['Meta+B']),
  bossKey(
    '老板键',
    ['Ctrl+Shift+Q'],
    appleKeys: ['Shift+Meta+Q'],
    desktopOnly: true,
  ),
  newTab('新建浏览标签', ['Ctrl+T'], appleKeys: ['Meta+T']),
  closeTab(
    '关闭当前标签页',
    ['Ctrl+W', 'MouseBack'],
    appleKeys: ['Meta+W', 'MouseBack'],
  ),
  nextTab('切换到下一个标签页', ['Ctrl+Tab'], appleKeys: ['Shift+Meta+BracketRight']),
  previousTab(
    '切换到上一个标签页',
    ['Ctrl+Shift+Tab'],
    appleKeys: ['Shift+Meta+BracketLeft'],
  ),
  refresh('刷新当前页面', ['Ctrl+R', 'F5'], appleKeys: ['Meta+R', 'F5']);

  const ShortcutAction(
    this.label,
    this.defaultKeys, {
    this.appleKeys,
    this.addedKeys = const [],
    this.desktopOnly = false,
  });
  final String label;
  final List<String> defaultKeys;
  final List<String>? appleKeys;
  final List<String> addedKeys;
  final bool desktopOnly;

  List<String> defaultsFor({required bool useAppleDefaults}) {
    final keys = useAppleDefaults ? appleKeys ?? defaultKeys : defaultKeys;
    return addedKeys.isEmpty
        ? keys
        : List.unmodifiable([...keys, ...addedKeys]);
  }
}

enum ReservedShortcut {
  imageClose,
  imagePrevious,
  imageNext,
  imageZoomIn,
  imageZoomOut,
}

enum FeaturedPagingShortcut { previous, next }
