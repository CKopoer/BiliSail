import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'player_contract.dart';
import 'video_composition.dart';

final class NativeTextureVideoOutput
    implements FlutterVideoOutput, VideoFrameReadiness {
  final _texture = ValueNotifier<({int id, VideoDimensions dimensions})?>(null);
  final _ready = ValueNotifier(false);
  bool _disposed = false;
  int _revision = 0;
  Object? _owner;
  Completer<void>? _presentation;

  @override
  ValueListenable<bool> get frameReady => _ready;

  void bind(int texture, VideoDimensions dimensions) {
    if (_disposed) return;
    _texture.value = (id: texture, dimensions: dimensions);
  }

  Future<void> confirmFrame() {
    final revision = _revision;
    final presented = _presentation = Completer<void>();
    void complete() {
      if (!presented.isCompleted) presented.complete();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && revision == _revision && _texture.value != null) {
        _ready.value = true;
      }
      // The frame above still painted the black preparation filter. Wait for
      // the following frame to paint the revealed texture before audio escapes.
      WidgetsBinding.instance.addPostFrameCallback((_) => complete());
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
    // Headless playback and detached views must not require Flutter frames.
    return _owner == null ? Future<void>.value() : presented.future;
  }

  void clear() {
    ++_revision;
    _completePresentation();
    _ready.value = false;
    _texture.value = null;
  }

  // Texture output keeps native frame dimensions. Attachment only controls
  // presentation; Flutter must never create a second native player on fullscreen.
  @override
  void attach(Object owner) => _owner = owner;
  @override
  void detach(Object owner) {
    if (identical(owner, _owner)) {
      _owner = null;
      _completePresentation();
    }
  }

  void _completePresentation() {
    final presentation = _presentation;
    if (presentation != null && !presentation.isCompleted) {
      presentation.complete();
    }
    _presentation = null;
  }

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
