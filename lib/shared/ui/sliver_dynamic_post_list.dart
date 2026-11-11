import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dynamic/application/dynamic_content_state.dart';

import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';
import 'dynamic_post_card.dart';
import 'dynamic_post_interactions.dart';

/// Natural-height, lazy dynamic cards with a known extent for every loaded post.
/// SliverList's visible-row average is unsuitable for heterogeneous dynamic
/// cards: it changes the scrollbar range whenever a different row is visible.
class SliverDynamicPostList extends ConsumerWidget {
  const SliverDynamicPostList({
    super.key,
    required this.posts,
    this.spacing = 16,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
    this.pinnedFirst = false,
  });

  final List<DynamicPost> posts;
  final double spacing;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;
  final bool pinnedFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(dynamicContentProvider);
    final pinned = {
      for (final p in content.posts.values)
        if (p.pinned && p.authorId != null) p.authorId!.value: p.id,
    };
    final visible = [
      for (final post in posts)
        if (!content.hidden(post)) content.posts[post.id] ?? post,
    ];
    for (var i = 0; i < visible.length; i++) {
      final p = visible[i], chosen = pinned[p.authorId?.value];
      if (p.pinned && chosen != null && chosen != p.id) {
        visible[i] = p.withManagement(pinned: false);
      }
    }
    final ordered = pinnedFirst
        ? [
            ...visible.where((p) => p.pinned),
            ...visible.where((p) => !p.pinned),
          ]
        : visible;
    return _RetainedDynamicPostList(
      posts: ordered,
      spacing: spacing,
      onOpenUser: onOpenUser,
      onOpenVideo: onOpenVideo,
      onOpenLink: onOpenLink,
      onLogin: onLogin,
    );
  }
}

class _RetainedDynamicPostList extends StatefulWidget {
  const _RetainedDynamicPostList({
    required this.posts,
    required this.spacing,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
  });
  final List<DynamicPost> posts;
  final double spacing;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;
  @override
  State<_RetainedDynamicPostList> createState() =>
      _SliverDynamicPostListState();
}

