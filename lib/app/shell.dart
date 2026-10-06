import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/feed/domain/home_channel.dart';
import '../features/search/presentation/search_category_bar.dart';
import '../core/presentation/workspace_activity.dart';
import 'workspace_tabs.dart';
import 'platform_defaults.dart';
import '../core/presentation/keyboard_shortcuts.dart';
import '../features/settings/domain/shortcut_settings.dart';
import '../features/settings/domain/settings_category.dart';
import '../features/settings/domain/app_settings.dart';
import '../shared/ui/smooth_scroll_behavior.dart';
import '../shared/ui/bili_icons.dart';
import '../shared/ui/app_notice.dart';

typedef WorkspacePageBuilder = Widget Function(
  BuildContext context,
  WorkspaceTab tab,
);
typedef DragRegionBuilder = Widget Function(BuildContext context, Widget child);

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
    this.windowControlsBuilder,
    this.dragRegionBuilder,
    this.shortcuts = const ShortcutSettings.defaults(),
    this.navigationMode,
  });
  final ShortcutSettings shortcuts;
  final WorkspaceNavigationMode? navigationMode;
  final String location;
  final Widget child;
  final WidgetBuilder? accountBuilder;
  final WorkspacePageBuilder? pageBuilder;
  final WidgetBuilder? windowControlsBuilder;
  final DragRegionBuilder? dragRegionBuilder;
  @override
  State<BiliAppShell> createState() => _BiliAppShellState();
}

final class _BiliAppShellState extends State<BiliAppShell> {
  final _workspace = WorkspaceTabs();
  final _searchController = TextEditingController();
  final _tabKeys = <String, GlobalKey>{};
  final _searchDrafts = <String, String>{};
  final _pageStorage = <String, PageStorageBucket>{};

  bool get _singlePage =>
      (widget.navigationMode ?? defaultWorkspaceNavigationMode) ==
      WorkspaceNavigationMode.singlePage;

