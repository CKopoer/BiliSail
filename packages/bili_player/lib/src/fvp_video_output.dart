import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'player_contract.dart';
import 'video_composition.dart';

final class FvpVideoOutput implements FlutterVideoOutput, VideoFrameReadiness {
  final _texture = ValueNotifier<({int id, VideoDimensions dimensions})?>(null);
  final _ready = ValueNotifier(false);
  bool _disposed = false;
  int _revision = 0;

  @override
  ValueListenable<bool> get frameReady => _ready;

  void bind(int texture, VideoDimensions dimensions) {
    if (_disposed) return;
    _texture.value = (id: texture, dimensions: dimensions);
  }

  void confirmFrame() {
    final revision = _revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && revision == _revision && _texture.value != null) {
        _ready.value = true;
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void clear() {
    ++_revision;
    _ready.value = false;
    _texture.value = null;
  }

  // Texture output keeps native frame dimensions. Attachment only controls
  // presentation; Flutter must never create a second MDK player on fullscreen.
  @override
  void attach(Object owner) {}
  @override
  void detach(Object owner) {}
  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {}

  @override
  Widget buildVideoSurface() =>
      ValueListenableBuilder<({int id, VideoDimensions dimensions})?>(
        valueListenable: _texture,
        builder: (_, texture, _) => texture == null
            ? const ColoredBox(color: Color(0xFF000000))
            : Center(
                child: AspectRatio(
                  aspectRatio:
                      texture.dimensions.width / texture.dimensions.height,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _ready,
                    child: IgnorePointer(child: Texture(textureId: texture.id)),
                    builder: (_, ready, child) => ready
                        ? child!
                        : ColorFiltered(
                            colorFilter: const ColorFilter.matrix([
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              255,
                            ]),
                            child: child,
                          ),
                  ),
                ),
              ),
      );

  void dispose() {
    if (_disposed) return;
    clear();
    _disposed = true;
    _texture.dispose();
    _ready.dispose();
  }
}
