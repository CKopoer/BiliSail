import 'package:flutter/material.dart';

import 'window_caption.dart';
import 'window_service.dart';

class PlaybackWindowChrome extends StatelessWidget {
  const PlaybackWindowChrome({
    super.key,
    required this.window,
    required this.onBack,
    required this.onHome,
    required this.onClose,
  });

  final WindowService window;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('playback-window-caption'),
    height: desktopCaptionHeight,
    child: Row(
      children: [
        DesktopCaptionButton(
          tooltip: '返回上一视频',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        DesktopCaptionButton(
          tooltip: '回到主页',
          icon: Icons.home_outlined,
          onPressed: onHome,
        ),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('playback-window-drag-region'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => window.startDraggingPlaybackWindow(),
            onDoubleTap: window.togglePlaybackWindowMaximized,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '哔帆 · 播放',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: desktopCaptionTextStyle,
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: window.alwaysOnTop,
          builder: (context, pinned, _) => DesktopCaptionButton(
            tooltip: pinned ? '取消置顶' : '置顶',
            icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            onPressed: () => window.setAlwaysOnTop(!pinned),
          ),
        ),
        DesktopCaptionButton(
          tooltip: '迷你小窗',
          icon: Icons.picture_in_picture_alt_rounded,
          onPressed: () => window.onMiniPlayerRequested?.call(),
        ),
        DesktopCaptionButton(
          tooltip: '最小化',
          icon: Icons.remove_rounded,
          onPressed: window.minimizePlaybackWindow,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: window.maximized,
          builder: (context, maximized, _) => DesktopCaptionButton(
            tooltip: maximized ? '还原' : '最大化',
            icon: maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            onPressed: window.togglePlaybackWindowMaximized,
          ),
        ),
        DesktopCaptionButton(
          tooltip: '关闭播放',
          icon: Icons.close_rounded,
          onPressed: onClose,
          close: true,
        ),
      ],
    ),
  );
}
