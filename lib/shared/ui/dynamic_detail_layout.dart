import 'package:material_ui/material_ui.dart';

import '../../domain/content_link.dart';
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
  }) : sliver = null,
       commentLink = null;

  const DynamicDetailLayout.sliver({
    super.key,
    required this.sliver,
    required this.comments,
    this.commentLink,
  }) : content = null,
       focusComments = false;

  final Widget? content, sliver, comments;
  final bool focusComments;
  final ContentLink? commentLink;

  @override
  State<DynamicDetailLayout> createState() => _DynamicDetailLayoutState();
}

class _DynamicDetailLayoutState extends State<DynamicDetailLayout> {
  final _nested = GlobalKey<NestedScrollViewState>();
  final _reading = ScrollController();
  Object? _focused;
  bool? _wide;

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  ScrollController? _readingController({required bool wide}) =>
      wide ? _reading : _nested.currentState?.outerController;

  void _retainReadingOffset(bool wide) {
    final previous = _wide;
    _wide = wide;
    if (widget.sliver == null || previous == null || previous == wide) return;
    final scroll = _readingController(wide: previous);
    if (scroll == null || !scroll.hasClients) return;
    final offset = scroll.offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _wide != wide) return;
      final reading = _readingController(wide: wide);
      if (reading == null || !reading.hasClients) return;
      final position = reading.position;
      final destination = offset.clamp(0.0, position.maxScrollExtent);
      // A jump on the outer controller also resets the comment list.
      position.setPixels(destination);
    });
  }

  void _focusComments(Object focus, {int attempts = 4}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _wide != false || _focused != focus) return;
      final controller = _nested.currentState?.outerController;
      if (controller == null || !controller.hasClients) return;
      final position = controller.position;
      if (position.extentAfter <= 1) return;
      position.setPixels(position.maxScrollExtent);
      // A lazily laid out article can expose more height after the jump.
      if (widget.sliver != null && attempts > 1) {
        _focusComments(focus, attempts: attempts - 1);
      }
    });
  }

  Widget _contentSliver({required bool wide}) =>
      widget.sliver ??
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(wide ? 12 : 8),
          child: widget.content,
        ),
      );

  Widget _readingView() => widget.sliver == null
      ? SingleChildScrollView(
          key: const PageStorageKey('dynamic-detail-content'),
          padding: const EdgeInsets.all(12),
          child: widget.content,
        )
      : CustomScrollView(
          key: const PageStorageKey('dynamic-detail-content'),
          controller: _reading,
          slivers: [_contentSliver(wide: true)],
        );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final comments = widget.comments;
      if (comments == null) return _readingView();
      final wide =
          constraints.maxWidth >= 900 &&
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(14) >=
              50;
      _retainReadingOffset(wide);
      final link = widget.commentLink;
      final focus = link?.comment != null
          ? link
          : widget.focusComments
          ? true
          : null;
      if (focus == null) {
        _focused = null;
      } else if (!wide && _focused != focus) {
        _focused = focus;
        _focusComments(focus);
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
                    child: _readingView(),
                  )
                : const SizedBox.shrink(),
          ),
          LayoutId(
            id: 1,
            child: NestedScrollView(
              key: _nested,
              headerSliverBuilder: (context, _) => [
                if (!wide) _contentSliver(wide: false),
              ],
              body: HeaderScrollBody(child: comments),
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
