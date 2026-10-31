import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/presentation/workspace_activity.dart';

/// Shares the workspace's choice of scrolling or fixed page headers.
class ScrollHeaderRegion extends InheritedWidget {
  const ScrollHeaderRegion({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool isEnabled(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ScrollHeaderRegion>()
          ?.enabled ??
      false;

  @override
  bool updateShouldNotify(ScrollHeaderRegion oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Scrolls the header before the body, and restores it only at the body's top.
/// The body's tab strip stays outside its retained, independently scrolling lists.
class ScrollHeaderLayout extends StatefulWidget {
  const ScrollHeaderLayout({
    super.key,
    required this.enabled,
    required this.header,
    required this.child,
  });

  final bool enabled;
  final Widget header;
  final Widget child;

  @override
  State<ScrollHeaderLayout> createState() => _ScrollHeaderLayoutState();
}

class _ScrollHeaderLayoutState extends State<ScrollHeaderLayout> {
  final _headerFocus = FocusScopeNode(debugLabel: 'scrolling header');
  final _nestedKey = GlobalKey<NestedScrollViewState>();
  bool _active = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = WorkspaceActivity.isActive(context);
    if (_active && !active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _active) return;
        final nested = _nestedKey.currentState;
        if (nested == null) return;
        for (final position in [
          ...nested.outerController.positions,
          ...nested.innerController.positions,
        ]) {
          if (position case final ScrollActivityDelegate delegate) {
            delegate.goIdle();
          }
        }
      });
    }
    _active = active;
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.enabled &&
        notification.metrics.axis == Axis.vertical &&
        _headerFocus.hasFocus &&
        ((notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle))) {
      // A focused search field would otherwise request showOnScreen and pull
      // the header back while the user is scrolling the content.
      _headerFocus.unfocus();
    }
    return false;
  }

