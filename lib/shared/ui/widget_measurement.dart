import 'package:material_ui/material_ui.dart';
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
  // Give the row the available width and let it take its natural height.
  final _root = RenderConstrainedOverflowBox(
    alignment: Alignment.topLeft,
    minWidth: 0,
    minHeight: 0,
    maxHeight: double.infinity,
  );
  RenderObjectToWidgetElement<RenderBox>? _element;

  double height(Widget widget) {
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
                child: TickerMode(enabled: false, child: widget),
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
    // A reused row may already have a valid layout after the tree update.
    final row = _root.child;
    if (row == null || !row.hasSize) throw StateError('Widget did not lay out');
    return row.size.height;
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
