import 'package:flutter/material.dart';

import 'scroll_collapsing_header.dart';

/// Keeps the comments and its nested coordinator mounted across width changes.
/// On phones the post scrolls away before the comment list; the composer stays
/// available without assigning an arbitrary fixed height to either section.
class DynamicDetailLayout extends StatefulWidget {
  const DynamicDetailLayout({
    super.key,
    required this.content,
    required this.comments,
    this.focusComments = false,
  });
  final Widget content, comments;
  final bool focusComments;

  @override
  State<DynamicDetailLayout> createState() => _DynamicDetailLayoutState();
}

class _DynamicDetailLayoutState extends State<DynamicDetailLayout> {
  final _nested = GlobalKey<NestedScrollViewState>();
  bool _focused = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 900 &&
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(14) >=
              50;
      if (!_focused && widget.focusComments) {
        _focused = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final controller = _nested.currentState?.outerController;
          if (mounted && controller != null && controller.hasClients) {
            controller.jumpTo(controller.position.maxScrollExtent);
          }
        });
      }
      return CustomMultiChildLayout(
        delegate: _DynamicDetailDelegate(wide),
        children: [
          LayoutId(
            id: 0,
            child: wide
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: SingleChildScrollView(
                      key: const PageStorageKey('dynamic-detail-content'),
                      padding: const EdgeInsets.all(12),
                      child: widget.content,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          LayoutId(
            id: 1,
            child: NestedScrollView(
              key: _nested,
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: wide
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: widget.content,
                        ),
                ),
              ],
              body: HeaderScrollBody(child: widget.comments),
            ),
          ),
        ],
      );
    },
  );
}

class _DynamicDetailDelegate extends MultiChildLayoutDelegate {
  _DynamicDetailDelegate(this.wide);
  final bool wide;

  @override
  void performLayout(Size size) {
    final contentWidth = wide ? (size.width * .54).clamp(400.0, 700.0) : 0.0;
    layoutChild(0, BoxConstraints.tight(Size(contentWidth, size.height)));
    positionChild(0, Offset.zero);
    layoutChild(
      1,
      BoxConstraints.tight(Size(size.width - contentWidth, size.height)),
    );
    positionChild(1, Offset(contentWidth, 0));
  }

  @override
  bool shouldRelayout(_DynamicDetailDelegate oldDelegate) =>
      wide != oldDelegate.wide;
}
