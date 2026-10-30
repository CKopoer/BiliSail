import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/platform/window_caption.dart';
import '../core/platform/window_size_policy.dart';
import '../features/feed/domain/home_channel.dart';
import '../features/search/presentation/search_category_bar.dart';
import '../core/presentation/workspace_activity.dart';
import '../core/presentation/page_back_scope.dart';
import '../core/presentation/predictive_back_region.dart';
import '../core/presentation/trackpad_back_region.dart';
import 'workspace_tabs.dart';
import 'workspace_navigation.dart';
import 'workspace_back_presentation.dart';
import 'platform_defaults.dart';
import '../core/input/input_stroke.dart';
import '../core/input/shortcut_dispatcher.dart';
import '../core/presentation/input_scope.dart';
import 'shortcut_coordinator.dart';
import '../features/settings/domain/shortcut_settings.dart';
import '../features/settings/domain/settings_category.dart';
import '../features/settings/domain/app_settings.dart';
import '../shared/ui/smooth_scroll_behavior.dart';
import '../shared/ui/bili_icons.dart';
import '../shared/ui/shortcut_hint.dart';
import '../shared/ui/app_notice.dart';
import '../shared/ui/playback_navigation.dart';
import '../shared/ui/app_dialog.dart';
import '../shared/ui/paging_tab_strip.dart';
import '../shared/ui/page_tab_style.dart';
import '../shared/ui/retained_tab_view.dart';
import '../shared/ui/scroll_collapsing_header.dart';

typedef WorkspacePageBuilder = Widget Function(
  BuildContext context,
  WorkspaceTab tab,
);
typedef WorkspacePageScopeBuilder = Widget Function(
  BuildContext context,
  WorkspaceTab tab,
  Widget child,
);
typedef DragRegionBuilder = Widget Function(BuildContext context, Widget child);
typedef WorkspaceWindowBuilder = Widget Function(
  BuildContext context, {
  required Widget child,
  required Widget? playback,
  required bool keepPlaybackMounted,
  required Object? activationToken,
  required VoidCallback onClose,
  required VoidCallback onBack,
  required VoidCallback onHome,
  required ValueChanged<Object> onError,
});

/// A visible browser must not take playback ownership from its sibling window.
class WorkspacePlaybackSelection extends InheritedWidget {
  const WorkspacePlaybackSelection({
    super.key,
    required this.tabId,
    required super.child,
  });
  final String? tabId;
  static String? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspacePlaybackSelection>()
      ?.tabId;
  @override
  bool updateShouldNotify(WorkspacePlaybackSelection oldWidget) =>
      oldWidget.tabId != tabId;
}

/// Navigation within an existing playback page preserves the selected tab.
final class WorkspacePageNavigation extends InheritedWidget {
  const WorkspacePageNavigation({
    super.key,
    required this.navigate,
    required super.child,
  });

  final ValueChanged<Uri> navigate;

  static WorkspacePageNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspacePageNavigation>();

  @override
  bool updateShouldNotify(WorkspacePageNavigation oldWidget) =>
      navigate != oldWidget.navigate;
}

/// Builds shell navigation inside a page's own provider scope.
final class WorkspacePageHeader extends InheritedWidget {
  const WorkspacePageHeader({
    super.key,
    required this.builder,
    required super.child,
  });

  final WidgetBuilder builder;

  static Widget wrap(BuildContext context, Widget page) {
    final header = context
        .dependOnInheritedWidgetOfExactType<WorkspacePageHeader>();
    return header == null
        ? page
        : Column(
            children: [
              header.builder(context),
              Expanded(child: page),
            ],
          );
  }

  @override
  bool updateShouldNotify(WorkspacePageHeader oldWidget) =>
      builder != oldWidget.builder;
}

final class BiliAppShell extends StatefulWidget {
  const BiliAppShell({
    super.key,
    required this.location,
    required this.child,
    this.accountBuilder,
    this.pageBuilder,
    this.pageScopeBuilder,
    this.windowControlsBuilder,
    this.dragRegionBuilder,
    this.shortcuts = const ShortcutSettings.defaults(),
    this.navigationMode,
    this.sidebarStyle = SidebarStyle.automatic,
    this.navigationBarMode = NavigationBarMode.automatic,
    this.sidebarCollapsed,
    this.onSidebarCollapsedChanged,
    this.accountIdentity,
    this.playbackWindowBuilder,
    this.onActivateBrowser,
    this.onExitRequested,
  });
  final ShortcutSettings shortcuts;
  final WorkspaceNavigationMode? navigationMode;
  final SidebarStyle sidebarStyle;
  final NavigationBarMode navigationBarMode;
  final bool? sidebarCollapsed;
  final ValueChanged<bool>? onSidebarCollapsedChanged;
  final Object? accountIdentity;
  final WorkspaceWindowBuilder? playbackWindowBuilder;
  final VoidCallback? onActivateBrowser;
  final Future<void> Function()? onExitRequested;
  final String location;
  final Widget child;
  final WidgetBuilder? accountBuilder;
  final WorkspacePageBuilder? pageBuilder;
  final WorkspacePageScopeBuilder? pageScopeBuilder;
  final WidgetBuilder? windowControlsBuilder;
  final DragRegionBuilder? dragRegionBuilder;
  @override
  State<BiliAppShell> createState() => _BiliAppShellState();
}

