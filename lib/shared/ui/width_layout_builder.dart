import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds width-dependent content while still laying it out at the current
/// height. Keep height-dependent positioning in a nested [LayoutBuilder].
/// Inherited dependencies and widget updates retain normal builder semantics.
final class WidthLayoutBuilder extends AbstractLayoutBuilder<double> {
  const WidthLayoutBuilder({super.key, required this.builder});

  @override
  final Widget Function(BuildContext context, double width) builder;

  @override
  RenderAbstractLayoutBuilderMixin<double, RenderBox> createRenderObject(
    BuildContext context,
  ) => _RenderWidthLayoutBuilder();
}

final class _RenderWidthLayoutBuilder extends RenderProxyBox
    with
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<double, RenderBox> {
  @override
  double get layoutInfo => constraints.maxWidth;

  @override
  void performLayout() {
    runLayoutCallback();
    super.performLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'WidthLayoutBuilder must build its child during real layout.',
      ),
    );
    return Size.zero;
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'WidthLayoutBuilder must build its child during real layout.',
      ),
    );
    return null;
  }

  double _unsupportedIntrinsic() {
    assert(() {
      if (!RenderObject.debugCheckingIntrinsics) {
        throw FlutterError(
          'WidthLayoutBuilder does not support intrinsic dimensions.',
        );
      }
      return true;
    }());
    return 0;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _unsupportedIntrinsic();
  @override
  double computeMaxIntrinsicWidth(double height) => _unsupportedIntrinsic();
  @override
  double computeMinIntrinsicHeight(double width) => _unsupportedIntrinsic();
  @override
  double computeMaxIntrinsicHeight(double width) => _unsupportedIntrinsic();
}
