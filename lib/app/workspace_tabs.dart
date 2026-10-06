/// An in-memory browsing workspace. Routes remain shareable without tab IDs.
final class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.location,
    this.pinned = false,
  });

  final String id;
  final Uri location;
  final bool pinned;

  bool get isVideo => location.path.startsWith('/video/');
  bool get isPgc => location.path.startsWith('/pgc/');
  bool get isLive => location.path.startsWith('/live/');
  bool get isPlayback => isVideo || isPgc || isLive;
  bool get isProfile =>
      location.pathSegments.length == 2 &&
      location.pathSegments.first == 'user';
  bool get isBrowse => location.path == '/';

  String get title {
    if (pinned) return '首页';
    if (isBrowse) return '浏览';
    if (location.path == '/search') {
      final query = location.queryParameters['q'] ?? '';
      return query.isEmpty ? '搜索' : '搜索：$query';
    }
    if (location.path == '/history') return '观看历史';
    if (location.path == '/messages') return '我的消息';
    if (location.path == '/settings') return '设置';
    if (location.path == '/downloads') return '下载';
    if (isVideo) return location.pathSegments.last;
    if (isPgc) return '影视 · ${location.pathSegments.last}';
    if (isLive) return '直播 · ${location.pathSegments.last}';
    if (isProfile) return '用户主页 · ${location.pathSegments.last}';
    return '浏览';
  }

  Uri get route => location.replace(
    queryParameters: {...location.queryParameters, 'tab': id},
  );
}

final class WorkspaceTabs {
  static const maximumTabs = 16;
  static const maximumHistory = 64;
  final List<WorkspaceTab> _tabs = [
    WorkspaceTab(
      id: 'home',
      location: Uri(path: '/'),
      pinned: true,
    ),
  ];
  String _activeId = 'home';
  int _nextId = 1;
  final List<String> _backHistory = [];

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  String get activeId => _activeId;
  int get activeIndex => _tabs.indexWhere((tab) => tab.id == _activeId);
  WorkspaceTab get active => _tabs[activeIndex];
  bool get canGoBack => _backHistory.isNotEmpty;

  void _activate(String id) {
    if (id == _activeId) return;
    _backHistory.add(_activeId);
    if (_backHistory.length > maximumHistory) _backHistory.removeAt(0);
    _activeId = id;
  }

  /// Back traverses visits, rather than the visual order of the tab strip.
  /// In single-page mode a popped page is released once no earlier visit uses it.
  bool goBack({bool closeCurrent = false}) {
    if (!canGoBack) return false;
    final previousId = _activeId;
    _activeId = _backHistory.removeLast();
    if (closeCurrent && !_backHistory.contains(previousId)) close(previousId);
    _trimHistory();
    return true;
  }

  void _trimHistory() {
    while (_backHistory.isNotEmpty && _backHistory.last == _activeId) {
      _backHistory.removeLast();
    }
  }

  WorkspaceTab addBrowseTab() {
    if (_tabs.length >= maximumTabs) return active;
    final tab = WorkspaceTab(
      id: 'tab-${_nextId++}',
      location: Uri(path: '/'),
    );
    _tabs.add(tab);
    _activate(tab.id);
    return tab;
  }

  /// A route with a tab ID updates that tab; a plain feature route opens one.
  bool acceptRoute(Uri route, {bool singlePage = false}) {
    final requestedId = route.queryParameters['tab'];
    final parameters = {...route.queryParameters}..remove('tab');
    final location = route.replace(queryParameters: parameters);
    final known = _tabs.indexWhere((tab) => tab.id == requestedId);
    if (known >= 0 && (!_tabs[known].pinned || location.path == '/')) {
      final previous = _tabs[known];
      _tabs[known] = WorkspaceTab(
        id: previous.id,
        location: location,
        pinned: previous.pinned,
      );
      _activate(previous.id);
      return true;
    }
    if (location.path == '/') {
      _tabs[0] = WorkspaceTab(id: 'home', location: location, pinned: true);
      _activate('home');
      return true;
    }
    final existing = _tabs.where((tab) => tab.location == location).firstOrNull;
    if (existing != null) {
      _activate(existing.id);
      return true;
    }
    if (_tabs.length >= maximumTabs) {
      if (!singlePage) return false;
      // A phone has no tab-close UI. Bound the page cache by releasing the
      // oldest non-home, inactive page instead of blocking further browsing.
      close(_tabs.firstWhere((tab) => !tab.pinned && tab.id != _activeId).id);
    }
    final tab = WorkspaceTab(id: 'tab-${_nextId++}', location: location);
    _tabs.add(tab);
    _activate(tab.id);
    return true;
  }

  void select(String id) {
    if (_tabs.any((tab) => tab.id == id)) _activate(id);
  }

  void cycle({bool backwards = false}) {
    final offset = backwards ? -1 : 1;
    _activate(_tabs[(activeIndex + offset) % _tabs.length].id);
  }

  bool close(String id) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0 || _tabs[index].pinned) return false;
    final wasActive = _activeId == id;
    _tabs.removeAt(index);
    _backHistory.removeWhere((previous) => previous == id);
    if (wasActive) _activeId = _tabs[index > 0 ? index - 1 : 0].id;
    _trimHistory();
    return true;
  }
}
