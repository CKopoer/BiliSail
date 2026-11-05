import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef PlayerPictureTransform = ({double scale, Offset offset});

/// Page-owned view state shared by the inline and fullscreen presentations.
class PlayerPictureController extends ValueNotifier<PlayerPictureTransform> {
  PlayerPictureController() : super(identity);

  static const PlayerPictureTransform identity = (
    scale: 1,
    offset: Offset.zero,
  );

  void reset() => value = identity;
}

/// Transforms only the video output, retaining the child across touch updates.
class PlayerPicture extends StatelessWidget {
  const PlayerPicture({
    super.key,
    required this.controller,
    required this.child,
  });

  final PlayerPictureController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder(
        valueListenable: controller,
        child: child,
        builder: (context, value, child) => Transform(
          key: const ValueKey('player-picture-transform'),
          transform: Matrix4.identity()
            ..translateByDouble(
              value.offset.dx * constraints.maxWidth,
              value.offset.dy * constraints.maxHeight,
              0,
              1,
            )
            ..scaleByDouble(value.scale, value.scale, 1, 1),
          child: child,
        ),
      ),
    ),
  );
}

/// Two touch contacts manipulate the picture without repurposing mouse wheels.
class PlayerPictureControls extends StatefulWidget {
  const PlayerPictureControls({
    super.key,
    required this.controller,
    required this.enabled,
    required this.sourceGeneration,
    required this.isCurrent,
    required this.allowShrink,
    required this.onTouchSequence,
    required this.onMultipleTouches,
    required this.child,
  });

  final PlayerPictureController controller;
  final bool enabled, allowShrink;
  final int sourceGeneration;
  final ValueGetter<bool> isCurrent;
  final VoidCallback onTouchSequence, onMultipleTouches;
  final Widget child;

  @override
  State<PlayerPictureControls> createState() => _PlayerPictureControlsState();
}

class _PlayerPictureControlsState extends State<PlayerPictureControls>
    with WidgetsBindingObserver {
  final _pointers = <int, Offset>{};
  bool _foreground = true;
  double _span = 0;
  Offset _anchor = Offset.zero;
  double _scale = 1;
  Size _size = Size.zero;

  bool get _current =>
      mounted &&
      widget.enabled &&
      _foreground &&
      widget.isCurrent() &&
      ModalRoute.of(context)?.isCurrent != false;

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
    if (!_current) _pointers.clear();
  }

  @override
  void didUpdateWidget(covariant PlayerPictureControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceGeneration != widget.sourceGeneration ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.allowShrink != widget.allowShrink) {
      _pointers.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pointers.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pointers.clear();
    super.dispose();
  }

  (Offset, double) get _geometry {
    final points = _pointers.values.take(2).toList(growable: false);
    return ((points[0] + points[1]) / 2, (points[0] - points[1]).distance);
  }

  void _rebase() {
    if (_pointers.length < 2) return;
    final (focal, span) = _geometry;
    final value = widget.controller.value;
    _span = span;
    _scale = value.scale;
    _anchor =
        (focal -
            Offset(
              value.offset.dx * _size.width,
              value.offset.dy * _size.height,
            )) /
        _scale;
  }

  void _down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || !_current) return;
    if (_pointers.isEmpty) widget.onTouchSequence();
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1) {
      widget.onMultipleTouches();
      _rebase();
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    if (!_current) {
      _pointers.clear();
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length < 2 || _span < 1 || _size.isEmpty) return;
    final (focal, span) = _geometry;
    final scale = (_scale * span / _span).clamp(
      widget.allowShrink ? .75 : 1.0,
      2.0,
    );
    final offset = focal - _anchor * scale;
    // Retain a visible part of the picture so a pan cannot lose it entirely.
    widget.controller.value = (
      scale: scale,
      offset: Offset(
        (offset.dx / _size.width).clamp(.1 - scale, .9),
        (offset.dy / _size.height).clamp(.1 - scale, .9),
      ),
    );
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    _rebase();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_size != constraints.biggest) _pointers.clear();
      _size = constraints.biggest;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: (_) => _pointers.clear(),
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          gestures: {
            if (widget.enabled)
              _TwoTouchRecognizer:
                  GestureRecognizerFactoryWithHandlers<_TwoTouchRecognizer>(
                    _TwoTouchRecognizer.new,
                    (_) {},
                  ),
          },
          child: widget.child,
        ),
      );
    },
  );
}

/// Claims two contacts before competing taps or page scrolls can act on them.
/// Raw contacts also allow a scrub/hold already in progress to become a pinch.
class _TwoTouchRecognizer extends OneSequenceGestureRecognizer {
  _TwoTouchRecognizer() : super(supportedDevices: {PointerDeviceKind.touch});

  final _pointers = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointers.add(event.pointer);
    if (_pointers.length > 1) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) =>
      resolve(GestureDisposition.rejected);

  @override
  String get debugDescription => 'player two touch';
}