final class _BiliAppShellState extends State<BiliAppShell>
    with WidgetsBindingObserver {
  static const _bottomNavigationHeight = 52.0;
  static const _bottomNavigationIconSize = 16.0;
  static const _bottomNavigationLabelStyle = TextStyle(
    fontSize: 11,
    height: 1.2,
  );

  final _workspace = WorkspaceTabs();
  final _searchControllers = <String, TextEditingController>{};
  final _tabKeys = <(String, String, String), GlobalKey>{};
  final _pageKeys = <String, GlobalKey>{};
  final _viewStorage = <(String, String), PageStorageBucket>{};
  final _searchDrafts = <String, String>{};
  final _pageBack = <String, PageBackController>{};
  final _pagingProgress = <(String, bool), TabPagingProgress>{};
  final _lastChannels = <WorkspaceSection, HomeChannel>{};
  final _lastSections = <HomeChannel, String>{};
  SettingsCategory _lastSettingsCategory = SettingsCategory.appearance;
  bool _windowFailed = false;
  int _windowActivation = 0;
  bool _exitConfirmationOpen = false;
  bool _localSidebarCollapsed = false;
  bool get _sidebarCollapsed =>
      widget.sidebarCollapsed ?? _localSidebarCollapsed;
  WorkspaceTab? _gestureSource, _gestureDestination;

  WorkspaceTab _frameTab(BuildContext context) =>
      WorkspaceFrameTab.maybeOf(context) ?? _displayTab;

  bool _frameShowsBack(BuildContext context) {
    final tab = _frameTab(context);
    return (_dualTabs || _singlePage) &&
        _canGoBack &&
        (!(tab.pinned && tab.isRoot) ||
            (tab.isMessages && _canReturnFromMessages) ||
            (_pageBack[tab.id]?.canGoBack ?? false));
  }

  bool get _android => Theme.of(context).platform == TargetPlatform.android;
  bool get _mobile => WindowSizePolicy.isMobile(Theme.of(context).platform);
  bool _compactLayout(double width) => WindowSizePolicy.compactLayout(
    mobile: _mobile,
    displaySize: WindowSizePolicy.displaySize(View.of(context)),
    availableWidth: width,
  );
  bool get _compactChannels => _compactLayout(
    MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).horizontal,
  );
  bool _usesBottomNavigation(double width) {
    final compact = _compactLayout(width);
    if (_mobile && compact) return true;
    return switch (widget.navigationBarMode) {
      NavigationBarMode.automatic => compact,
      NavigationBarMode.bottom => true,
      NavigationBarMode.sidebar => false,
    };
  }

  bool get _canReturnFromMessages =>
      _android && _workspace.canReturnFromMessages;

  bool get _desktopDual =>
      _dualTabs && widget.playbackWindowBuilder != null && !_windowFailed;
  WorkspaceTab get _displayTab => _desktopDual
      ? _workspace.tabs.firstWhere((tab) => tab.id == _workspace.browseId)
      : _workspace.active;

  PageBackController _backFor(String id) => _pageBack.putIfAbsent(
    id,
    () => PageBackController()..addListener(_pageBackChanged),
  );

  void _pageBackChanged() {
    if (mounted) setState(() {});
  }

  bool get _canGoBack =>
      (_pageBack[_displayTab.id]?.canGoBack ?? false) ||
      _canReturnFromMessages ||
      (_desktopDual ? _workspace.canGoBackBrowsing : _workspace.canGoBack);

  bool _goBackWithinPage() => _pageBack[_displayTab.id]?.goBack() ?? false;

  bool get _canTrackpadBack => !_dualTabs && !_singlePage
      ? (_pageBack[_displayTab.id]?.canGoBack ?? false) || !_displayTab.pinned
      : _canGoBack;

  void _closeCurrentTabOrBackWithinPage() {
    if (!_goBackWithinPage()) _closeTab(_workspace.activeId);
  }

  void _trackpadBack() {
    // Separate tabs close just like the close command; visit history can
    // otherwise select an old player while retaining the page being left.
    if (!_dualTabs && !_singlePage) {
      _closeCurrentTabOrBackWithinPage();
    } else {
      _goBack();
    }
  }

  TabPagingProgress _pagingFor(WorkspaceTab tab) {
    final settings = tab.location.path == '/settings';
    final channels = channelsForSection(
      sectionForLocation(tab.location, compact: _compactChannels),
      compact: _compactChannels,
    );
    final index = settings
        ? SettingsCategory.fromName(tab.location.queryParameters['section'])
              .index
        : channels
              .indexWhere(
                (channel) =>
                    channel.name ==
                    (tab.location.queryParameters['channel'] == 'ranking'
                        ? 'popular'
                        : tab.location.queryParameters['channel'] ??
                              'recommended'),
              )
              .clamp(0, channels.isEmpty ? 0 : channels.length - 1);
    return _pagingProgress.putIfAbsent((
      tab.id,
      settings,
    ), () => TabPagingProgress(index.toDouble()));
  }

  bool get _dualTabs =>
      (widget.navigationMode ?? defaultWorkspaceNavigationMode) ==
      WorkspaceNavigationMode.dualTabs;

  bool get _singlePage =>
      (widget.navigationMode ?? defaultWorkspaceNavigationMode) ==
      WorkspaceNavigationMode.singlePage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspace.setDualMode(_dualTabs);
    _workspace.setSingleMode(_singlePage);
    _workspace.acceptRoute(Uri.parse(widget.location));
    _rememberSection(_displayTab.location);
    _restoreSearch();
  }

  @override
  void didUpdateWidget(covariant BiliAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.accountIdentity != oldWidget.accountIdentity) {
      _tabKeys.clear();
      _viewStorage.clear();
      _workspace.clearPlaybackHistory();
    }
    if (widget.navigationMode != oldWidget.navigationMode) {
      _windowFailed = false;
    }
    _workspace.setDualMode(_dualTabs);
    _workspace.setSingleMode(_singlePage);
    if (widget.navigationMode != oldWidget.navigationMode) _revealActiveTab();
    if (widget.location != oldWidget.location) {
      if (!_workspace.acceptRoute(Uri.parse(widget.location))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showAppNotice(context, '最多打开 16 个标签页，请先关闭不用的标签');
          context.go(_workspace.active.route.toString());
        });
        return;
      }
      _prunePages();
      _rememberSection(_displayTab.location, compact: _compactChannels);
      _restoreSearch();
      _revealActiveTab();
      if (_workspace.active.isPlayback) _windowActivation++;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rememberSection(_displayTab.location, compact: _compactChannels);
    _revealActiveTab();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (!_desktopDual ||
        event.state != ViewFocusState.focused ||
        event.viewId != View.maybeOf(context)?.viewId ||
        _workspace.activeId == _workspace.browseId) {
      return;
    }
    // The browser remains visible while playback owns another view. Restore
    // its route on refocus so opening the same video is a new navigation and
    // raises the existing playback window, including clicks through the OS.
    _selectTab(_workspace.browseId);
  }

  void _prunePages() {
    final liveIds = _workspace.tabs.map((tab) => tab.id).toSet();
    _tabKeys.removeWhere(
      (key, _) => !liveIds.contains(key.$1) || !liveIds.contains(key.$3),
    );
    _pageKeys.removeWhere((id, _) => !liveIds.contains(id));
    _searchDrafts.removeWhere((id, _) => !liveIds.contains(id));
    _searchControllers.removeWhere((id, controller) {
      if (liveIds.contains(id)) return false;
      controller.dispose();
      return true;
    });
    _pageBack.removeWhere((id, controller) {
      if (liveIds.contains(id)) return false;
      controller.dispose();
      return true;
    });
    _pagingProgress.removeWhere((key, progress) {
      if (liveIds.contains(key.$1)) return false;
      progress.dispose();
      return true;
    });
  }

  TextEditingController _searchFor(WorkspaceTab tab) =>
      _searchControllers.putIfAbsent(tab.id, () {
        final controller = TextEditingController(
          text:
              _searchDrafts[tab.id] ?? tab.location.queryParameters['q'] ?? '',
        );
        controller.addListener(() => _searchDrafts[tab.id] = controller.text);
        return controller;
      });
  void _restoreSearch() {
    _searchFor(_displayTab).text =
        _searchDrafts[_displayTab.id] ??
        _displayTab.location.queryParameters['q'] ??
        '';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    for (final controller in _pageBack.values) {
      controller.dispose();
    }
    for (final progress in _pagingProgress.values) {
      progress.dispose();
    }
    super.dispose();
  }

  void _revealActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final frame = _viewKey(_displayTab);
      final tabContext =
          _tabKeys[(frame.$1, frame.$2, _workspace.activeId)]?.currentContext;
      if (tabContext != null) {
        Scrollable.ensureVisible(tabContext, alignment: 0.5);
      }
    });
  }

  void _commitWorkspace() {
    _restoreSearch();
    context.go(_workspace.active.route.toString());
    _revealActiveTab();
  }

  void _newTab() {
    if (_dualTabs || _singlePage) return;
    if (_workspace.tabs.length >= WorkspaceTabs.maximumTabs) {
      showAppNotice(context, '最多打开 16 个标签页，请先关闭不用的标签');
      return;
    }
    setState(_workspace.addBrowseTab);
    _commitWorkspace();
  }

  void _selectTab(String id) {
    setState(() => _workspace.select(id));
    _commitWorkspace();
  }

  void _returnToPlayback() {
    final playback = _workspace.latestPlayback;
    if (playback == null) return;
    if (_desktopDual && _workspace.activeId == playback.id) {
      setState(() => _windowActivation++);
    } else {
      _selectTab(playback.id);
    }
  }

  void _updatePageLocation(WorkspaceTab tab, Uri location) {
    if (!mounted ||
        !_workspace.updateLocation(
          tab.id,
          location,
          expectedLocation: tab.location,
        )) {
      return;
    }
    setState(() {});
    if (tab.id == _workspace.activeId) _commitWorkspace();
  }

  void _closeTab(String id) {
    final wasActive = id == _workspace.activeId;
    if (!_workspace.close(id)) return;
    _tabKeys.removeWhere((key, _) => key.$1 == id || key.$3 == id);
    _searchDrafts.remove(id);
    _prunePages();
    setState(() {});
    if (wasActive) _commitWorkspace();
  }

  bool _goBack() {
    if (_goBackWithinPage()) return true;
    if (!(_canReturnFromMessages
        ? _workspace.returnFromMessages()
        : _desktopDual
        ? _workspace.goBackBrowsing()
        : _workspace.goBack())) {
      return false;
    }
    _prunePages();
    setState(() {});
    _commitWorkspace();
    return true;
  }

  Future<void> _confirmAndroidExit() async {
    if (_exitConfirmationOpen) return;
    _exitConfirmationOpen = true;
    final location = widget.location;
    try {
      final exit = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('退出哔帆？'),
          content: const Text('确定要退出应用吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (exit == true &&
          mounted &&
          widget.location == location &&
          !_canGoBack) {
        // Android's SystemNavigator.pop finishes the Activity without a
        // cancelable desktop exit notification. Drain shared resources first.
        await widget.onExitRequested?.call();
        await SystemNavigator.pop();
      }
    } finally {
      _exitConfirmationOpen = false;
    }
  }

  void _closePlaybackWindow() {
    final id = _workspace.playbackId;
    if (id == null) return;
    _closeTab(id);
    widget.onActivateBrowser?.call();
  }

  void _playbackWindowBack() {
    final id = _workspace.playbackId;
    if (id == null) return;
    if (_pageBack[id]?.goBack() ?? false) return;
    _workspace.select(id);
    if (!_workspace.goBack()) return;
    _prunePages();
    setState(() {});
    _commitWorkspace();
    if (!_workspace.active.isPlayback) widget.onActivateBrowser?.call();
  }

  void _playbackWindowError(Object error) {
    if (!mounted || _windowFailed) return;
    setState(() => _windowFailed = true);
    showAppNotice(context, '独立播放窗口未能打开，已保留当前播放页面，请重试或切换导航模式');
  }

  void _playbackHome() {
    _workspace.returnFromPlayback();
    _prunePages();
    setState(() {});
    _commitWorkspace();
    if (_desktopDual) widget.onActivateBrowser?.call();
  }

  void _cycleTabs({bool backwards = false}) {
    if (_singlePage) return;
    if (_desktopDual) {
      setState(() => _windowActivation++);
      return;
    }
    setState(() => _workspace.cycle(backwards: backwards));
    _commitWorkspace();
  }

  void _search(String input) {
    final query = input.trim();
    if (query.isEmpty) return;
    context.go(Uri(path: '/search', queryParameters: {'q': query}).toString());
  }

  void _selectChannel(HomeChannel channel) {
    _lastChannels[sectionForLocation(
          Uri(path: '/', queryParameters: {'channel': channel.name}),
          compact: _compactChannels,
        )] =
        channel;
    final tab = _displayTab.isBrowse ? _displayTab : _workspace.tabs.first;
    context.go(
      Uri(
        path: '/',
        queryParameters: {
          'channel': channel.name,
          'tab': tab.id,
          'section': ?_lastSections[channel],
        },
      ).toString(),
    );
  }

  void _rememberSection(Uri location, {bool compact = false}) {
    if (location.path == '/settings') {
      _lastSettingsCategory = SettingsCategory.fromName(
        location.queryParameters['section'],
      );
      return;
    }
    if (location.path != '/') return;
    final requestedChannel =
        HomeChannel.values
            .where((value) => value.name == location.queryParameters['channel'])
            .firstOrNull ??
        HomeChannel.recommended;
    final channel = requestedChannel == HomeChannel.ranking
        ? HomeChannel.popular
        : requestedChannel;
    _lastChannels[sectionForLocation(location, compact: compact)] = channel;
    final section = location.queryParameters['section'];
    if (section != null && channel.sections.contains(section)) {
      _lastSections[channel] = section;
    } else if (channel == HomeChannel.live) {
      _lastSections[channel] = channel.sections.first;
    } else if (requestedChannel == HomeChannel.ranking) {
      _lastSections[channel] = '排行榜';
    }
  }

  void _selectLiveSection(String section) {
    _lastSections[HomeChannel.live] = section;
    final tab = _displayTab.isBrowse ? _displayTab : _workspace.tabs.first;
    context.go(
      Uri(
        path: '/',
        queryParameters: {
          'channel': HomeChannel.live.name,
          'section': section,
          'tab': tab.id,
        },
      ).toString(),
    );
  }

  CommandOutcome _workspaceCommand(Object command, InputStroke stroke) {
    if (stroke.phase == InputPhase.up) return CommandOutcome.noOp;
    InputScope.of<Object>(context)?.dispatcher.beforeNavigation();
    switch (command) {
      case ShortcutAction.newTab:
        _newTab();
      case ShortcutAction.closeTab:
        if (_desktopDual || _singlePage) {
          _goBack();
        } else {
          _closeCurrentTabOrBackWithinPage();
        }
      case ShortcutAction.nextTab:
        _cycleTabs();
      case ShortcutAction.previousTab:
        _cycleTabs(backwards: true);
    }
    return CommandOutcome.completed;
  }

  @override
  Widget build(BuildContext context) {
    final dispatcher = InputScope.of<Object>(context)?.dispatcher;
    if (dispatcher is ShortcutCoordinator) {
      dispatcher.configure(widget.shortcuts);
    }
    // Keyboard resizing changes geometry, not the cached pages' configuration.
    final pages = Builder(builder: _pages);
    final main = CommandTargetScope<Object>(
      scope: CommandScope.workspace,
      commands: {
        for (final command in <Object>[
          ShortcutAction.newTab,
          ShortcutAction.closeTab,
          ShortcutAction.nextTab,
          ShortcutAction.previousTab,
        ])
          command: (stroke) => _workspaceCommand(command, stroke),
      },
      child: PopScope<Object?>(
        canPop: !_android && !_canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_goBack() && _android) _confirmAndroidExit();
        },
        child: Focus(
          autofocus: true,
          child: (_android
              ? pages
              : _workspaceFrame(context, _displayTab, pages)),
        ),
      ),
    );
    final windowBuilder = widget.playbackWindowBuilder;
    final presented = TrackpadBackRegion(
      enabled: _canTrackpadBack,
      identity: (
        _backIdentity(_displayTab),
        _desktopDual
            ? _workspace.browseId
            : _workspace.backDestination()?.location,
        _pageBack[_displayTab.id]?.canGoBack ?? false,
      ),
      onBack: _trackpadBack,
      child: _withBackPreview(context, main),
    );
    if (windowBuilder == null) return presented;
    final playback = _desktopDual
        ? _workspace.tabs
              .where((tab) => tab.id == _workspace.playbackId)
              .firstOrNull
        : null;
    return windowBuilder(
      context,
      child: presented,
      keepPlaybackMounted:
          playback != null && _pageKeys[playback.id]?.currentContext != null,
      playback: playback == null
          ? null
          : TrackpadBackRegion(
              enabled: true,
              identity: (
                _backIdentity(playback),
                _pageBack[playback.id]?.canGoBack ?? false,
              ),
              onBack: _playbackWindowBack,
              child: _page(context, playback, active: true),
            ),
      activationToken: _windowActivation,
      onClose: _closePlaybackWindow,
      onBack: _playbackWindowBack,
      onHome: _playbackHome,
      onError: _playbackWindowError,
    );
  }

  Widget _workspaceFrame(
    BuildContext context,
    WorkspaceTab tab,
    Widget pages,
  ) => WorkspaceFrameTab(
    tab: tab,
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: _android || _compactChannels
            ? Theme.of(context).colorScheme.surface
            : null,
        floatingActionButton:
            _usesBottomNavigation(
                  MediaQuery.sizeOf(context).width -
                      MediaQuery.paddingOf(context).horizontal,
                ) &&
                _dualTabs &&
                !_desktopDual &&
                !tab.isPlayback &&
                _workspace.playbackId != null &&
                !(_gestureDestination?.id == tab.id &&
                    (_gestureSource?.isPlayback ?? false) &&
                    _workspace.playbackHistory.isEmpty)
            ? FloatingActionButton.small(
                tooltip: '返回播放',
                onPressed: () => _selectTab(_workspace.playbackId!),
                child: const Icon(Icons.play_arrow_rounded),
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = _usesBottomNavigation(constraints.maxWidth);
              final extended = switch (widget.sidebarStyle) {
                SidebarStyle.automatic => constraints.maxWidth >= 1600,
                SidebarStyle.expanded => true,
                SidebarStyle.compact => false,
              };
              final playback = _workspace.latestPlayback;
              final captionTools = workspaceHeaderVisibleForPlatform(
                Theme.of(context).platform,
              );
              final navigationTools = compact
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sidebarToggle(context, caption: captionTools),
                        if (!tab.isPlayback)
                          _returnToPlaybackButton(
                            context,
                            enabled: playback != null,
                            caption: captionTools,
                          ),
                      ],
                    );
              final colors = Theme.of(context).colorScheme;
              return Column(
                children: [
                  if (_dualTabs || _singlePage) ...[
                    if (!_android && widget.windowControlsBuilder != null)
                      _dualWindowCaption(
                        context,
                        navigationTools: navigationTools,
                      )
                    else if (!_android && !_desktopDual && tab.isPlayback)
                      _playbackHeader(context, navigationTools: navigationTools)
                    else if (navigationTools != null)
                      SizedBox(
                        key: const ValueKey('workspace-sidebar-toolbar'),
                        height: captionTools ? desktopCaptionHeight : 40,
                        child: Row(children: [navigationTools]),
                      ),
                  ] else
                    _tabStrip(context, navigationTools: navigationTools),
                  Expanded(
                    key: const ValueKey('workspace-body'),
                    child: Row(
                      children: [
                        _sidebarRegion(
                          context,
                          compact: compact,
                          extended: extended,
                        ),
                        Expanded(
                          child: AnimatedPadding(
                            duration:
                                compact ||
                                    MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            curve: Curves.easeInOutCubic,
                            padding: compact
                                ? EdgeInsets.zero
                                : EdgeInsets.fromLTRB(
                                    _sidebarCollapsed ? 16 : 0,
                                    12,
                                    16,
                                    16,
                                  ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                compact ? 0 : 18,
                              ),
                              child: ColoredBox(
                                color: colors.surface,
                                // Switching a retained root restores dense image
                                // lists. Keep that content stationary while the
                                // bottom bar animates its selected destination.
                                child: RepaintBoundary(
                                  key: const ValueKey(
                                    'workspace-primary-content',
                                  ),
                                  child: ScrollHeaderRegion(
                                    enabled: compact,
                                    identity: (
                                      tab.id,
                                      sectionForLocation(
                                        tab.location,
                                        compact: _compactChannels,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        if (_frameShowsBack(context) &&
                                            widget.windowControlsBuilder ==
                                                null &&
                                            tab.isProfile)
                                          SizedBox(
                                            key: const ValueKey(
                                              'workspace-profile-back-header',
                                            ),
                                            height: 42,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: _backButton(),
                                            ),
                                          ),
                                        if (tab.location.path != '/search' &&
                                            !tab.isPlayback &&
                                            !tab.isProfile)
                                          LayoutBuilder(
                                            builder: (context, bounds) =>
                                                _navigationHeader(
                                                  context,
                                                  bounds,
                                                  _channelBar(
                                                    context,
                                                    compact: compact,
                                                  ),
                                                  compact: compact,
                                                ),
                                          ),
                                        Expanded(child: pages),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (compact && !tab.isPlayback && !tab.isProfile)
                    _animatedBottomNavigation(context),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _dualWindowCaption(BuildContext context, {Widget? navigationTools}) =>
      SizedBox(
        key: const ValueKey('dual-window-caption'),
        height: desktopCaptionHeight,
        child: Row(
          children: [
            ?navigationTools,
            if (_frameShowsBack(context)) _backButton(caption: true),
            if (!_android && _frameTab(context).isPlayback)
              _homeButton(caption: true),
            Expanded(
              child:
                  widget.dragRegionBuilder?.call(
                    context,
                    const Padding(
                      padding: EdgeInsets.only(left: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '哔帆',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: desktopCaptionTextStyle,
                        ),
                      ),
                    ),
                  ) ??
                  const SizedBox.expand(),
            ),
            widget.windowControlsBuilder!(context),
          ],
        ),
      );

  Widget _playbackHeader(BuildContext context, {Widget? navigationTools}) =>
      SizedBox(
        key: const ValueKey('workspace-playback-header'),
        height: 44,
        child: Row(
          children: [
            ?navigationTools,
            if (_singlePage)
              _backButton()
            else
              IconButton(
                tooltip: '返回上一视频',
                onPressed: _playbackWindowBack,
                icon: const Icon(Icons.arrow_back),
              ),
            _homeButton(),
            Expanded(
              child: Text(
                _workspace.active.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_singlePage)
              IconButton(
                tooltip: '关闭播放',
                onPressed: _closePlaybackWindow,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      );

  Object _backIdentity(WorkspaceTab tab) =>
      (widget.accountIdentity, widget.navigationMode, tab.id, tab.location);

  Widget _withBackPreview(BuildContext context, Widget child) {
    if (!_android || _desktopDual || widget.pageBuilder == null) return child;
    final destination = _workspace.backDestination(
      fromMessages: _canReturnFromMessages,
    );
    final supported =
        destination != null &&
        _viewsForTab(
          _workspace.tabs.firstWhere((tab) => tab.id == destination.id),
        ).any((view) => view.location == destination.location);
    return LayoutBuilder(
      builder: (context, constraints) => PredictiveBackRegion(
        // Match the frame's navigation layout after SafeArea consumes padding.
        enabled:
            supported &&
            _usesBottomNavigation(
              constraints.maxWidth - MediaQuery.paddingOf(context).horizontal,
            ) &&
            !(_pageBack[_displayTab.id]?.canGoBack ?? false),
        identity: _backIdentity(_displayTab),
        destinationIdentity: destination == null
            ? null
            : _backIdentity(destination),
        onStart: () {
          _gestureSource = _displayTab;
          _gestureDestination = destination;
          return destination != null;
        },
        onEnd: () {
          _gestureSource = null;
          _gestureDestination = null;
        },
        onBack: _goBack,
        builder: (context, progress, edge, previewing) =>
            WorkspaceBackPresentation(
              progress: progress,
              edge: edge,
              source: previewing ? _gestureSource : null,
              destination: previewing ? _gestureDestination : null,
              child: child,
            ),
      ),
    );
  }

  (String, String) _viewKey(WorkspaceTab tab) => (
    tab.id,
    !_android
        ? 'slot'
        : tab.isRoot
        ? 'root'
        : tab.location.path,
  );

  List<WorkspaceTab> _viewsForTab(WorkspaceTab tab) {
    if (!_android || tab.id != _workspace.playbackId) {
      return [tab];
    }
    final views = <WorkspaceTab>[tab];
    final paths = {tab.location.path};
    final budget = WorkspaceTabs.maximumTabs - _workspace.tabs.length;
    for (final location in _workspace.playbackHistory.reversed) {
      if (views.length > budget) break;
      if (paths.add(location.path)) {
        views.add(WorkspaceTab(id: tab.id, location: location));
      }
    }
    return views.reversed.toList();
  }

  Widget _pages(BuildContext context) {
    final builder = widget.pageBuilder;
    if (builder == null) {
      return _android
          ? _workspaceFrame(
              context,
              _displayTab,
              PageBackScope(
                controller: _backFor(_workspace.activeId),
                child: widget.child,
              ),
            )
          : PageBackScope(
              controller: _backFor(_workspace.activeId),
              child: widget.child,
            );
    }
    final liveViews = {
      for (final tab in _workspace.tabs)
        for (final view in _viewsForTab(tab)) _viewKey(view),
    };
    _tabKeys.removeWhere((key, _) => !liveViews.contains((key.$1, key.$2)));
    _viewStorage.removeWhere((key, _) => !liveViews.contains(key));
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(child: widget.child),
        for (final tab in _workspace.tabs)
          if (!_desktopDual || tab.id != _workspace.playbackId)
            _page(context, tab, active: tab.id == _displayTab.id),
      ],
    );
  }

  Widget _page(BuildContext context, WorkspaceTab tab, {required bool active}) {
    final back = WorkspaceBackPresentation.maybeOf(context);
    final previewsTab = back?.destination?.id == tab.id;
    final content = Builder(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          for (final view in _viewsForTab(tab))
            _locationView(context, tab, view, active: active, back: back),
        ],
      ),
    );
    return Offstage(
      key: _pageKeys.putIfAbsent(tab.id, GlobalKey.new),
      offstage: !active && !previewsTab,
      child: FocusScope(
        canRequestFocus: active,
        skipTraversal: !active,
        child: WorkspaceActivity(
          active: active,
          previewing: previewsTab && !active,
          child: WorkspacePlaybackSelection(
            tabId: _desktopDual ? _workspace.playbackId : null,
            child:
                widget.pageScopeBuilder?.call(context, tab, content) ?? content,
          ),
        ),
      ),
    );
  }

  Widget _locationView(
    BuildContext context,
    WorkspaceTab tab,
    WorkspaceTab view, {
    required bool active,
    required WorkspaceBackPresentation? back,
  }) {
    final selected = _viewKey(tab) == _viewKey(view);
    final incoming = back?.matches(back.destination, view) ?? false;
    final outgoing = back?.matches(back.source, view) ?? false;
    final current = active && selected;
    final key = _viewKey(view);
    return Offstage(
      key: ValueKey(('workspace-view', key)),
      offstage: !current && !incoming,
      child: PredictiveBackPageTransition(
        progress: incoming || outgoing
            ? back!.progress
            : kAlwaysDismissedAnimation,
        edge: back?.edge ?? SwipeEdge.left,
        incoming: incoming,
        child: IgnorePointer(
          ignoring: !current,
          child: ExcludeSemantics(
            excluding: !current,
            child: FocusScope(
              canRequestFocus: current,
              skipTraversal: !current,
              child: WorkspaceActivity(
                active: current,
                previewing: incoming && !current,
                child: WorkspaceMediaPermission(
                  allowed: selected,
                  child: PageStorage(
                    bucket: _viewStorage.putIfAbsent(
                      key,
                      PageStorageBucket.new,
                    ),
                    child: WorkspacePageHeader(
                      builder: _searchHeader,
                      child: WorkspacePageNavigation(
                        navigate: (location) =>
                            _updatePageLocation(view, location),
                        child: TabPagingScope(
                          progress: _pagingFor(view),
                          child: PageBackScope(
                            controller: _backFor(tab.id),
                            child: Builder(
                              builder: (context) {
                                final page =
                                    widget.pageBuilder?.call(context, view) ??
                                    widget.child;
                                return PlaybackNavigation(
                                  onBack: _desktopDual
                                      ? _playbackWindowBack
                                      : () {
                                          _goBack();
                                        },
                                  onHome: _playbackHome,
                                  showInPlayer:
                                      _android && (_singlePage || _dualTabs),
                                  child: _android
                                      ? _workspaceFrame(context, view, page)
                                      : page,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectSection(WorkspaceSection section, {required bool compact}) {
    switch (section) {
      case WorkspaceSection.home:
        final channels = channelsForSection(section, compact: _compactChannels);
        final previous = _lastChannels[section];
        _selectChannel(
          previous != null && channels.contains(previous)
              ? previous
              : channels.first,
        );
      case WorkspaceSection.dynamic:
        _selectChannel(_lastChannels[section] ?? HomeChannel.dynamic);
      case WorkspaceSection.live:
        _selectChannel(HomeChannel.live);
      case WorkspaceSection.mine:
        context.go('/me');
      case WorkspaceSection.messages:
        context.go('/messages');
      case WorkspaceSection.downloads:
        context.go('/downloads');
      case WorkspaceSection.settings:
        context.go(
          Uri(
            path: '/settings',
            queryParameters: {'section': _lastSettingsCategory.name},
          ).toString(),
        );
    }
  }

  IconData _sectionIcon(WorkspaceSection section, {bool selected = false}) =>
      switch (section) {
        WorkspaceSection.home =>
          selected ? Icons.home_rounded : Icons.home_outlined,
        WorkspaceSection.dynamic => Icons.rss_feed_rounded,
        WorkspaceSection.live =>
          selected ? Icons.live_tv_rounded : Icons.live_tv_outlined,
        WorkspaceSection.mine =>
          selected ? Icons.person_rounded : Icons.person_outline_rounded,
        WorkspaceSection.messages => Icons.chat_bubble_outline_rounded,
        WorkspaceSection.downloads => Icons.file_download_outlined,
        WorkspaceSection.settings => Icons.tune_rounded,
      };

  Widget _sidebarToggle(BuildContext context, {bool caption = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: caption
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: IconButton(
        key: const ValueKey('workspace-sidebar-toggle'),
        tooltip: _sidebarCollapsed ? '展开侧栏' : '收起侧栏',
        style: caption
            ? desktopCaptionButtonStyle
            : IconButton.styleFrom(
                minimumSize: const Size(36, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: colors.onSurfaceVariant,
                backgroundColor: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: colors.outlineVariant),
                ),
              ),
        onPressed: () {
          final collapsed = !_sidebarCollapsed;
          if (widget.sidebarCollapsed == null) {
            setState(() => _localSidebarCollapsed = collapsed);
          }
          widget.onSidebarCollapsedChanged?.call(collapsed);
        },
        icon: AnimatedRotation(
          turns: _sidebarCollapsed ? .5 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeInOutCubic,
          child: Icon(Icons.menu_open_rounded, size: caption ? 18 : 20),
        ),
      ),
    );
  }

  Widget _returnToPlaybackButton(
    BuildContext context, {
    required bool enabled,
    bool caption = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: caption
          ? EdgeInsets.zero
          : const EdgeInsets.only(right: 8, top: 2, bottom: 2),
      child: IconButton(
        key: const ValueKey('workspace-return-to-playback'),
        tooltip: '回到播放页',
        style: caption
            ? desktopCaptionButtonStyle
            : IconButton.styleFrom(
                minimumSize: const Size(36, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: colors.onSurfaceVariant,
                disabledForegroundColor: colors.onSurface.withValues(
                  alpha: .38,
                ),
                backgroundColor: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: colors.outlineVariant),
                ),
              ),
        onPressed: enabled ? _returnToPlayback : null,
        icon: Icon(Icons.play_circle_outline_rounded, size: caption ? 18 : 20),
      ),
    );
  }

  Widget _sidebarRegion(
    BuildContext context, {
    required bool compact,
    required bool extended,
  }) {
    final visible = !compact && !_sidebarCollapsed;
    final width = extended ? 164.0 : 76.0;
    final target = visible ? width : 0.0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: compact || reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: IgnorePointer(
            ignoring: !visible,
            child: _sideNavigation(context, extended: extended),
          ),
        ),
      ),
      builder: (context, animatedWidth, child) {
        final currentWidth = compact || reduceMotion ? target : animatedWidth;
        return SizedBox(
          key: const ValueKey('workspace-sidebar-region'),
          width: currentWidth,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: width,
              maxWidth: width,
              child: Offstage(
                offstage: currentWidth == 0,
                child: Opacity(
                  opacity: (currentWidth / width).clamp(0, 1),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sideNavigation(BuildContext context, {required bool extended}) {
    final colors = Theme.of(context).colorScheme;
    final section = sectionForLocation(
      _frameTab(context).location,
      compact: _compactChannels,
    );
    Widget entry(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap, {
      Key? key,
      bool iconOnly = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Semantics(
              label: iconOnly ? label : null,
              selected: selected,
              button: true,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? 14 : 4,
                  vertical: iconOnly ? 8 : 13,
                ),
                child: iconOnly
                    ? Center(
                        child: Icon(
                          icon,
                          size: 21,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      )
                    : extended
                    ? Row(
                        children: [
                          Icon(
                            icon,
                            size: 21,
                            color: selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? colors.primary
                                    : colors.onSurface,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Icon(
                            icon,
                            size: 21,
                            color: selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactTools = constraints.maxHeight < 430;
        return Column(
          key: const ValueKey('workspace-side-navigation'),
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('workspace-primary-navigation'),
                padding: const EdgeInsets.only(top: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/branding/app_icon.png',
                          key: const ValueKey('workspace-brand-logo'),
                          width: 36,
                          height: 36,
                          excludeFromSemantics: true,
                        ),
                        if (extended) ...[
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              '哔帆',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final item in [
                    WorkspaceSection.home,
                    WorkspaceSection.dynamic,
                    if (!_compactChannels) WorkspaceSection.live,
                    WorkspaceSection.mine,
                  ])
                    entry(
                      item.label,
                      _sectionIcon(
                        item,
                        selected:
                            !_frameTab(context).isPlayback && section == item,
                      ),
                      !_frameTab(context).isPlayback && section == item,
                      () => _selectSection(item, compact: _compactChannels),
                      key: ValueKey('workspace-nav-${item.name}'),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.75,
              ),
              // Extremely short windows retain access to every utility while
              // leaving the primary navigation its own scrollable region.
              child: SingleChildScrollView(
                key: const ValueKey('workspace-utility-navigation'),
                reverse: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(height: 16),
                      ),
                      entry(
                        '消息',
                        _sectionIcon(WorkspaceSection.messages),
                        section == WorkspaceSection.messages,
                        () => _selectSection(
                          WorkspaceSection.messages,
                          compact: false,
                        ),
                        key: const ValueKey('workspace-nav-messages'),
                        iconOnly: compactTools,
                      ),
                      entry(
                        '下载',
                        _sectionIcon(WorkspaceSection.downloads),
                        section == WorkspaceSection.downloads,
                        () => _selectSection(
                          WorkspaceSection.downloads,
                          compact: false,
                        ),
                        key: const ValueKey('workspace-nav-downloads'),
                        iconOnly: compactTools,
                      ),
                      entry(
                        '设置',
                        _sectionIcon(WorkspaceSection.settings),
                        section == WorkspaceSection.settings,
                        () => _selectSection(
                          WorkspaceSection.settings,
                          compact: false,
                        ),
                        key: const ValueKey('workspace-nav-settings'),
                        iconOnly: compactTools,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _animatedBottomNavigation(BuildContext context) {
    // Scaffold clears MediaQuery's body insets. Read this view's inset to
    // hide immediately on keyboard opening and animate only the return.
    final visible = View.of(context).viewInsets.bottom == 0;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final target = visible ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: visible && !disableAnimations
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      child: _bottomNavigation(context),
      builder: (context, value, child) {
        final progress = disableAnimations ? 1.0 : value;
        if (!visible || progress == 0) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: progress < 1,
          child: ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: progress,
              child: Opacity(opacity: progress, child: child),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomNavigation(BuildContext context) {
    final sections = [
      WorkspaceSection.home,
      WorkspaceSection.dynamic,
      if (!_compactChannels) WorkspaceSection.live,
      WorkspaceSection.mine,
      WorkspaceSection.settings,
    ];
    final selected = sectionForLocation(
      _frameTab(context).location,
      compact: _compactChannels,
    );
    if (!sections.contains(selected)) {
      return _unselectedBottomNavigation(context, sections);
    }
    return NavigationBar(
      key: const ValueKey('workspace-bottom-navigation'),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      height: _bottomNavigationHeight,
      labelPadding: EdgeInsets.zero,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final colors = Theme.of(context).colorScheme;
        return _bottomNavigationLabelStyle.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        );
      }),
      selectedIndex: sections.indexOf(selected),
      onDestinationSelected: (index) {
        if (sections[index] != selected) {
          _selectSection(sections[index], compact: true);
        }
      },
      destinations: [
        for (final item in sections)
          NavigationDestination(
            key: ValueKey('workspace-bottom-${item.name}'),
            icon: Icon(_sectionIcon(item), size: _bottomNavigationIconSize),
            selectedIcon: Icon(
              _sectionIcon(item, selected: true),
              size: _bottomNavigationIconSize,
            ),
            label: item.label,
          ),
      ],
    );
  }

  Widget _unselectedBottomNavigation(
    BuildContext context,
    List<WorkspaceSection> sections,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final barTheme = NavigationBarTheme.of(context);
    return Material(
      key: const ValueKey('workspace-bottom-navigation'),
      color: barTheme.backgroundColor ?? colors.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _bottomNavigationHeight,
          child: Row(
            children: [
              for (final section in sections)
                Expanded(
                  child: Tooltip(
                    message: section.label,
                    child: Semantics(
                      selected: false,
                      button: true,
                      label: section.label,
                      child: InkWell(
                        key: ValueKey('workspace-bottom-${section.name}'),
                        onTap: () => _selectSection(section, compact: true),
                        child: Center(
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Keep NavigationDestination's indicator slot
                                // even when no primary destination is selected.
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const NavigationIndicator(
                                      animation: kAlwaysDismissedAnimation,
                                    ),
                                    Icon(
                                      _sectionIcon(section),
                                      size: _bottomNavigationIconSize,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                                MediaQuery.withClampedTextScaling(
                                  // Match NavigationDestination's label limit.
                                  maxScaleFactor: 1.3,
                                  child: Text(
                                    section.label,
                                    style: _bottomNavigationLabelStyle.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabStrip(BuildContext context, {Widget? navigationTools}) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: SizedBox(
        key: const ValueKey('workspace-tabs-toolbar'),
        height: workspaceHeaderVisibleForPlatform(Theme.of(context).platform)
            ? desktopCaptionHeight
            : 42,
        child: Row(
          children: [
            ?navigationTools,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (constraints.maxWidth - 66).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: _horizontalTabs(
                        key: const ValueKey('workspace-tab-strip'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final tab in _workspace.visibleTabs)
                              _tab(context, tab),
                          ],
                        ),
                      ),
                    ),
                    if (!_dualTabs)
                      SizedBox(
                        width: 42,
                        child: IconButton(
                          key: const ValueKey('new-workspace-tab'),
                          tooltip: shortcutHint(
                            widget.shortcuts,
                            ShortcutAction.newTab,
                            '新建标签页',
                          ),
                          onPressed: _newTab,
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ),
                    Expanded(
                      child:
                          widget.dragRegionBuilder?.call(
                            context,
                            const SizedBox.expand(),
                          ) ??
                          const SizedBox.expand(),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.windowControlsBuilder case final builder?
                when workspaceHeaderVisible)
              builder(context),
          ],
        ),
      ),
    );
  }

  Widget _backButton({bool caption = false}) => caption
      ? DesktopCaptionButton(
          key: const ValueKey('workspace-back'),
          tooltip: '返回上一页',
          onPressed: _canGoBack ? _goBack : null,
          icon: Icons.arrow_back_rounded,
        )
      : IconButton(
          key: const ValueKey('workspace-back'),
          tooltip: '返回上一页',
          onPressed: _canGoBack ? _goBack : null,
          icon: const Icon(Icons.arrow_back, size: 20),
        );

  Widget _homeButton({bool caption = false}) => caption
      ? DesktopCaptionButton(
          key: const ValueKey('workspace-playback-home'),
          tooltip: '回到主页',
          onPressed: _playbackHome,
          icon: Icons.home_outlined,
        )
      : IconButton(
          key: const ValueKey('workspace-playback-home'),
          tooltip: '回到主页',
          onPressed: _playbackHome,
          icon: const Icon(Icons.home_outlined, size: 20),
        );

  Widget _horizontalTabs({
    required Key key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) => ScrollConfiguration(
    behavior: const SmoothScrollBehavior(horizontalMouseWheel: true),
    child: SingleChildScrollView(
      key: key,
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: child,
    ),
  );

  Widget _tab(BuildContext context, WorkspaceTab tab) {
    final selected = tab.id == _frameTab(context).id;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: _tabKeys.putIfAbsent((
        _frameTab(context).id,
        _viewKey(_frameTab(context)).$2,
        tab.id,
      ), GlobalKey.new),
      padding: const EdgeInsets.only(left: 3, top: 4),
      child: Material(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: InkWell(
          key: ValueKey('workspace-tab-${tab.id}'),
          onTap: () => _selectTab(tab.id),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Semantics(
            selected: selected,
            button: true,
            child: SizedBox(
              width: tab.pinned ? 116 : 176,
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(_tabIcon(tab), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dualTabs && !tab.isPlayback
                          ? '浏览 · ${tab.title}'
                          : tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (!tab.pinned && (!_dualTabs || tab.isPlayback))
                    IconButton(
                      key: ValueKey('close-workspace-tab-${tab.id}'),
                      tooltip: '关闭${tab.title}',
                      onPressed: () => _closeTab(tab.id),
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, size: 13),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _tabIcon(WorkspaceTab tab) => switch (tab.location.path) {
    '/'
        when sectionForLocation(tab.location, compact: false) ==
            WorkspaceSection.dynamic =>
      _sectionIcon(WorkspaceSection.dynamic),
    '/me' => _sectionIcon(WorkspaceSection.mine),
    '/messages' => _sectionIcon(WorkspaceSection.messages),
    '/downloads' => _sectionIcon(WorkspaceSection.downloads),
    '/search' => BiliIcons.search,
    '/history' => BiliIcons.history,
    '/settings' => _sectionIcon(WorkspaceSection.settings),
    _ =>
      tab.isProfile
          ? Icons.person_outline
          : tab.isPlayback
          ? BiliIcons.playCount
          : BiliIcons.home,
  };

  Widget? _channelBar(BuildContext context, {required bool compact}) {
    final active = _frameTab(context);
    if (active.location.path == '/history' ||
        active.location.path == '/downloads' ||
        active.location.path == '/messages' ||
        active.location.path == '/settings' ||
        active.location.path == '/me') {
      return null;
    }
    if (!_compactChannels &&
        active.location.queryParameters['channel'] == 'live') {
      return _liveSectionBar(context);
    }
    final selected = active.isBrowse
        ? HomeChannel.primaryValues
              .where(
                (channel) =>
                    channel.name ==
                    (active.location.queryParameters['channel'] == 'ranking'
                        ? 'popular'
                        : active.location.queryParameters['channel'] ??
                              'recommended'),
              )
              .firstOrNull
        : null;
    final section = sectionForLocation(
      active.location,
      compact: _compactChannels,
    );
    final tabs = channelsForSection(section, compact: _compactChannels);
    final equalWidthTabs = compact && section == WorkspaceSection.dynamic;
    return SizedBox(
      height: PageTabStyle.barHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => _horizontalTabs(
          key: const ValueKey('home-channel-strip'),
          padding: equalWidthTabs
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 10),
          child: PagingTabStrip<HomeChannel>(
            tabs: tabs,
            value: selected,
            progress: _pagingFor(active),
            onSelected: _selectChannel,
            itemKey: (channel) => ValueKey('channel-${channel.name}'),
            spacing: equalWidthTabs ? 0 : 3,
            buttonStyle: PageTabStyle.buttonStyle(context).copyWith(
              fixedSize: equalWidthTabs
                  ? WidgetStatePropertyAll(
                      Size.fromWidth(constraints.maxWidth / tabs.length),
                    )
                  : null,
            ),
            labelBuilder: (context, channel) =>
                PageTabStyle.label(channel.label, icon: _channelIcon(channel)),
          ),
        ),
      ),
    );
  }

  Widget _liveSectionBar(BuildContext context) {
    final sections = HomeChannel.live.sections;
    final requested = _frameTab(context).location.queryParameters['section'];
    final selected = sections.contains(requested) ? requested : sections.first;
    return SizedBox(
      height: PageTabStyle.barHeight,
      child: _horizontalTabs(
        key: const ValueKey('workspace-live-section-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: PagingTabStrip<String>(
          tabs: sections,
          value: selected,
          onSelected: _selectLiveSection,
          itemKey: (section) => ValueKey('workspace-live-section-$section'),
          buttonStyle: PageTabStyle.buttonStyle(context),
          labelBuilder: (context, section) => PageTabStyle.label(
            section,
            icon: switch (section) {
              '我的关注' => Icons.favorite_border_rounded,
              '观看记录' => Icons.history_rounded,
              _ => Icons.live_tv_outlined,
            },
          ),
        ),
      ),
    );
  }

  Widget _searchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _navigationHeader(
      context,
      constraints,
      const SearchCategoryBar(),
      showTools: true,
    ),
  );

  bool _navigationToolsVisible(BuildContext context, {required bool compact}) =>
      switch (sectionForLocation(_frameTab(context).location, compact: false)) {
        WorkspaceSection.dynamic => !compact,
        WorkspaceSection.mine ||
        WorkspaceSection.messages ||
        WorkspaceSection.downloads ||
        WorkspaceSection.settings => false,
        _ => true,
      };

  Widget _navigationHeader(
    BuildContext context,
    BoxConstraints constraints,
    Widget? navigation, {
    bool? showTools,
    bool compact = false,
  }) {
    if (!(showTools ?? _navigationToolsVisible(context, compact: compact))) {
      if (navigation == null &&
          (_dualTabs || _singlePage) &&
          widget.windowControlsBuilder == null &&
          _frameShowsBack(context) &&
          _frameTab(context).location.path != '/me') {
        return SizedBox(
          key: const ValueKey('workspace-page-back-header'),
          height: 42,
          child: Align(alignment: Alignment.centerLeft, child: _backButton()),
        );
      }
      return navigation ?? const SizedBox.shrink();
    }
    final tools = ScrollCollapsingHeader(
      enabled:
          compact &&
          sectionForLocation(
                _frameTab(context).location,
                compact: _compactChannels,
              ) ==
              WorkspaceSection.home,
      child: _tools(context),
    );
    return compact || constraints.maxWidth < 760
        ? Column(mainAxisSize: MainAxisSize.min, children: [tools, ?navigation])
        : SizedBox(
            height: PageTabStyle.barHeight,
            child: Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth >= 1300 ? 470 : 380,
                  child: tools,
                ),
                if (navigation != null) Expanded(child: navigation),
              ],
            ),
          );
  }

  IconData _channelIcon(HomeChannel channel) => switch (channel) {
    HomeChannel.recommended => BiliIcons.home,
    HomeChannel.popular => Icons.local_fire_department_outlined,
    HomeChannel.dynamic => Icons.rss_feed_rounded,
    HomeChannel.videoDynamic => Icons.video_library_outlined,
    HomeChannel.bangumi => Icons.live_tv_outlined,
    HomeChannel.guochuang => Icons.animation_outlined,
    HomeChannel.live => Icons.live_tv,
    HomeChannel.cinema => Icons.movie_outlined,
    HomeChannel.categories => BiliIcons.categories,
    HomeChannel.ranking => BiliIcons.ranking,
    HomeChannel.watchLater => BiliIcons.watchLater,
    HomeChannel.favorites => BiliIcons.favorite,
  };

  Widget _tools(BuildContext context) => SizedBox(
    key: const ValueKey('workspace-common-tools'),
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (_frameShowsBack(context) && widget.windowControlsBuilder == null)
            _backButton(),
          if (widget.accountBuilder case final builder?) ...[
            builder(context),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                key: const ValueKey('workspace-search'),
                controller: _searchFor(_frameTab(context)),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 12),
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: '搜索视频、UP 主、番剧',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () =>
                        _search(_searchFor(_frameTab(context)).text),
                    icon: const Icon(BiliIcons.search, size: 17),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          if (_frameTab(context).location.path != '/' &&
              _frameTab(context).location.path != '/search' &&
              !_compactChannels) ...[
            _tool('观看历史', BiliIcons.history, '/history'),
            _tool('下载', Icons.download_outlined, '/downloads'),
            _tool('设置', BiliIcons.settings, '/settings'),
          ],
        ],
      ),
    ),
  );
  Widget _tool(String tooltip, IconData icon, String route) => IconButton(
    tooltip: tooltip,
    onPressed: () => route == '/settings'
        ? _selectSection(WorkspaceSection.settings, compact: false)
        : context.go(route),
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 18),
  );
}
