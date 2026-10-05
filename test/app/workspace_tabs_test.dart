import 'package:bilisail/app/workspace_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
