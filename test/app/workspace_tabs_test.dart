import 'package:bilisail/app/workspace_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background playback updates preserve selection and visit history', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/video/BV1234567890?queue=fixture'));
    final videoId = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/search?q=still-reading'));
    final searchId = workspace.activeId;
    expect(
      workspace.updateLocation(
        videoId,
        Uri.parse('/video/BV0987654321?queue=fixture&tab=$videoId'),
      ),
      isTrue,
    );
    expect(workspace.activeId, searchId);
    expect(workspace.tabs, hasLength(3));
    expect(
      workspace.tabs.firstWhere((tab) => tab.id == videoId).location,
      Uri.parse('/video/BV0987654321?queue=fixture'),
    );
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, videoId);
    expect(workspace.active.location.path, '/video/BV0987654321');
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, 'home');
    expect(workspace.canGoBack, isFalse);
  });

  test('late playback cannot recreate closed tabs or replace pinned home', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
    final videoId = workspace.activeId;
    workspace.close(videoId);
    expect(
      workspace.updateLocation(videoId, Uri.parse('/video/BV0987654321')),
      isFalse,
    );
    expect(
      workspace.updateLocation('home', Uri.parse('/video/BV0987654321')),
      isFalse,
    );
    expect(workspace.tabs, hasLength(1));
    expect(workspace.activeId, 'home');
    expect(workspace.canGoBack, isFalse);
  });

  test(
    'back follows visits, reuses pages and does not record route commits',
    () {
      final workspace = WorkspaceTabs();
      workspace.acceptRoute(Uri.parse('/search?q=test'));
      final search = workspace.active;
      workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
      final video = workspace.active;
      workspace.select(search.id);
      workspace.acceptRoute(search.route);
      expect(workspace.goBack(), isTrue);
      expect(workspace.activeId, video.id);
      workspace.acceptRoute(video.route);
      expect(workspace.goBack(), isTrue);
      expect(workspace.activeId, search.id);
      expect(workspace.goBack(), isTrue);
      expect(workspace.activeId, 'home');
      expect(workspace.canGoBack, isFalse);
      expect(workspace.tabs, hasLength(3));
    },
  );

  test('section updates stay on a page and back restores the home channel', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/?channel=bangumi&tab=home'));
    workspace.acceptRoute(Uri.parse('/settings'));
    workspace.acceptRoute(
      Uri.parse('/settings?section=playback&tab=${workspace.activeId}'),
    );
    workspace.goBack(closeCurrent: true);
    expect(workspace.active.location.queryParameters['channel'], 'bangumi');
    expect(workspace.canGoBack, isFalse);
    expect(workspace.tabs, hasLength(1));
  });

  test(
    'single-page back keeps repeated destinations until their final pop',
    () {
      final workspace = WorkspaceTabs();
      workspace.acceptRoute(Uri.parse('/search?q=test'));
      final search = workspace.active;
      workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
      final video = workspace.active;
      workspace.acceptRoute(Uri.parse('/search?q=test'));
      workspace.goBack(closeCurrent: true);
      expect(workspace.activeId, video.id);
      expect(workspace.tabs.map((tab) => tab.id), contains(search.id));
      workspace.goBack(closeCurrent: true);
      expect(workspace.activeId, search.id);
      expect(workspace.tabs.map((tab) => tab.id), isNot(contains(video.id)));
      workspace.goBack(closeCurrent: true);
      expect(workspace.tabs, hasLength(1));
      expect(workspace.goBack(closeCurrent: true), isFalse);
    },
  );

  test('closing a page removes stale visits from back history', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/search?q=test'));
    final search = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/settings'));
    workspace.select(search);
    workspace.close(search);
    expect(workspace.activeId, 'home');
    workspace.goBack();
    expect(workspace.active.location.path, '/settings');
    workspace.goBack();
    expect(workspace.activeId, 'home');
    expect(workspace.canGoBack, isFalse);
  });

  test('single-page browsing evicts old pages and remains bounded past 16', () {
    final workspace = WorkspaceTabs();
    for (var i = 0; i < 40; i++) {
      expect(
        workspace.acceptRoute(Uri.parse('/search?q=$i'), singlePage: true),
        isTrue,
      );
    }
    expect(workspace.tabs, hasLength(WorkspaceTabs.maximumTabs));
    expect(workspace.active.location.queryParameters['q'], '39');
    expect(workspace.tabs.first.id, 'home');
    var backCount = 0;
    while (workspace.goBack(closeCurrent: true)) {
      backCount++;
    }
    expect(backCount, WorkspaceTabs.maximumTabs - 1);
    expect(workspace.activeId, 'home');
    expect(workspace.tabs, hasLength(1));
  });

  test('repeated tab selection has a bounded navigation history', () {
    final workspace = WorkspaceTabs();
    final browse = workspace.addBrowseTab();
    for (var i = 0; i < 100; i++) {
      workspace.select(i.isEven ? 'home' : browse.id);
    }
    var backCount = 0;
    while (workspace.goBack()) {
      backCount++;
    }
    expect(backCount, WorkspaceTabs.maximumHistory);
  });

  test('messages open and reuse their own tab while keeping the video tab', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
    final video = workspace.active.id;
    workspace.acceptRoute(Uri.parse('/messages'));
    final messages = workspace.active.id;
    expect(workspace.active.title, '我的消息');
    workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
    expect(workspace.active.id, video);
    workspace.acceptRoute(Uri.parse('/messages'));
    expect(workspace.active.id, messages);
    expect(workspace.tabs, hasLength(3));
  });
  test('user spaces reuse their tab by UID and preserve the video tab', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
    final videoTab = workspace.active.id;
    workspace.acceptRoute(Uri.parse('/user/9007199254740993'));
    final userTab = workspace.active.id;
    expect(workspace.active.isProfile, isTrue);
    expect(workspace.active.title, '用户主页 · 9007199254740993');
    expect(workspace.tabs.length, 3);
    workspace.acceptRoute(Uri.parse('/user/42'));
    expect(workspace.active.id, isNot(userTab));
    workspace.acceptRoute(Uri.parse('/user/9007199254740993'));
    expect(workspace.active.id, userTab);
    expect(workspace.tabs.length, 4);
    workspace.close(userTab);
    expect(workspace.active.id, videoTab);
  });

  test(
    'pinned home, distinct browse tabs, query identity and adjacent close',
    () {
      final workspace = WorkspaceTabs();
      expect(workspace.close('home'), isFalse);
      final browse = workspace.addBrowseTab();
      expect(browse.id, isNot('home'));
      workspace.acceptRoute(Uri.parse('/search?q=猫'));
      final firstSearch = workspace.active;
      workspace.acceptRoute(Uri.parse('/search?q=狗'));
      final secondSearch = workspace.active;
      expect(secondSearch.id, isNot(firstSearch.id));
      workspace.acceptRoute(Uri.parse('/search?q=猫'));
      expect(workspace.activeId, firstSearch.id);
      expect(workspace.tabs.length, 4);
      workspace.close(firstSearch.id);
      expect(workspace.activeId, browse.id);
      workspace.acceptRoute(Uri.parse('/'));
      expect(workspace.activeId, 'home');
      expect(workspace.tabs.length, 3);
    },
  );

  test(
    'tab routes retain identity and a deep link cannot replace pinned home',
    () {
      final workspace = WorkspaceTabs();
      final browse = workspace.addBrowseTab();
      workspace.acceptRoute(Uri.parse('/?channel=popular&tab=${browse.id}'));
      expect(workspace.activeId, browse.id);
      expect(workspace.active.location.queryParameters['channel'], 'popular');
      expect(
        workspace.active.location.queryParameters.containsKey('tab'),
        isFalse,
      );
      workspace.acceptRoute(Uri.parse('/video/BV1234567890?tab=home'));
      expect(workspace.tabs.first.isBrowse, isTrue);
      expect(workspace.active.isVideo, isTrue);
      workspace.cycle();
      expect(workspace.activeId, 'home');
      workspace.cycle(backwards: true);
      expect(workspace.active.isVideo, isTrue);
    },
  );

  test('feature navigation respects workspace capacity', () {
    final workspace = WorkspaceTabs();
    for (var index = 0; index < 40; index++) {
      workspace.acceptRoute(Uri.parse('/search?q=query$index'));
    }
    expect(workspace.tabs.length, WorkspaceTabs.maximumTabs);
    expect(workspace.tabs.first.pinned, isTrue);
    expect(workspace.active.location.queryParameters['q'], 'query14');
  });
}
