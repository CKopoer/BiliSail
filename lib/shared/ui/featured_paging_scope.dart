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

/// Identifies playback owned by a featured viewer.
class FeaturedPagingScope extends InheritedWidget {
  const FeaturedPagingScope({
    super.key,
    required super.child,
    this.inlinePicture,
    this.onControlsInsetChanged,
    this.showVideoOverlays = true,
    this.onToggleVideoOverlays,
  });

  /// Height occupied by the inline controls, zero once they finish fading out.
  final ValueChanged<double>? onControlsInsetChanged;
  final FeaturedInlinePicture? inlinePicture;
  final bool showVideoOverlays;
  final VoidCallback? onToggleVideoOverlays;

  static FeaturedPagingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeaturedPagingScope>();
  @override
  bool updateShouldNotify(FeaturedPagingScope oldWidget) =>
      !identical(inlinePicture, oldWidget.inlinePicture) ||
      onControlsInsetChanged != oldWidget.onControlsInsetChanged ||
      showVideoOverlays != oldWidget.showVideoOverlays ||
      onToggleVideoOverlays != oldWidget.onToggleVideoOverlays;
}
