import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'smooth_scroll_behavior.dart';

/// Compact content filters share a text-only row, independent of page tabs.
class ContentSectionTabs<T extends Object> extends StatefulWidget {
  const ContentSectionTabs({
    super.key,
    required this.entries,
    required this.value,
    required this.onSelected,
    this.itemKey,
    this.scrollKey,
    this.wrap = false,
  });

  final List<(T, String)> entries;
  final T? value;
  final ValueChanged<T> onSelected;
  final Key Function(T)? itemKey;
  final Key? scrollKey;
  final bool wrap;

  @override
  State<ContentSectionTabs<T>> createState() => _ContentSectionTabsState<T>();
}

class _ContentSectionTabsState<T extends Object>
    extends State<ContentSectionTabs<T>> {
  final _scrollController = ScrollController();
  final _itemKeys = <T, GlobalKey>{};
  bool _revealPending = false;
  double? _viewportWidth;

  void _revealSelection() {
    if (_revealPending) return;
    _revealPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealPending = false;
      if (!mounted || !_scrollController.hasClients) return;
      final target = _itemKeys[widget.value]?.currentContext
          ?.findRenderObject();
      final position = _scrollController.position;
      if (target is! RenderBox ||
          !target.hasSize ||
          !position.hasContentDimensions) {
        return;
      }
      final viewport = RenderAbstractViewport.of(target);
      final leading = viewport.getOffsetToReveal(target, 0).offset;
      final trailing = viewport.getOffsetToReveal(target, 1).offset;
      // Move only this horizontal viewport, and only enough to reveal the tab.
      // Data rebuilds must leave the user's manual wheel position untouched.
      final requiredOffset = trailing > leading
          ? leading
          : position.pixels.clamp(trailing, leading);
      final offset = requiredOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((offset - position.pixels).abs() > .5) position.jumpTo(offset);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.textScalerOf(context);
    _revealSelection();
  }

  @override
  void didUpdateWidget(ContentSectionTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.wrap != widget.wrap ||
        !listEquals(oldWidget.entries, widget.entries)) {
      _revealSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ids = widget.entries.map((entry) => entry.$1).toSet();
    _itemKeys.removeWhere((id, _) => !ids.contains(id));
    final tabs = [
      for (final (id, label) in widget.entries)
        Padding(
          key: _itemKeys.putIfAbsent(id, GlobalKey.new),
          padding: const EdgeInsets.only(right: 4),
          child: Semantics(
            selected: widget.value == id,
            child: TextButton(
              key: widget.itemKey?.call(id),
              style:
                  TextButton.styleFrom(
                    foregroundColor: widget.value == id
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused)
                          ? colors.surfaceContainerLow
                          : Colors.transparent,
                    ),
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? colors.onSurface.withValues(alpha: .06)
                          : Colors.transparent,
                    ),
                  ),
              onPressed: () => widget.onSelected(id),
              child: Text(label, maxLines: 1),
            ),
          ),
        ),
    ];
    return SizedBox(
      width: double.infinity,
      height: widget.wrap ? null : 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_viewportWidth != constraints.maxWidth) {
              _viewportWidth = constraints.maxWidth;
              _revealSelection();
            }
            if (widget.wrap) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(runSpacing: 4, children: tabs),
              );
            }
            return ScrollConfiguration(
              behavior: const SmoothScrollBehavior(horizontalMouseWheel: true),
              child: SingleChildScrollView(
                key: widget.scrollKey,
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: tabs),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
