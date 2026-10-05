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
  final List<WorkspaceTab> _tabs = [
    WorkspaceTab(
      id: 'home',
      location: Uri(path: '/'),
      pinned: true,
    ),
  ];
  String _activeId = 'home';
  int _nextId = 1;

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  String get activeId => _activeId;
  int get activeIndex => _tabs.indexWhere((tab) => tab.id == _activeId);
  WorkspaceTab get active => _tabs[activeIndex];

  WorkspaceTab addBrowseTab() {
    if (_tabs.length >= maximumTabs) return active;
    final tab = WorkspaceTab(
      id: 'tab-${_nextId++}',
      location: Uri(path: '/'),
    );
    _tabs.add(tab);
    _activeId = tab.id;
    return tab;
  }

  /// A route with a tab ID updates that tab; a plain feature route opens one.
  bool acceptRoute(Uri route) {
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
      _activeId = previous.id;
      return true;
    }
    if (location.path == '/') {
      _tabs[0] = WorkspaceTab(id: 'home', location: location, pinned: true);
      _activeId = 'home';
      return true;
    }
    final existing = _tabs.where((tab) => tab.location == location).firstOrNull;
    if (existing != null) {
      _activeId = existing.id;
      return true;
    }
    // Existing tabs remain alive until the user explicitly closes them.
    if (_tabs.length >= maximumTabs) return false;
    final tab = WorkspaceTab(id: 'tab-${_nextId++}', location: location);
    _tabs.add(tab);
    _activeId = tab.id;
    return true;
  }

  void select(String id) {
    if (_tabs.any((tab) => tab.id == id)) _activeId = id;
  }

  void cycle({bool backwards = false}) {
    final offset = backwards ? -1 : 1;
    _activeId = _tabs[(activeIndex + offset) % _tabs.length].id;
  }

  bool close(String id) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0 || _tabs[index].pinned) return false;
    final wasActive = _activeId == id;
    _tabs.removeAt(index);
    if (wasActive) _activeId = _tabs[index > 0 ? index - 1 : 0].id;
    return true;
  }
}
