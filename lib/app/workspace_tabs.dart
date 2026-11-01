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
  bool get isOffline => location.path.startsWith('/offline/');
  bool get isPlayback => isVideo || isPgc || isLive || isOffline;
  bool get isProfile =>
      location.pathSegments.length == 2 &&
      location.pathSegments.first == 'user';
  bool get isBrowse => location.path == '/';
  bool get isAccount => location.path == '/me';
  bool get isHistory => location.path == '/history';
  bool get isMessages => location.path == '/messages';
  bool get isDownloads => location.path == '/downloads';
  bool get isSettings => location.path == '/settings';
  bool get isRoot =>
      isBrowse ||
      isAccount ||
      isHistory ||
      isMessages ||
      isDownloads ||
      isSettings;

  String get title {
    if (isBrowse) return pinned ? '首页' : '浏览';
    if (location.path == '/search') {
      final query = location.queryParameters['q'] ?? '';
      return query.isEmpty ? '搜索' : '搜索：$query';
    }
    if (location.path == '/history') return '观看历史';
    if (location.path == '/messages') return '我的消息';
    if (location.path == '/settings') return '设置';
    if (location.path == '/downloads') return '下载';
    if (location.path == '/me') return '我的';
    if (isOffline) return '离线播放';
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
  bool _dualMode = false;
  bool _singleMode = false;
  String _browseId = 'home';
  String? _playbackId;
  final List<String> _playbackVisits = [];
  final List<Uri> _playbackHistory = [];
  ({String id, Uri location, List<String> history})? _playbackEntry;
  ({String tabId, String browseId, Uri rootLocation, List<String> history})?
  _messagesReturnPoint;

  bool get canReturnFromMessages =>
      active.isMessages && _messagesReturnPoint != null;

  /// Android's inbox Back restores its entry page, including the root channel.
  bool returnFromMessages() {
    final point = _messagesReturnPoint;
    if (!active.isMessages || point == null) return false;
    _messagesReturnPoint = null;
    updateLocation('home', point.rootLocation);
    final originExists = _tabs.any((tab) => tab.id == point.tabId);
    _browseId = _tabs.any((tab) => tab.id == point.browseId && !tab.isPlayback)
        ? point.browseId
        : 'home';
    _activate(originExists ? point.tabId : 'home');
    _backHistory
      ..clear()
      ..addAll(
        originExists
            ? point.history.where((id) => _tabs.any((tab) => tab.id == id))
            : const <String>[],
      );
    _trimHistory();
    return true;
  }

  /// Dual mode projects the retained workspace onto a browsing and a playback
  /// slot. Existing tabs survive mode changes; new media reuse one page/session.
  void setDualMode(bool enabled) {
    if (_dualMode == enabled) return;
    _dualMode = enabled;
    if (!enabled) return;
    if (active.isPlayback) {
      _playbackId = activeId;
    } else {
      _browseId = activeId;
    }
    if (!_tabs.any((tab) => tab.id == _playbackId)) {
      _playbackId = latestPlayback?.id;
    }
    if (!_tabs.any((tab) => tab.id == _browseId && !tab.isPlayback)) {
      _browseId = 'home';
    }
  }

  /// Single-page Back consumes visits and releases pages no longer in history.
  /// Mode changes alone retain every page and its playback owner.
  void setSingleMode(bool enabled) => _singleMode = enabled;

  List<WorkspaceTab> get visibleTabs => !_dualMode
      ? tabs
      : [
          _tabs.firstWhere((tab) => tab.id == _browseId),
          if (_playbackId case final id?) ..._tabs.where((tab) => tab.id == id),
        ];

  String get browseId => _browseId;
  String? get playbackId => _playbackId;

  /// Most recently visited media page that is still retained in the workspace.
  /// Unlike Back history, this stays bounded by the open pages, not visit count.
  WorkspaceTab? get latestPlayback {
    for (final id in _playbackVisits.reversed) {
      final tab = _tabs
          .where((tab) => tab.id == id && tab.isPlayback)
          .firstOrNull;
      if (tab != null) return tab;
    }
    return null;
  }

  List<Uri> get playbackHistory => List.unmodifiable(_playbackHistory);
  bool get canGoBackBrowsing => _browseId != 'home';

  /// Desktop dual windows keep media navigation out of the browser's Back.
  bool goBackBrowsing() {
    if (!canGoBackBrowsing) return false;
    final leaving = _browseId;
    var destination = 'home';
    while (_backHistory.isNotEmpty) {
      final id = _backHistory.removeLast();
      if (id == leaving ||
          !_tabs.any((tab) => tab.id == id && !tab.isPlayback)) {
        continue;
      }
      destination = id;
      break;
    }
    _activeId = _browseId = destination;
    // Change the selected browsing slot before closing it; ordinary close
    // intentionally protects the currently visible dual browsing slot.
    close(leaving);
    _trimHistory();
    return true;
  }

  void clearPlaybackHistory() => _playbackHistory.clear();

  /// Leave all media visits in single mode; other modes retain playback.
  void returnFromPlayback() {
    if (_dualMode) {
      select(_browseId);
      return;
    }
    if (!_singleMode) {
      acceptRoute(Uri(path: '/'));
      return;
    }
    final visits = [..._backHistory, _activeId];
    final firstMedia = visits.indexWhere(
      (id) => _tabs.any((tab) => tab.id == id && tab.isPlayback),
    );
    final retained = firstMedia < 0
        ? <String>[]
        : visits.take(firstMedia).toList();
    final entry = _playbackEntry;
    if (entry != null && _tabs.any((tab) => tab.id == entry.id)) {
      _activeId = entry.id;
      updateLocation(entry.id, entry.location);
      retained
        ..clear()
        ..addAll(entry.history.where((id) => _tabs.any((tab) => tab.id == id)));
    } else {
      _activeId = retained.isEmpty ? 'home' : retained.removeLast();
    }
    _playbackEntry = null;
    _browseId = _activeId;
    _backHistory
      ..clear()
      ..addAll(retained);
    for (final tab in _tabs.where((tab) => tab.isPlayback).toList()) {
      close(tab.id);
    }
    _playbackHistory.clear();
    _trimHistory();
  }

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  String get activeId => _activeId;
  int get activeIndex => _tabs.indexWhere((tab) => tab.id == _activeId);
  WorkspaceTab get active => _tabs[activeIndex];
  bool get canGoBack {
    if (_singleMode && active.pinned) return false;
    if (_dualMode) return active.isPlayback || canGoBackBrowsing;
    // History is bounded; a deep page must still be able to reach the root
    // after repeated visits have pushed its original root visit out.
    if (_singleMode) return true;
    return _backHistory.any((id) => id != activeId);
  }

  /// Resolves a preview without selecting a page or consuming its history.
  WorkspaceTab? backDestination({bool fromMessages = false}) {
    WorkspaceTab rootAt(Uri location) =>
        WorkspaceTab(id: 'home', location: location, pinned: true);
    if (fromMessages && canReturnFromMessages) {
      final point = _messagesReturnPoint;
      if (point == null) return null;
      final origin = _tabs.where((tab) => tab.id == point.tabId).firstOrNull;
      return origin == null || origin.id == 'home'
          ? rootAt(point.rootLocation)
          : origin;
    }
    if (!canGoBack) return null;
    if (_singleMode && active.isPlayback && _playbackHistory.isNotEmpty) {
      return WorkspaceTab(id: activeId, location: _playbackHistory.last);
    }
    if (_dualMode && active.isPlayback) {
      if (_playbackHistory.isNotEmpty) {
        return WorkspaceTab(id: activeId, location: _playbackHistory.last);
      }
      return _tabs.firstWhere((tab) => tab.id == _browseId);
    }
    for (final id in _backHistory.reversed) {
      final destination = _tabs.where((tab) => tab.id == id).firstOrNull;
      if (destination == null || id == activeId) continue;
      if (_dualMode && destination.isPlayback) continue;
      return destination;
    }
    return _dualMode || _singleMode ? _tabs.first : null;
  }

  void _activate(String id) {
    if (id != _activeId) {
      _backHistory.add(_activeId);
      if (_backHistory.length > maximumHistory) _backHistory.removeAt(0);
      _activeId = id;
    }
    if (active.isPlayback) {
      _rememberPlaybackVisit();
      if (_playbackId != id) _playbackHistory.clear();
      _playbackId = id;
    } else {
      _browseId = id;
    }
  }

  void _rememberPlaybackVisit() {
    _playbackVisits
      ..remove(_activeId)
      ..add(_activeId);
  }

  /// Back traverses visits, rather than the visual order of the tab strip.
  bool goBack() {
    if (!canGoBack) return false;
    if (_singleMode && active.isPlayback && _playbackHistory.isNotEmpty) {
      return updateLocation(activeId, _playbackHistory.removeLast());
    }
    if (_dualMode && active.isPlayback) {
      if (_playbackHistory.isNotEmpty) {
        updateLocation(activeId, _playbackHistory.removeLast());
      } else {
        return close(activeId);
      }
      return true;
    }
    if (_dualMode) return goBackBrowsing();
    _trimHistory();
    final leaving = _activeId;
    _activeId = _backHistory.isEmpty ? 'home' : _backHistory.removeLast();
    if (!active.isPlayback) {
      _browseId = _activeId;
    } else if (_playbackId != activeId) {
      _playbackId = activeId;
      _playbackHistory.clear();
    }
    if (active.isPlayback) _rememberPlaybackVisit();
    _trimHistory();
    if (_singleMode && !_backHistory.contains(leaving)) close(leaving);
    return true;
  }

  void _trimHistory() {
    while (_backHistory.isNotEmpty && _backHistory.last == _activeId) {
      _backHistory.removeLast();
    }
  }

  WorkspaceTab addBrowseTab() {
    if (_dualMode) {
      select(_browseId);
      return active;
    }
    if (_tabs.length >= maximumTabs) return active;
    final tab = WorkspaceTab(
      id: 'tab-${_nextId++}',
      location: Uri(path: '/'),
    );
    _tabs.add(tab);
    _activate(tab.id);
    return tab;
  }

  /// Playback advancement changes a cached page without recording a visit or
  /// selecting it. A closed page must never be recreated by a late callback.
  bool updateLocation(String id, Uri route, {Uri? expectedLocation}) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return false;
    final previous = _tabs[index];
    if (expectedLocation != null && previous.location != expectedLocation) {
      return false;
    }
    if (previous.pinned && !WorkspaceTab(id: '', location: route).isRoot) {
      return false;
    }
    final parameters = {...route.queryParameters}..remove('tab');
    _tabs[index] = WorkspaceTab(
      id: previous.id,
      location: route.replace(queryParameters: parameters),
      pinned: previous.pinned,
    );
    return true;
  }

  /// Primary destinations select home; explicit feed tabs and detail routes
  /// retain their independent page identities.
  bool acceptRoute(Uri route) {
    final requestedId = route.queryParameters['tab'];
    final parameters = {...route.queryParameters}..remove('tab');
    final location = route.replace(queryParameters: parameters);
    final target = WorkspaceTab(id: '', location: location);
    if (_singleMode &&
        target.isPlayback &&
        !active.isPlayback &&
        !_backHistory.any(
          (id) => _tabs.any((tab) => tab.id == id && tab.isPlayback),
        )) {
      _playbackEntry = (
        id: activeId,
        location: active.location,
        history: List.of(_backHistory),
      );
    }
    if (target.isMessages && !active.isMessages) {
      final root = _tabs.first;
      _messagesReturnPoint = (
        tabId: activeId,
        browseId: _browseId,
        // A profile opened from the inbox can itself start another chat.
        // Keep a non-inbox root so returning from that profile cannot loop.
        rootLocation: root.isMessages
            ? _messagesReturnPoint?.rootLocation ?? Uri(path: '/')
            : root.location,
        history: List.of(_backHistory),
      );
    }
    if ((target.isRoot && !target.isBrowse) ||
        (target.isBrowse && (requestedId == null || requestedId == 'home'))) {
      _tabs[0] = WorkspaceTab(id: 'home', location: location, pinned: true);
      // Primary destinations share one root identity. Moving between them is
      // a selection, not a visit to a new page in the transient Back stack.
      _activeId = _browseId = 'home';
      if (_singleMode) {
        _backHistory.clear();
        _playbackEntry = null;
      }
      _trimHistory();
      return true;
    }
    if (_dualMode && target.isPlayback && _playbackId != null) {
      final slot = _tabs.firstWhere((tab) => tab.id == _playbackId);
      // Route commits and part/quality updates are not new media visits.
      if (slot.location.path != location.path) {
        _playbackHistory.add(slot.location);
        if (_playbackHistory.length > maximumTabs) {
          _playbackHistory.removeAt(0);
        }
      }
      updateLocation(slot.id, location);
      _activate(slot.id);
      return true;
    }
    final known = _tabs.indexWhere((tab) => tab.id == requestedId);
    if (known >= 0 && (!_tabs[known].pinned || target.isRoot)) {
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
      if (!_dualMode && !_singleMode) return false;
      // Single/dual mode has no tab-close UI. Protect the last playback page
      // while browsing spaces, and evict an older inactive page at capacity.
      close(
        _tabs
            .firstWhere(
              (tab) =>
                  !tab.pinned &&
                  tab.id != _activeId &&
                  (!_dualMode ||
                      (tab.id != _browseId && tab.id != _playbackId)) &&
                  (!_singleMode ||
                      (tab.id != _playbackId && tab.id != _playbackEntry?.id)),
            )
            .id,
      );
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
    final candidates = visibleTabs;
    final index = candidates.indexWhere((tab) => tab.id == activeId);
    final offset = backwards ? -1 : 1;
    _activate(candidates[(index + offset) % candidates.length].id);
  }

  bool close(String id) {
    if (_dualMode && id == _browseId) return false;
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0 || _tabs[index].pinned) return false;
    final wasActive = _activeId == id;
    _tabs.removeAt(index);
    _playbackVisits.remove(id);
    _backHistory.removeWhere((previous) => previous == id);
    if (id == _playbackId) {
      _playbackId = null;
      _playbackHistory.clear();
    }
    if (id == _browseId) _browseId = 'home';
    if (wasActive) {
      _activeId = _dualMode ? _browseId : _tabs[index > 0 ? index - 1 : 0].id;
      if (active.isPlayback) _rememberPlaybackVisit();
    }
    _trimHistory();
    return true;
  }
}