  @override
  void initState() {
    super.initState();
    _workspace.acceptRoute(Uri.parse(widget.location));
    _restoreSearch();
    _searchController.addListener(_saveSearch);
    // Unfocusing search can return focus to the route scope outside this
    // shell. Workspace commands must not depend on a focused descendant.
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  @override
  void didUpdateWidget(covariant BiliAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationMode != oldWidget.navigationMode) _revealActiveTab();
    if (widget.location != oldWidget.location) {
      if (!_workspace.acceptRoute(
        Uri.parse(widget.location),
        singlePage: _singlePage,
      )) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showAppNotice(context, '最多打开 16 个标签页，请先关闭不用的标签');
          context.go(_workspace.active.route.toString());
        });
        return;
      }
      _prunePages();
      _restoreSearch();
      _revealActiveTab();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealActiveTab();
  }

  void _prunePages() {
    final liveIds = _workspace.tabs.map((tab) => tab.id).toSet();
    _tabKeys.removeWhere((id, _) => !liveIds.contains(id));
    _searchDrafts.removeWhere((id, _) => !liveIds.contains(id));
    _pageStorage.removeWhere((id, _) => !liveIds.contains(id));
  }

  void _saveSearch() =>
      _searchDrafts[_workspace.activeId] = _searchController.text;
  void _restoreSearch() {
    _searchController.text =
        _searchDrafts[_workspace.activeId] ??
        _workspace.active.location.queryParameters['q'] ??
        '';
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _searchController.dispose();
    super.dispose();
  }

  void _revealActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabContext = _tabKeys[_workspace.activeId]?.currentContext;
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
    if (_singlePage) return;
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

  void _updatePageLocation(String id, Uri location) {
    if (!mounted || !_workspace.updateLocation(id, location)) return;
    setState(() {});
    if (id == _workspace.activeId) _commitWorkspace();
  }

  void _closeTab(String id) {
    final wasActive = id == _workspace.activeId;
    if (!_workspace.close(id)) return;
    _tabKeys.remove(id);
    _searchDrafts.remove(id);
    _pageStorage.remove(id);
    setState(() {});
    if (wasActive) _commitWorkspace();
  }

  void _goBack() {
    if (!_workspace.goBack(closeCurrent: _singlePage)) return;
    _prunePages();
    setState(() {});
    _commitWorkspace();
  }

  void _cycleTabs({bool backwards = false}) {
    if (_singlePage) return;
    setState(() => _workspace.cycle(backwards: backwards));
    _commitWorkspace();
  }

  void _search(String input) {
    final query = input.trim();
    if (query.isEmpty) return;
    context.go(Uri(path: '/search', queryParameters: {'q': query}).toString());
  }

  void _selectChannel(HomeChannel channel) {
    final tab = _workspace.active.isBrowse
        ? _workspace.active
        : _workspace.tabs.first;
    context.go(
      Uri(
        path: '/',
        queryParameters: {'channel': channel.name, 'tab': tab.id},
      ).toString(),
    );
  }

  bool _shortcut(String key) {
    final action = widget.shortcuts.actionFor(key);
    // Closing a page is a workspace command even while its composer owns
    // focus. Explicit side-button bindings are also workspace commands;
    // typing keys stay with the editor and dialogs protect the page below.
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final keyParts = key.split('+');
    final modifiers = keyParts.take(keyParts.length - 1);
    final sideButton =
        keyParts.last == 'MouseBack' || keyParts.last == 'MouseForward';
    final closeWhileEditing =
        action == ShortcutAction.closeTab &&
        (sideButton ||
            modifiers.contains('Ctrl') ||
            modifiers.contains('Meta'));
    if (!closeWhileEditing && shortcutsBlocked(context)) return false;
    switch (action) {
      case ShortcutAction.newTab:
        _newTab();
      case ShortcutAction.closeTab:
        if (_singlePage) {
          _goBack();
        } else {
          _closeTab(_workspace.activeId);
        }
      default:
        return false;
    }
    return true;
  }

  KeyEventResult _key(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = shortcutKey(event);
    return key != null && _shortcut(key)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_workspace.canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _goBack();
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            _cycleTabs,
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            _cycleTabs(backwards: true),
      },
      child: Focus(
        autofocus: true,
        child: MouseShortcutListener(
          onShortcut: _shortcut,
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  return Column(
                    children: [
                      if (_singlePage)
                        _singlePageHeader(context)
                      else
                        _tabStrip(context),
                      if (_workspace.active.location.path != '/search' &&
                          !_workspace.active.isPlayback &&
                          !_workspace.active.isProfile &&
                          compact) ...[
                        _channelBar(context),
                        _tools(context, compact: true),
                      ] else if (_workspace.active.location.path != '/search' &&
                          !_workspace.active.isPlayback &&
                          !_workspace.active.isProfile)
                        SizedBox(
                          height: 58,
                          child: Row(
                            children: [
                              Expanded(child: _channelBar(context)),
                              SizedBox(
                                width: constraints.maxWidth >= 1300 ? 470 : 380,
                                child: _tools(context, compact: false),
                              ),
                            ],
                          ),
                        ),
                      Expanded(child: _pages(context)),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _pages(BuildContext context) {
    final builder = widget.pageBuilder;
    if (builder == null) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        // go_router needs its shell Navigator mounted to dispatch system back
        // and dismiss dialogs. Its feature routes only build placeholders.
        Offstage(child: widget.child),
        for (final tab in _workspace.tabs)
          Offstage(
            key: ValueKey(tab.id),
            offstage: tab.id != _workspace.activeId,
            // Keep account listeners active for cached pages. Riverpod pauses
            // listeners below a disabled TickerMode, delaying logout cleanup.
            child: FocusScope(
              canRequestFocus: tab.id == _workspace.activeId,
              skipTraversal: tab.id != _workspace.activeId,
              child: WorkspaceActivity(
                active: tab.id == _workspace.activeId,
                child: PageStorage(
                  bucket: _pageStorage.putIfAbsent(
                    tab.id,
                    PageStorageBucket.new,
                  ),
                  child: WorkspacePageHeader(
                    builder: _searchHeader,
                    child: WorkspacePageNavigation(
                      navigate: (location) =>
                          _updatePageLocation(tab.id, location),
                      child: builder(context, tab),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tabStrip(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            _backButton(),
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
                            for (final tab in _workspace.tabs)
                              _tab(context, tab),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: IconButton(
                        key: const ValueKey('new-workspace-tab'),
                        tooltip: '新建标签页 (Ctrl+T)',
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
            if (widget.windowControlsBuilder case final builder?)
              builder(context),
          ],
        ),
      ),
    );
  }

  Widget _backButton() => IconButton(
    key: const ValueKey('workspace-back'),
    tooltip: '返回上一页',
    onPressed: _workspace.canGoBack ? _goBack : null,
    icon: const Icon(Icons.arrow_back, size: 20),
  );

  Widget _singlePageHeader(BuildContext context) => ColoredBox(
    key: const ValueKey('single-page-header'),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SizedBox(
      height: 42,
      child: Row(
        children: [
          _backButton(),
          Expanded(
            child:
                widget.dragRegionBuilder?.call(context, _pageTitle()) ??
                _pageTitle(),
          ),
          if (!_workspace.active.pinned)
            IconButton(
              key: const ValueKey('workspace-home'),
              tooltip: '首页',
              onPressed: () => _selectTab('home'),
              icon: const Icon(BiliIcons.home, size: 20),
            ),
          if (widget.windowControlsBuilder case final builder?)
            builder(context),
        ],
      ),
    ),
  );

  Widget _pageTitle() => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      _workspace.active.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14),
    ),
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
    final selected = tab.id == _workspace.activeId;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: _tabKeys.putIfAbsent(tab.id, GlobalKey.new),
      padding: const EdgeInsets.only(left: 3, top: 4),
      child: Material(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        child: InkWell(
          key: ValueKey('workspace-tab-${tab.id}'),
          onTap: () => _selectTab(tab.id),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          child: Semantics(
            selected: selected,
            button: true,
            child: SizedBox(
              width: tab.pinned ? 116 : 176,
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(tab.pinned ? BiliIcons.home : _tabIcon(tab), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (!tab.pinned)
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
    '/search' => BiliIcons.search,
    '/history' => BiliIcons.history,
    '/settings' => BiliIcons.settings,
    _ =>
      tab.isProfile
          ? Icons.person_outline
          : tab.isPlayback
          ? BiliIcons.playCount
          : BiliIcons.home,
  };

  Widget _channelBar(BuildContext context) {
    final active = _workspace.active;
    if (active.location.path == '/settings') return _settingsBar(context);
    final selected = active.isBrowse
        ? active.location.queryParameters['channel'] ?? 'recommended'
        : '';
    return SizedBox(
      height: 58,
      child: _horizontalTabs(
        key: const ValueKey('home-channel-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (final channel in HomeChannel.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: TextButton(
                  key: ValueKey('channel-${channel.name}'),
                  onPressed: () => _selectChannel(channel),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    foregroundColor: selected == channel.name
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    textStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_channelIcon(channel), size: 16),
                          const SizedBox(width: 5),
                          Text(channel.label),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 20,
                        height: 2,
                        color: selected == channel.name
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 760
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SearchCategoryBar(),
              _tools(context, compact: true),
            ],
          )
        : SizedBox(
            height: 58,
            child: Row(
              children: [
                const Expanded(child: SearchCategoryBar()),
                SizedBox(
                  width: constraints.maxWidth >= 1300 ? 470 : 380,
                  child: _tools(context, compact: false),
                ),
              ],
            ),
          ),
  );

  Widget _settingsBar(BuildContext context) {
    final selected = SettingsCategory.fromName(
      _workspace.active.location.queryParameters['section'],
    );
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 58,
      child: _horizontalTabs(
        key: const ValueKey('settings-category-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (final category in SettingsCategory.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: TextButton(
                  key: ValueKey('settings-category-${category.name}'),
                  onPressed: () => context.go(
                    Uri(
                      path: '/settings',
                      queryParameters: {
                        'tab': _workspace.activeId,
                        'section': category.name,
                      },
                    ).toString(),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 42),
                    foregroundColor: selected == category
                        ? colors.primary
                        : colors.onSurface,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(category.label),
                      const SizedBox(height: 4),
                      Container(
                        width: 20,
                        height: 2,
                        color: selected == category
                            ? colors.primary
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _channelIcon(HomeChannel channel) => switch (channel) {
    HomeChannel.recommended => BiliIcons.home,
    HomeChannel.popular => Icons.local_fire_department_outlined,
    HomeChannel.dynamic => BiliIcons.dynamic,
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

  Widget _tools(BuildContext context, {required bool compact}) => SizedBox(
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                key: const ValueKey('workspace-search'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 12),
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: '搜索视频',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () => _search(_searchController.text),
                    icon: const Icon(BiliIcons.search, size: 17),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          if (widget.accountBuilder case final builder?)
            compact
                ? IconButton(
                    tooltip: '账号',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: builder(context),
                        ),
                      ),
                    ),
                    icon: const Icon(BiliIcons.account, size: 22),
                  )
                : builder(context),
          _tool('观看历史', BiliIcons.history, '/history'),
          _tool('下载', Icons.download_outlined, '/downloads'),
          _tool('设置', BiliIcons.settings, '/settings'),
        ],
      ),
    ),
  );
  Widget _tool(String tooltip, IconData icon, String route) => IconButton(
    tooltip: tooltip,
    onPressed: () => context.go(route),
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 18),
  );
}