  @override
  void dispose() {
    _headerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = FocusScope(node: _headerFocus, child: widget.header);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: IgnorePointer(
        ignoring: !_active,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.enabled) header else const SizedBox.shrink(),
            Expanded(
              child: NestedScrollView(
                key: _nestedKey,
                // Keep the same coordinator at every width so retained list positions do
                // not change type when the header switches between scrolling and pinned.
                physics: const ClampingScrollPhysics(),
                headerSliverBuilder: (context, _) => [
                  _FadingHeaderSliver(
                    child: widget.enabled ? header : const SizedBox.shrink(),
                  ),
                ],
                body: Builder(
                  builder: (context) => _ScrollHeaderBody(
                    nested: context
                        .findAncestorStateOfType<NestedScrollViewState>()!,
                    child: PrimaryScrollController.none(child: widget.child),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollHeaderBody extends InheritedWidget {
  const _ScrollHeaderBody({required this.nested, required super.child});
  final NestedScrollViewState nested;

  @override
  bool updateShouldNotify(_ScrollHeaderBody oldWidget) =>
      nested != oldWidget.nested;
}

/// Gives each retained list its own controller while attaching only the active
/// list to NestedScrollView. Sharing the primary controller directly would
/// otherwise scroll every visited tab at once.
class HeaderScrollController extends ScrollController {
  HeaderScrollController({super.keepScrollOffset});

  ScrollController? _parent;
  NestedScrollViewState? _nested;
  bool _active = false;
  static final _offsets = Expando<HeaderScrollOffset>();

  void configure(BuildContext context, {required bool active}) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_ScrollHeaderBody>();
    // Query-replacement views (currently search) explicitly opt out of retained
    // offsets and do not have a scrolling header.
    final parent = keepScrollOffset ? scope?.nested.innerController : null;
    // A list stays inside its layout for its lifetime, including width changes.
    assert(!hasClients || identical(parent, _parent));
    if (active == _active && identical(parent, _parent)) return;
    if (_active) {
      for (final position in positions) {
        _parent?.detach(position);
      }
    }
    _parent = parent;
    _nested = parent == null ? null : scope?.nested;
    _active = active;
    if (_active) {
      for (final position in positions) {
        _parent?.attach(position);
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active) return;
        for (final position in positions) {
          if (position case final ScrollActivityDelegate delegate) {
            delegate.goIdle();
          }
        }
      });
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      _parent?.createScrollPosition(physics, context, oldPosition) ??
      super.createScrollPosition(physics, context, oldPosition);

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (_nested case final nested?) {
      _offsets[position] = HeaderScrollOffset(nested, position);
    }
    if (_active) _parent?.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    if (_active) _parent?.detach(position);
    _offsets[position] = null;
    super.detach(position);
  }

  static HeaderScrollOffset? offsetFor(ScrollPosition position) =>
      _offsets[position];

  @override
  void jumpTo(double value) {
    final nested = _nested;
    if (value == 0 && _active && nested != null) {
      nested.outerController.jumpTo(0);
    } else {
      super.jumpTo(value);
    }
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    final nested = _nested;
    if (offset == 0 && _active && nested != null) {
      return nested.outerController.animateTo(
        0,
        duration: duration,
        curve: curve,
      );
    }
    return super.animateTo(offset, duration: duration, curve: curve);
  }
}

/// Combined distance and activities for the existing desktop wheel spring.
class HeaderScrollOffset {
  HeaderScrollOffset(this._nested, this.inner);
  final NestedScrollViewState _nested;
  final ScrollPosition inner;
  ScrollPosition get _outer => _nested.outerController.position;
  double get pixels => _outer.pixels + inner.pixels;
  double get minScrollExtent => _outer.minScrollExtent + inner.minScrollExtent;
  double get maxScrollExtent => _outer.maxScrollExtent + inner.maxScrollExtent;

  void beginActivity(ScrollActivity activity) {
    final outer = _outer;
    if (outer case final ScrollActivityDelegate delegate) {
      outer.beginActivity(_HeaderWheelActivity(delegate, activity));
    }
    inner.beginActivity(activity);
  }

  void applyDelta(double delta) {
    // The wheel keeps both positions scrolling for its entire lifetime. Using
    // pointerScroll for each frame would emit start/end on every tick and let
    // hover previews restart in the middle of a continuous wheel gesture.
    final first = delta > 0 ? _outer : inner;
    final second = delta > 0 ? inner : _outer;
    final before = first.pixels;
    first.setPixels(
      (before + delta).clamp(first.minScrollExtent, first.maxScrollExtent),
    );
    final remainder = delta - (first.pixels - before);
    if (remainder != 0) {
      second.setPixels(
        (second.pixels + remainder).clamp(
          second.minScrollExtent,
          second.maxScrollExtent,
        ),
      );
    }
  }

  void goIdle() {
    for (final position in [inner, _outer]) {
      if (position case final ScrollActivityDelegate delegate) {
        delegate.goIdle();
      }
    }
  }
}

class _HeaderWheelActivity extends ScrollActivity {
  _HeaderWheelActivity(super.delegate, this.motion);
  final ScrollActivity motion;

  @override
  bool get shouldIgnorePointer => false;
  @override
  bool get isScrolling => true;
  @override
  double get velocity => motion.velocity;

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }
}

class _FadingHeaderSliver extends SingleChildRenderObjectWidget {
  const _FadingHeaderSliver({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFadingHeader();
}

class _RenderFadingHeader extends RenderSliverToBoxAdapter {
  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();

  int get _alpha {
    final height = child?.size.height ?? 0;
    return height <= 0
        ? 0
        : ((1 - constraints.scrollOffset / height).clamp(0, 1) * 255).round();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_alpha == 0 || geometry?.visible != true) {
      _opacityLayer.layer = null;
      return;
    }
    _opacityLayer.layer = context.pushOpacity(
      offset,
      _alpha,
      super.paint,
      oldLayer: _opacityLayer.layer,
    );
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    super.dispose();
  }
}
