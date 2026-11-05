import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/window_brightness_service.dart';

/// Only the picture participates; buttons above this layer keep their gestures.
class PlayerSwipeControls extends StatefulWidget {
  const PlayerSwipeControls({
    super.key,
    required this.enabled,
    required this.sourceGeneration,
    required this.volume,
    required this.setVolume,
    required this.child,
    this.brightness,
    this.onFullScreen,
    this.fullScreen = false,
    this.reverseFullScreenGesture = false,
  });

  final bool enabled;
  final int sourceGeneration;
  final double volume;
  final Future<void> Function(double) setVolume;
  final Widget child;
  final WindowBrightnessService? brightness;
  final VoidCallback? onFullScreen;
  final bool fullScreen, reverseFullScreenGesture;

  @override
  State<PlayerSwipeControls> createState() => _PlayerSwipeControlsState();
}

class _PlayerSwipeControlsState extends State<PlayerSwipeControls>
    with WidgetsBindingObserver {
  late final _brightnessService =
      widget.brightness ?? WindowBrightnessService();
  Object? _drag;
  bool _left = false;
  bool _center = false;
  final _pointers = <int>{};
  bool _multiplePointers = false;
  bool _foreground = true;
  bool _readingBrightness = false;
  bool _released = false;
  bool _writingBrightness = false;
  double? _pendingBrightness;
  double _brightness = 1;
  double _startValue = 0;
  double _delta = 0;
  double _height = 1;
  String? _feedback;
  Timer? _feedbackTimer;

  bool get _enabled =>
      (widget.enabled || widget.onFullScreen != null) && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) _cancel();
  }

  @override
  void didUpdateWidget(covariant PlayerSwipeControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceGeneration != widget.sourceGeneration ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.fullScreen != widget.fullScreen ||
        oldWidget.reverseFullScreenGesture != widget.reverseFullScreenGesture ||
        (oldWidget.onFullScreen == null) != (widget.onFullScreen == null)) {
      _cancel();
      if (!widget.enabled) _resetBrightness();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _cancel();
      if (!_foreground) _resetBrightness();
    });
  }

  void _cancel() {
    _drag = null;
    _pendingBrightness = null;
    _feedback = null;
    _feedbackTimer?.cancel();
  }

  void _resetBrightness() {
    _pendingBrightness = null;
    _brightness = 1;
    if (_brightnessService.isNative) {
      unawaited(
        _brightnessService.reset().catchError((Object _) {
          // Android also restores the window override when the engine detaches.
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _resetBrightness();
    super.dispose();
  }

  void _start(DragStartDetails details, Size size) {
    if (!_enabled ||
        _multiplePointers ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _center =
        details.localPosition.dx >= size.width / 3 &&
        details.localPosition.dx < size.width * 2 / 3;
    if (_center ? widget.onFullScreen == null : !widget.enabled) return;
    _feedbackTimer?.cancel();
    if (_center) setState(() => _feedback = null);
    final drag = Object();
    _drag = drag;
    _released = false;
    _left = details.localPosition.dx < size.width / 3;
    _height = size.height;
    _delta = 0;
    _startValue = _left ? _brightness : widget.volume / 100;
    _readingBrightness = !_center && _left && _brightnessService.isNative;
    if (_readingBrightness) unawaited(_readBrightness(drag));
  }

  Future<void> _readBrightness(Object drag) async {
    try {
      final value = await _brightnessService.read();
      if (!mounted ||
          !identical(_drag, drag) ||
          !_enabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _startValue = value;
      _readingBrightness = false;
      _apply();
      if (_released) {
        _drag = null;
        _hideFeedback();
      }
    } catch (_) {
      if (mounted && identical(_drag, drag)) {
        setState(() {
          _drag = null;
          _feedback = '亮度调节失败';
        });
        _hideFeedback();
      }
    }
  }

  void _update(DragUpdateDetails details) {
    if (_drag == null || !_enabled) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      setState(_cancel);
      return;
    }
    _delta -= details.delta.dy / _height;
    if (_center) return;
    if (!_readingBrightness) _apply();
  }

  void _apply() {
    final value = (_startValue + _delta).clamp(_left ? .01 : 0.0, 1.0);
    setState(() {
      _feedback = '${_left ? '亮度' : '音量'} ${(value * 100).round()}%';
      if (_left) _brightness = value;
    });
    if (_left) {
      if (_brightnessService.isNative) {
        _pendingBrightness = value;
        unawaited(_writeBrightness());
      }
    } else {
      final drag = _drag;
      unawaited(
        widget.setVolume(value * 100).catchError((Object _) {
          if (mounted && identical(_drag, drag)) {
            setState(() => _feedback = '音量调节失败');
          }
        }),
      );
    }
  }

  Future<void> _writeBrightness() async {
    if (_writingBrightness) return;
    _writingBrightness = true;
    try {
      while (_pendingBrightness != null) {
        final value = _pendingBrightness;
        _pendingBrightness = null;
        if (value != null) await _brightnessService.set(value);
      }
    } catch (_) {
      _pendingBrightness = null;
      if (mounted && _enabled) {
        setState(() => _feedback = '亮度调节失败');
      }
    } finally {
      _writingBrightness = false;
    }
  }

  void _end() {
    if (_drag == null) return;
    if (_center) {
      _drag = null;
      // Confirm on release, once per gesture, after deliberate movement.
      final pixels = _delta * _height;
      final enter = widget.reverseFullScreenGesture ? pixels < 0 : pixels > 0;
      if (_enabled &&
          !_multiplePointers &&
          ModalRoute.of(context)?.isCurrent != false &&
          pixels.abs() >= 36 &&
          enter != widget.fullScreen) {
        widget.onFullScreen?.call();
      }
      return;
    }
    _released = true;
    if (!_readingBrightness) {
      _drag = null;
      _hideFeedback();
    }
  }

  void _cancelGesture() {
    if (_drag == null) return;
    _drag = null;
    _hideFeedback();
  }

  void _hideFeedback() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.touch) return;
        _pointers.add(event.pointer);
        if (_pointers.length > 1) {
          _multiplePointers = true;
          setState(_cancel);
        }
      },
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        if (_pointers.isEmpty) _multiplePointers = false;
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _cancelGesture();
        if (_pointers.isEmpty) _multiplePointers = false;
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        gestures: {
          if (_enabled)
            VerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer
                >(
                  () =>
                      VerticalDragGestureRecognizer(
                          supportedDevices: {PointerDeviceKind.touch},
                        )
                        ..dragStartBehavior = DragStartBehavior.down
                        ..onlyAcceptDragOnThreshold = true,
                  (recognizer) {
                    recognizer.onStart = (details) =>
                        _start(details, constraints.biggest);
                    recognizer.onUpdate = _update;
                    recognizer.onEnd = (_) => _end();
                    recognizer.onCancel = _cancelGesture;
                  },
                ),
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (!_brightnessService.isNative && _brightness < 1)
              IgnorePointer(
                child: ColoredBox(
                  key: const ValueKey('player-brightness-dimmer'),
                  color: Colors.black.withValues(alpha: 1 - _brightness),
                ),
              ),
            if (_feedback case final feedback?)
              Center(
                child: IgnorePointer(
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('player-swipe-feedback'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        feedback,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
