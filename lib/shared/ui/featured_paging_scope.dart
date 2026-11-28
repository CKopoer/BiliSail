import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'player_picture.dart';

// The PageView slot owns its inline surface in both preview and selected modes.
final class FeaturedInlinePicture {
  final controller = PlayerPictureController();
  final suspended = ValueNotifier(false);
  bool _disposed = false;

  void setSuspended(bool value) {
    if (!_disposed) suspended.value = value;
  }

  void dispose() {
    _disposed = true;
    controller.dispose();
    suspended.dispose();
  }
}

/// Current card's measured toolbar height and its actual fade progress.
final class FeaturedControlsGeometry {
  final height = ValueNotifier(0.0);
  final opacity = ValueNotifier(0.0);
  double? _pendingHeight;

  void reportHeight(double value) {
    if (_pendingHeight != null) {
      _pendingHeight = value;
      return;
    }
    if (value == height.value) return;
    // Measurement happens during layout; the rail direction depends on it.
    _pendingHeight = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measured = _pendingHeight;
      _pendingHeight = null;
      if (measured != null) height.value = measured;
    });
  }

  void showAudioToolbar(double value) {
    reportHeight(value);
    opacity.value = 1;
  }

  void dispose() {
    _pendingHeight = null;
    height.dispose();
    opacity.dispose();
  }
}

/// Both the picture and its interactive overlays are inside this mouse region.
class FeaturedPlayerMouseRegion extends StatefulWidget {
  const FeaturedPlayerMouseRegion({super.key, required this.child});
  final Widget child;

  static ValueListenable<PointerEvent?>? eventsOf(BuildContext context) =>
      context
          .findAncestorStateOfType<_FeaturedPlayerMouseRegionState>()
          ?.events;

  @override
  State<FeaturedPlayerMouseRegion> createState() =>
      _FeaturedPlayerMouseRegionState();
}

class _FeaturedPlayerMouseRegionState extends State<FeaturedPlayerMouseRegion> {
  final events = ValueNotifier<PointerEvent?>(null);

  void _onMouseEvent(PointerEvent event) => events.value = event;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: _onMouseEvent,
    onHover: _onMouseEvent,
    onExit: _onMouseEvent,
    child: widget.child,
  );

  @override
  void dispose() {
    events.dispose();
    super.dispose();
  }
}

/// Identifies playback owned by a featured viewer.
class FeaturedPagingScope extends InheritedWidget {
  const FeaturedPagingScope({
    super.key,
    required super.child,
    this.inlinePicture,
    this.controlsGeometry,
    this.showVideoOverlays = true,
    this.onToggleVideoOverlays,
  });

  final FeaturedControlsGeometry? controlsGeometry;
  final FeaturedInlinePicture? inlinePicture;
  final bool showVideoOverlays;
  final VoidCallback? onToggleVideoOverlays;

  static FeaturedPagingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeaturedPagingScope>();
  @override
  bool updateShouldNotify(FeaturedPagingScope oldWidget) =>
      !identical(inlinePicture, oldWidget.inlinePicture) ||
      controlsGeometry != oldWidget.controlsGeometry ||
      showVideoOverlays != oldWidget.showVideoOverlays ||
      onToggleVideoOverlays != oldWidget.onToggleVideoOverlays;
}
