import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/state_view.dart';
import '../domain/home_channel.dart';

typedef HomeChannelPageBuilder = Widget Function(
  BuildContext context,
  HomeChannel channel,
  bool active,
);

/// Native tab paging keeps the outgoing and incoming pages on screen together.
final class HomeChannelSwipe extends StatefulWidget {
  const HomeChannelSwipe({
    super.key,
    required this.channel,
    required this.onChanged,
    required this.pageBuilder,
  });

  final HomeChannel channel;
  final ValueChanged<HomeChannel> onChanged;
  final HomeChannelPageBuilder pageBuilder;

  @override
  State<HomeChannelSwipe> createState() => _HomeChannelSwipeState();
}

final class _HomeChannelSwipeState extends State<HomeChannelSwipe>
    with TickerProviderStateMixin {
  TabController? _tabs;
  late final _selection = ValueNotifier(widget.channel);
  bool _dragging = false;
  bool _active = true;
  int _generation = 0;

  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 300);

  void _replaceController() {
    _generation++;
    _dragging = false;
    _tabs?.dispose();
    _tabs = TabController(
      length: HomeChannel.values.length,
      initialIndex: widget.channel.index,
      animationDuration: _duration,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = WorkspaceActivity.isActive(context);
    if (_tabs == null ||
        _tabs?.animationDuration != _duration ||
        (_active && !active)) {
      _replaceController();
    }
    _active = active;
  }

  @override
  void didUpdateWidget(HomeChannelSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) {
      _generation++;
      _selection.value = widget.channel;
      if (_dragging) {
        _replaceController();
      } else {
        _tabs?.animateTo(widget.channel.index);
      }
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
    }
    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      final generation = _generation;
      final index = _tabs?.index;
      // Scroll notifications can arrive during layout. Commit only the settled
      // user selection, and let cancellation or an external route supersede it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _generation &&
            WorkspaceActivity.isActive(context) &&
            index != null &&
            index != widget.channel.index) {
          widget.onChanged(HomeChannel.values[index]);
        }
      });
    }
    return false;
  }

  void _cancelPointer(PointerCancelEvent event) {
    if (!_dragging) return;
    // An accepted Flutter drag reports pointer cancellation as drag end.
    // Replacing the controller restores the routed page before it can commit.
    setState(_replaceController);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: _cancelPointer,
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
          },
          scrollbars: false,
        ),
        child: TabBarView(
          key: const ValueKey('home-channel-swipe'),
          controller: _tabs,
          physics: _active
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          dragStartBehavior: DragStartBehavior.down,
          children: [
            for (final channel in HomeChannel.values)
              _RetainedChannelPage(
                key: ValueKey(channel),
                channel: channel,
                selection: _selection,
                pageBuilder: widget.pageBuilder,
                scrollBehavior: ScrollConfiguration.of(context),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _tabs?.dispose();
    _selection.dispose();
    super.dispose();
  }
}

final class _RetainedChannelPage extends StatefulWidget {
  const _RetainedChannelPage({
    super.key,
    required this.channel,
    required this.selection,
    required this.pageBuilder,
    required this.scrollBehavior,
  });

  final HomeChannel channel;
  final ValueNotifier<HomeChannel> selection;
  final HomeChannelPageBuilder pageBuilder;
  final ScrollBehavior scrollBehavior;

  @override
  State<_RetainedChannelPage> createState() => _RetainedChannelPageState();
}

final class _RetainedChannelPageState extends State<_RetainedChannelPage>
    with AutomaticKeepAliveClientMixin {
  bool _visited = false;

  @override
  bool get wantKeepAlive => _visited;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // TabBarView retains its children during a non-adjacent tap animation.
    // Selection must still deactivate the outgoing page immediately.
    return ScrollConfiguration(
      // Restrict input on the pager, while lists keep their own wheel,
      // scrollbar and drag behavior from the application.
      behavior: widget.scrollBehavior,
      child: ValueListenableBuilder(
        valueListenable: widget.selection,
        builder: (context, selected, _) {
          final active = selected == widget.channel;
          if (active && !_visited) {
            _visited = true;
            updateKeepAlive();
          }
          return WorkspaceActivity(
            active: active && WorkspaceActivity.isActive(context),
            child: ExcludeFocus(
              excluding: !active,
              child: IgnorePointer(
                ignoring: !active,
                child: _visited
                    ? widget.pageBuilder(context, widget.channel, active)
                    : const StateView.loading(),
              ),
            ),
          );
        },
      ),
    );
  }
}
