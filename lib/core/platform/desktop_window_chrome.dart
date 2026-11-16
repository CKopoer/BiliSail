import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart'
    show DragToMoveArea, WindowListener, windowManager;

import 'window_caption.dart';

/// Platform chrome is injected by the app, keeping the workspace testable.
final class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() {});

  @override
  void onWindowUnmaximize() => setState(() {});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 138,
    height: desktopCaptionHeight,
    child: Row(
      children: [
        DesktopCaptionButton(
          tooltip: '最小化',
          icon: Icons.remove_rounded,
          onPressed: () async {
            if (await windowManager.isMinimized()) {
              await windowManager.restore();
            } else {
              await windowManager.minimize();
            }
          },
        ),
        FutureBuilder<bool>(
          future: windowManager.isMaximized(),
          builder: (context, snapshot) {
            final maximized = snapshot.data == true;
            return DesktopCaptionButton(
              tooltip: maximized ? '还原' : '最大化',
              icon: maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              onPressed: () => maximized
                  ? windowManager.unmaximize()
                  : windowManager.maximize(),
            );
          },
        ),
        DesktopCaptionButton(
          tooltip: '关闭窗口',
          icon: Icons.close_rounded,
          onPressed: windowManager.close,
          close: true,
        ),
      ],
    ),
  );
}

final class DesktopDragRegion extends StatelessWidget {
  const DesktopDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DragToMoveArea(child: child);
}
