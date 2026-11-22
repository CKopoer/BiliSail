import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/responsive_layout_settings.dart';
import 'responsive_layout_scope.dart';

/// Chooses the information position from the unsplit player bounds. The
/// compact summary is laid out at the candidate width only when its inputs
/// change. Expanding the visible description never feeds back into the choice.
class PlaybackSplitLayout extends StatefulWidget {
  const PlaybackSplitLayout({
    super.key,
    required this.page,
    required this.enabled,
    required this.showInfo,
    required this.dimensions,
    required this.contentKey,
    required this.summaryIdentity,
    required this.summaryBuilder,
    required this.builder,
  });

  static const sidebarWidth = 380.0;
  final PlaybackSplitPage page;
  final bool enabled;
  final bool showInfo;
  final VideoDimensions? dimensions;
  final Object contentKey;
  final Object summaryIdentity;
  final Widget Function(BuildContext context, {required bool measuring})?
  summaryBuilder;

  /// The page places the scrollable summary within the available height.
  final Widget Function(
    BuildContext context,
    double maxSummaryHeight,
    Widget? bottomSummary,
  )
  builder;

  static bool infoBelowOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitPosition>()?.below ??
      false;

  static bool readInfoBelow(BuildContext? context) =>
      context?.getInheritedWidgetOfExactType<_SplitPosition>()?.below ?? false;

  @override
  State<PlaybackSplitLayout> createState() => _PlaybackSplitLayoutState();
}

class _PlaybackSplitLayoutState extends State<PlaybackSplitLayout> {
  final _measureKey = GlobalKey();
  Object? _measuredFor;
  Object? _pending;
  double _compactHeight = 0;
  bool _autoBelow = false;

  @override
  void didUpdateWidget(PlaybackSplitLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey) _autoBelow = false;
  }

  void _measure(Object inputs) {
    if (_pending == inputs) return;
    _pending = inputs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pending != inputs) return;
      _pending = null;
      final size = _measureKey.currentContext?.size;
      if (size == null) return;
      setState(() {
        _compactHeight = size.height;
        _measuredFor = inputs;
      });
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final style = ResponsiveLayoutScope.of(context)
          .playbackSplitStyleFor(widget.page);
      final width = math.max(
        0.0,
        bounds.maxWidth - PlaybackSplitLayout.sidebarWidth,
      );
      final dimensions = widget.dimensions;
      final ratio =
          dimensions != null && dimensions.width > 0 && dimensions.height > 0
          ? dimensions.width / dimensions.height
          : null;
      final free = math.max(
        0.0,
        bounds.maxHeight - width / (ratio ?? (16 / 9)),
      );
      final canSplit =
          widget.enabled &&
          widget.summaryBuilder != null &&
          width > 0 &&
          bounds.maxHeight.isFinite &&
          (style == PlaybackSplitStyle.below ||
              (style == PlaybackSplitStyle.automatic &&
                  ratio != null &&
                  free > 0));
      final inputs = (
        widget.summaryIdentity,
        width,
        MediaQuery.textScalerOf(context),
        Theme.of(context),
        Localizations.maybeLocaleOf(context),
        Directionality.of(context),
      );
      final needsMeasure =
          canSplit && widget.showInfo && inputs != _measuredFor;
      if (needsMeasure) {
        _measure(inputs);
      } else {
        _pending = null;
      }
      if (!canSplit || style != PlaybackSplitStyle.automatic) {
        _autoBelow = false;
      } else if (widget.showInfo && !needsMeasure) {
        _autoBelow = free >= _compactHeight + (_autoBelow ? 0 : 24);
      }

      // Keep the last decision for the single layout pass spent measuring a
      // resized window. Never use an assumed aspect ratio in automatic mode.
      final below =
          canSplit && (style == PlaybackSplitStyle.below || _autoBelow);
      final showBelow = below && widget.showInfo;
      final maxSummaryHeight = !showBelow
          ? 0.0
          : style == PlaybackSplitStyle.below && free < _compactHeight
          ? math.min(_compactHeight, bounds.maxHeight * .4)
          : free;
      final bottomSummary = showBelow
          ? Material(
              color: Theme.of(context).colorScheme.surface,
              child: SingleChildScrollView(
                key: PageStorageKey(('playback-summary', widget.contentKey)),
                primary: false,
                child: widget.summaryBuilder!(context, measuring: false),
              ),
            )
          : null;
      return _SplitPosition(
        below: below,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Builder(
              builder: (context) =>
                  widget.builder(context, maxSummaryHeight, bottomSummary),
            ),
            if (needsMeasure)
              Positioned(
                left: 0,
                top: 0,
                width: width,
                child: Offstage(
                  child: ExcludeFocus(
                    child: TickerMode(
                      enabled: false,
                      child: SizedBox(
                        key: _measureKey,
                        child: widget.summaryBuilder!(context, measuring: true),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _SplitPosition extends InheritedWidget {
  const _SplitPosition({required this.below, required super.child});
  final bool below;
  @override
  bool updateShouldNotify(_SplitPosition oldWidget) => below != oldWidget.below;
}
