import '../../core/presentation/motion_preferences.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../core/presentation/workspace_activity.dart';
import 'app_network_image.dart';
import 'state_view.dart';
import 'tab_paging_motion.dart';

typedef RetainedTabPageBuilder<T extends Object> = Widget Function(
  BuildContext context,
  T tab,
  bool active,
);

typedef TabSelectionAnimation<T extends Object> = bool Function(T from, T to);

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
    this.preloadPages = false,
    this.swipeEnabled = true,
    this.animateSelection,
  });

  final List<T> tabs;
  final T value;
  final Key? viewKey;
  final TabPagingProgress? progress;
  // Ready local data can appear on the first drag without a loading placeholder.
  final bool preloadPages;
  final bool swipeEnabled;

  /// Controls routed selections; touch drags keep their paging motion.
  final TabSelectionAnimation<T>? animateSelection;
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
  final _pagerStorage = PageStorageBucket();
  bool _publishPending = false;
  late final _selection = ValueNotifier<T>(widget.value);
  bool _dragging = false;
  bool _active = true;
  int _generation = 0;
  (RetainedTabView<T>, ScrollBehavior, PageStorageBucket, Object)?
  _pagesConfiguration;
  List<Widget> _pages = const [];

  Duration get _duration =>
      shouldReduceMotion(context) ? Duration.zero : TabPagingMotion.duration;

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
    final deactivated = _active && !active;
    final interruptMotion =
        deactivated &&
        (_dragging ||
            _tabs?.indexIsChanging == true ||
            (_tabs?.offset ?? 0).abs() > precisionErrorTolerance);
    if (_tabs == null ||
        _tabs?.animationDuration != _duration ||
        interruptMotion) {
      _replaceController();
    } else {
      // Keep idle retained pagers intact on primary navigation. Only unfinished
      // motion needs a new controller to restore the routed page.
      if (deactivated) _generation++;
      if (progressChanged) {
        _progress?._attach(this, _tabs?.animation?.value ?? 0);
      }
    }
    _active = active;
  }

  @override
  void didUpdateWidget(RetainedTabView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.swipeEnabled && !widget.swipeEnabled) {
      _replaceController();
    }
    if (_connectProgress()) {
      _progress?._attach(this, _tabs?.animation?.value ?? 0);
    }
    if (!listEquals(oldWidget.tabs, widget.tabs)) {
      _selection.value = widget.value;
      _replaceController();
    } else if (oldWidget.value != widget.value) {
      _generation++;
      _selection.value = widget.value;
      if (_dragging ||
          widget.animateSelection?.call(oldWidget.value, widget.value) ==
              false) {
        // TabBarView uses the controller's animationDuration for its own page
        // motion, even when animateTo receives Duration.zero. Replacing only
        // the controller jumps the retained pager and cancels ongoing motion.
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
      _generation++;
      _dragging = true;
    }
    // Wheel input has no dragDetails. User direction distinguishes it from
    // routed tab animations and lets it commit only after page snapping.
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle &&
        _tabs?.indexIsChanging != true &&
        !_dragging) {
      _generation++;
      _dragging = true;
    }
    if (notification is ScrollEndNotification && _dragging) {
      final metrics = notification.metrics;
      if (metrics is! PageMetrics) return false;
      final page = metrics.page;
      // A new pointer holds the unfinished snap and emits ScrollEnd too. Keep
      // that swipe pending until a page boundary is reached; committing here
      // would let the route update reset the next drag's controller.
      if (page == null ||
          (page - page.round()).abs() > precisionErrorTolerance) {
        return false;
      }
      _dragging = false;
      final generation = _generation;
      final index = _tabs?.index;
      // Scroll notifications can arrive during layout. Commit only the settled
      // user selection, and let cancellation or an external route supersede it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.swipeEnabled &&
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
  Widget build(BuildContext context) {
    final pageStorage = PageStorage.maybeOf(context) ?? _pagerStorage;
    // A nested PageStorage stops key collection. Carry the outer page's keys
    // into the list scope so different workspace pages cannot share offsets.
    Object storageScope = (widget.key, widget.viewKey);
    context.visitAncestorElements((element) {
      if (element.widget.key case final PageStorageKey<Object?> key) {
        storageScope = (storageScope, key);
      }
      return element.widget is! PageStorage;
    });
    final scrollBehavior = ScrollConfiguration.of(context);
    final configuration = (widget, scrollBehavior, pageStorage, storageScope);
    if (_pagesConfiguration != configuration) {
      _pagesConfiguration = configuration;
      // Activity changes only gate input and visibility. Reuse the children so
      // returning to another primary section does not rebuild hidden content.
      // Include the whole widget: an unchanged builder tear-off can still read
      // new configuration from its parent's State on a normal parent update.
      _pages = [
        for (final tab in widget.tabs)
          PageStorage(
            key: PageStorageKey((storageScope, tab)),
            bucket: pageStorage,
            child: _RetainedTabPage<T>(
              key: ValueKey(tab),
              tab: tab,
              selection: _selection,
              pageBuilder: widget.pageBuilder,
              preload: widget.preloadPages,
              scrollBehavior: scrollBehavior,
            ),
          ),
      ];
    }
    return IgnorePointer(
      ignoring: !_active,
      child: Listener(
        onPointerCancel: _cancelPointer,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: scrollBehavior.copyWith(
              dragDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
                PointerDeviceKind.trackpad,
              },
              scrollbars: false,
            ),
            // Selection owns the page position. A remounted pager must not restore
            // another media item's offset from the workspace PageStorage bucket.
            child: PageStorage(
              bucket: _pagerStorage,
              child: TabBarView(
                key: widget.viewKey,
                controller: _tabs,
                // Changing the physics type recreates ScrollPosition, which
                // invalidates every retained list's scroll dependencies. Hidden
                // pagers reject input above without replacing their position.
                physics: widget.swipeEnabled
                    ? TabPagingMotion.physics
                    : const NeverScrollableScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                children: _pages,
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    required this.preload,
    required this.scrollBehavior,
  });

  final T tab;
  final ValueNotifier<T> selection;
  final RetainedTabPageBuilder<T> pageBuilder;
  final bool preload;
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
          if ((active || widget.preload) && !_visited) {
            _visited = true;
            updateKeepAlive();
          }
          return _RetainedTabActivity(
            selected: active,
            child: ExcludeFocus(
              excluding: !active,
              child: IgnorePointer(
                ignoring: !active,
                child: AppImagePageViewport(
                  child: _visited
                      ? widget.pageBuilder(context, widget.tab, active)
                      // Unvisited neighbors may be laid out during a partial
                      // swipe. Keep their placeholder from animating forever;
                      // active pages are marked visited before this branch.
                      : const TickerMode(
                          enabled: false,
                          child: StateView.loading(),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Keep the inherited visibility subscription outside the content factory.
/// Descendants still receive activity/provider updates while hidden.
class _RetainedTabActivity extends StatelessWidget {
  const _RetainedTabActivity({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => WorkspaceActivity(
    active: selected && WorkspaceActivity.isActive(context),
    previewing:
        selected &&
        WorkspaceActivity.isVisible(context) &&
        !WorkspaceActivity.isActive(context),
    child: child,
  );
}
