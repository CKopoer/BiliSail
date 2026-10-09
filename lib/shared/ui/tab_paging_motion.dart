import 'package:flutter/widgets.dart';

/// Shared timing for page transitions and standalone tab-strip transitions.
abstract final class TabPagingMotion {
  static const duration = Duration(milliseconds: 200);
  static const ScrollPhysics physics = _TabPagingScrollPhysics();
}

final class _TabPagingScrollPhysics extends ClampingScrollPhysics {
  const _TabPagingScrollPhysics({super.parent});

  // TabController timing affects taps only. PageScrollPhysics uses this spring
  // for release snapping and short-drag rebound, without adding oscillation.
  static final _spring = SpringDescription.withDurationAndBounce(
    duration: TabPagingMotion.duration,
  );

  @override
  SpringDescription get spring => _spring;

  @override
  _TabPagingScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _TabPagingScrollPhysics(parent: buildParent(ancestor));
}