class _SliverDynamicPostListState extends State<_RetainedDynamicPostList> {
  final _extents = <String, (DynamicPost, double)>{};
  final _pendingSizes = <String, (DynamicPost, double)>{};
  final _expansionState = DynamicPostExpansionState();
  double? _width;
  Widget? _sliver;
  bool _sizeUpdateScheduled = false;
  Object? _textLayout;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_invalidateLayout);
  }

  void _invalidateLayout() {
    if (!mounted) return;
    setState(() {
      _extents.clear();
      _pendingSizes.clear();
      _sliver = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Insets, viewport height and page activity do not change card heights.
    // In particular, opening an IME elsewhere must not synchronously measure
    // every loaded post in each retained/offstage dynamic list again.
    final defaults = DefaultTextStyle.of(context);
    final textLayout = (
      Theme.of(context),
      MediaQuery.textScalerOf(context),
      MediaQuery.boldTextOf(context),
      Directionality.of(context),
      Localizations.localeOf(context),
      defaults.style,
      defaults.textAlign,
      defaults.softWrap,
      defaults.overflow,
      defaults.maxLines,
      defaults.textWidthBasis,
      defaults.textHeightBehavior,
    );
    if (_textLayout != textLayout) {
      _textLayout = textLayout;
      _extents.clear();
      _pendingSizes.clear();
      _sliver = null;
    }
  }

  @override
  void didUpdateWidget(_RetainedDynamicPostList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sliver = null;
    if (oldWidget.spacing != widget.spacing ||
        (oldWidget.onOpenLink == null) != (widget.onOpenLink == null)) {
      _extents.clear();
    }
    if (identical(oldWidget.posts, widget.posts)) return;
    final ids = widget.posts.map((post) => post.id).toSet();
    void retainOriginals(DynamicPost post, int depth) {
      ids.add(post.id);
      if (post.original case final original? when depth < 2) {
        retainOriginals(original, depth + 1);
      }
    }

    for (final post in widget.posts) {
      retainOriginals(post, 0);
    }
    _expansionState.retain(ids);
    _extents.removeWhere((id, _) => !ids.contains(id));
    _pendingSizes.clear();
  }

  Widget _row(Widget card) => Padding(
    padding: EdgeInsets.only(bottom: widget.spacing),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: card,
      ),
    ),
  );

  void _recordSize(DynamicPost post, double height) {
    final previous = _extents[post.id];
    if (previous == null ||
        !identical(previous.$1, post) ||
        (previous.$2 - height).abs() < .01) {
      return;
    }
    _pendingSizes[post.id] = (post, height);
    if (_sizeUpdateScheduled) return;
    _sizeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sizeUpdateScheduled = false;
      if (!mounted || _pendingSizes.isEmpty) return;
      setState(() {
        _extents.addAll(_pendingSizes);
        _pendingSizes.clear();
        _sliver = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      if (_width != constraints.crossAxisExtent) {
        _width = constraints.crossAxisExtent;
        _extents.clear();
        _pendingSizes.clear();
        _sliver = null;
      }
      final cached = _sliver;
      if (cached != null) return cached;

      final missing = widget.posts.where(
        (post) => !identical(_extents[post.id]?.$1, post),
      );
      if (missing.isNotEmpty) {
        final measurement = _CardMeasurement(
          context,
          constraints.crossAxisExtent,
        );
        try {
          for (final post in missing) {
            final height = measurement.height(
              _row(
                DynamicPostCard.forLayout(
                  key: ValueKey(post.id),
                  post: post,
                  expansionState: _expansionState,
                  onOpenLink: widget.onOpenLink,
                ),
              ),
            );
            _extents[post.id] = (post, height);
          }
        } finally {
          measurement.dispose();
        }
      }
      final extent = widget.posts.fold<double>(
        0,
        (sum, post) => sum + _extents[post.id]!.$2,
      );
      final indices = {
        for (final (index, post) in widget.posts.indexed) post.id: index,
      };
      return _sliver = _KnownExtentSliverList(
        delegate: _KnownExtentDelegate(
          (context, index) {
            final post = widget.posts[index];
            return _ObserveHeight(
              key: ValueKey(post.id),
              onHeight: (height) => _recordSize(post, height),
              child: _row(
                InteractiveDynamicPostCard(
                  key: ValueKey(post.id),
                  post: post,
                  expansionState: _expansionState,
                  onOpenUser: widget.onOpenUser,
                  onOpenVideo: widget.onOpenVideo,
                  onOpenLink: widget.onOpenLink,
                  onLogin: widget.onLogin,
                ),
              ),
            );
          },
          childCount: widget.posts.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? indices[key.value] : null,
          extent: extent,
        ),
      );
    },
  );

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_invalidateLayout);
    super.dispose();
  }
}

class _KnownExtentSliverList extends SliverList {
  const _KnownExtentSliverList({required super.delegate});

  @override
  void updateRenderObject(BuildContext context, RenderSliverList renderObject) {
    super.updateRenderObject(context, renderObject);
    // Appending offscreen entries or changing a recorded extent can leave every
    // mounted row's size unchanged. The delegate still changes total geometry.
    renderObject.markNeedsLayout();
  }
}

class _KnownExtentDelegate extends SliverChildBuilderDelegate {
  _KnownExtentDelegate(
    super.builder, {
    required super.childCount,
    required super.findChildIndexCallback,
    required this.extent,
  });

  final double extent;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => extent;
}

/// Layout one inert card at a time, then dispose its entire detached tree.
/// Pagination measures only new/changed posts; scrolling reuses cached extents.
/// Images are fixed-size placeholders, and no interactive providers are mounted.
class _CardMeasurement {
  _CardMeasurement(this.context, this.width) {
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

  double height(Widget card) {
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
                    child: _ObserveHeight(
                      onHeight: (height) => _height = height,
                      child: card,
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
    return _height ?? (throw StateError('Dynamic card did not lay out'));
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

class _ObserveHeight extends SingleChildRenderObjectWidget {
  const _ObserveHeight({
    super.key,
    required this.onHeight,
    required super.child,
  });

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderObserveHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderObserveHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderObserveHeight extends RenderProxyBox {
  _RenderObserveHeight(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
