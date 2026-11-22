import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../core/presentation/workspace_activity.dart';

/// Limits outstanding local image loads even when a scrollbar drag crosses
/// many rows before the viewport paints. Flutter owns the decoded image cache.
final class DownloadCoverLoader {
  static const _maximumLoads = 2;
  final _waiting = <_DownloadLocalCoverState>{};
  int _loading = 0;
  bool _scheduled = false;
  bool _disposed = false;

  void _request(_DownloadLocalCoverState cover) {
    if (_disposed) return;
    _waiting.add(cover);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _waiting.isEmpty || _loading >= _maximumLoads) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      while (_loading < _maximumLoads && _waiting.isNotEmpty) {
        final cover = _waiting.first;
        _waiting.remove(cover);
        if (!cover._canLoad) continue;
        _loading++;
        unawaited(
          cover._load().whenComplete(() {
            _loading--;
            _schedule();
          }),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void dispose() {
    _disposed = true;
    _waiting.clear();
  }
}

final class DownloadLocalCover extends StatefulWidget {
  const DownloadLocalCover({
    super.key,
    required this.loader,
    required this.image,
    required this.placeholder,
  });

  final DownloadCoverLoader loader;
  final ImageProvider<Object> image;
  final Widget placeholder;

  @override
  State<DownloadLocalCover> createState() => _DownloadLocalCoverState();
}

final class _DownloadLocalCoverState extends State<DownloadLocalCover> {
  bool _active = false;
  bool _loading = false;
  bool? _ready;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!_active) widget.loader._waiting.remove(this);
  }

  @override
  void didUpdateWidget(DownloadLocalCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader || oldWidget.image != widget.image) {
      oldWidget.loader._waiting.remove(this);
      _generation++;
      _loading = false;
      _ready = null;
    }
  }

  bool get _needsLoad => _active && !_loading && _ready == null;

  bool get _canLoad {
    if (!mounted || !_needsLoad) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    for (
      RenderObject? ancestor = box.parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor is RenderAbstractViewport &&
          !MatrixUtils.transformRect(
            box.getTransformTo(ancestor),
            box.paintBounds,
          ).overlaps(ancestor.paintBounds)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _load() async {
    final generation = _generation;
    _loading = true;
    var succeeded = true;
    await precacheImage(
      widget.image,
      context,
      onError: (_, _) => succeeded = false,
    );
    if (!mounted || generation != _generation) return;
    _loading = false;
    if (_canLoad) setState(() => _ready = succeeded);
  }

  @override
  void dispose() {
    widget.loader._waiting.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CoverPaint(
    onPaint: () {
      if (_needsLoad) widget.loader._request(this);
    },
    child: _ready == true
        ? Image(
            image: widget.image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => widget.placeholder,
          )
        : widget.placeholder,
  );
}

final class _CoverPaint extends SingleChildRenderObjectWidget {
  const _CoverPaint({required this.onPaint, required super.child});

  final VoidCallback onPaint;

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderCoverPaint(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCoverPaint renderObject,
  ) {
    renderObject.onPaint = onPaint;
    renderObject.markNeedsPaint();
  }
}

final class _RenderCoverPaint extends RenderProxyBox {
  _RenderCoverPaint(this.onPaint);

  VoidCallback onPaint;

  // The card supplies the cover's tight bounds. A decoded frame changing the
  // child can then lay itself out without invalidating the list's row heights.
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void performLayout() => child?.layout(BoxConstraints.tight(size));

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
