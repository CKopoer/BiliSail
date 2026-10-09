import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/presentation/workspace_activity.dart';
import 'app_network_image.dart';
import 'state_view.dart';
import 'tab_paging_motion.dart';

typedef RetainedTabPageBuilder<T extends Object> = Widget Function(
  BuildContext context,
  T tab,
  bool active,
);

/// Presentation-only paging progress shared with a tab strip outside the pager.
final class TabPagingProgress extends ChangeNotifier
    implements ValueListenable<double> {
  TabPagingProgress(double initialIndex) : _value = initialIndex;

  double _value;
  Object? _owner;
  bool _disposed = false;

  @override
  double get value => _value;
  bool get isAttached => _owner != null;

  void _attach(Object owner, double value) {
    _owner = owner;
    _value = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && identical(_owner, owner)) notifyListeners();
    });
  }

  void _publish(Object owner, double value) {
    if (_disposed || !identical(_owner, owner) || _value == value) return;
    _value = value;
    notifyListeners();
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _owner == null) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class TabPagingScope extends InheritedWidget {
  const TabPagingScope({
    super.key,
    required this.progress,
    required super.child,
  });

  final TabPagingProgress progress;

  static TabPagingProgress? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabPagingScope>()?.progress;

  @override
  bool updateShouldNotify(TabPagingScope oldWidget) =>
      progress != oldWidget.progress;
}

/// Touch paging retains visited pages and commits selection after settling.
final class RetainedTabView<T extends Object> extends StatefulWidget {
  const RetainedTabView({
    super.key,
    required this.value,
    required this.tabs,
    required this.onChanged,
    required this.pageBuilder,
    this.viewKey,
    this.progress,
  });

  final List<T> tabs;
  final T value;
  final Key? viewKey;
  final TabPagingProgress? progress;
  final ValueChanged<T> onChanged;
  final RetainedTabPageBuilder<T> pageBuilder;

  @override
  State<RetainedTabView<T>> createState() => _RetainedTabViewState<T>();
}

final class _RetainedTabViewState<T extends Object>
    extends State<RetainedTabView<T>>
    with TickerProviderStateMixin {
  TabController? _tabs;
  TabPagingProgress? _progress;
  bool _publishPending = false;
  late final _selection = ValueNotifier<T>(widget.value);
  bool _dragging = false;
  bool _active = true;
  int _generation = 0;

  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : TabPagingMotion.duration;

  void _replaceController() {
    _generation++;
    _dragging = false;
    _tabs?.animation?.removeListener(_publishProgress);
    _tabs?.dispose();
    _tabs = TabController(
      length: widget.tabs.length,
      initialIndex: widget.tabs.indexOf(widget.value),
      animationDuration: _duration,
      vsync: this,
    );
    _tabs?.animation?.addListener(_publishProgress);
    _progress?._attach(this, _tabs?.animation?.value ?? 0);
  }

  void _publishProgress() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_publishPending) return;
      _publishPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _publishPending = false;
        if (mounted) _progress?._publish(this, _tabs?.animation?.value ?? 0);
      });
    } else {
      _progress?._publish(this, _tabs?.animation?.value ?? 0);
    }
  }

  bool _connectProgress() {
    final progress = widget.progress ?? TabPagingScope.maybeOf(context);
    if (identical(progress, _progress)) return false;
    _progress?._detach(this);
    _progress = progress;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final progressChanged = _connectProgress();
    final active = WorkspaceActivity.isActive(context);
    if (_tabs == null ||
        _tabs?.animationDuration != _duration ||
        (_active && !active)) {
      _replaceController();
    } else if (progressChanged) {
      _progress?._attach(this, _tabs?.animation?.value ?? 0);
    }
    _active = active;
  }

  @override
  void didUpdateWidget(RetainedTabView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_connectProgress()) {
      _progress?._attach(this, _tabs?.animation?.value ?? 0);
    }
    if (!listEquals(oldWidget.tabs, widget.tabs)) {
      _selection.value = widget.value;
      _replaceController();
    } else if (oldWidget.value != widget.value) {
      _generation++;
      _selection.value = widget.value;
      if (_dragging) {
        _replaceController();
      } else {
        _tabs?.animateTo(widget.tabs.indexOf(widget.value));
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
            index != widget.tabs.indexOf(widget.value)) {
          widget.onChanged(widget.tabs[index]);
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
          key: widget.viewKey,
          controller: _tabs,
          physics: _active
              ? TabPagingMotion.physics
              : const NeverScrollableScrollPhysics(),
          dragStartBehavior: DragStartBehavior.down,
          children: [
            for (final tab in widget.tabs)
              _RetainedTabPage<T>(
                key: ValueKey(tab),
                tab: tab,
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
    _progress?._detach(this);
    _tabs?.animation?.removeListener(_publishProgress);
    _tabs?.dispose();
    _selection.dispose();
    super.dispose();
  }
}

final class _RetainedTabPage<T extends Object> extends StatefulWidget {
  const _RetainedTabPage({
    super.key,
    required this.tab,
    required this.selection,
    required this.pageBuilder,
    required this.scrollBehavior,
  });

  final T tab;
  final ValueNotifier<T> selection;
  final RetainedTabPageBuilder<T> pageBuilder;
  final ScrollBehavior scrollBehavior;

  @override
  State<_RetainedTabPage<T>> createState() => _RetainedTabPageState<T>();
}

final class _RetainedTabPageState<T extends Object>
    extends State<_RetainedTabPage<T>>
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
          final active = selected == widget.tab;
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
                child: AppImagePageViewport(
                  child: _visited
                      ? widget.pageBuilder(context, widget.tab, active)
                      : const StateView.loading(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
