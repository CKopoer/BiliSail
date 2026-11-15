import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Lays out one inert widget at a time, then disposes the detached tree.
/// Callers must replace image requests and interactive state with placeholders.
class WidgetMeasurement {
  WidgetMeasurement(this.context, this.width) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    _view = RenderView(
      view: View.of(context),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(Size(width, 1)),
        physicalConstraints: BoxConstraints.tight(Size(width, 1) * ratio),
        devicePixelRatio: ratio,
      ),
      child: _root,
    );
    _pipeline.rootNode = _view;
    _view.prepareInitialFrame();
  }

  final BuildContext context;
  final double width;
  // A secondary BuildOwner must not register a second global key handler.
  final _owner = BuildOwner(focusManager: FocusManager());
  final _pipeline = PipelineOwner();
  late final RenderView _view;
  double? _height;
  final _root = RenderPositionedBox(
    alignment: Alignment.topLeft,
    heightFactor: 1,
  );
  RenderObjectToWidgetElement<RenderBox>? _element;

  double height(Widget widget) {
    _height = null;
    final child = InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: MediaQuery.of(context),
        child: Directionality(
          textDirection: Directionality.of(context),
          child: Localizations.override(
            context: context,
            child: DefaultTextStyle(
              style: DefaultTextStyle.of(context).style,
              child: TooltipVisibility(
                visible: false,
                child: TickerMode(
                  enabled: false,
                  child: UnconstrainedBox(
                    constrainedAxis: Axis.horizontal,
                    child: _MeasureHeight(
                      onHeight: (height) => _height = height,
                      child: widget,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _element = RenderObjectToWidgetAdapter<RenderBox>(
      container: _root,
      child: child,
    ).attachToRenderTree(_owner, _element);
    _owner.buildScope(_element!);
    _pipeline.flushLayout();
    _owner.finalizeTree();
    return _height ?? (throw StateError('Widget did not lay out'));
  }

  void dispose() {
    final element = _element;
    if (element != null) {
      RenderObjectToWidgetAdapter<RenderBox>(container: _root)
          .attachToRenderTree(_owner, element);
      _owner.buildScope(element);
      _owner.finalizeTree();
    }
    _pipeline.rootNode = null;
    _view.child = null;
    _root.dispose();
    _view.dispose();
    _pipeline.dispose();
    _owner.focusManager.dispose();
  }
}

class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
