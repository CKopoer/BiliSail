import 'package:bilisail/app/workspace_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latest playback follows visits and falls back when pages close', () {
    final workspace = WorkspaceTabs();
    expect(workspace.latestPlayback, isNull);
    final media = <WorkspaceTab>[];
    for (final route in ['/video/A', '/pgc/42', '/live/12', '/offline/task']) {
      workspace.acceptRoute(Uri.parse(route));
      media.add(workspace.active);
      expect(workspace.latestPlayback?.id, media.last.id);
    }
    workspace.select(media.first.id);
    workspace.acceptRoute(Uri.parse('/?channel=dynamic'));
    expect(workspace.latestPlayback?.id, media.first.id);
    // A background source update is not a visit to that media page.
    workspace.updateLocation(media.last.id, Uri.parse('/offline/next'));
    expect(workspace.latestPlayback?.id, media.first.id);
    for (final tab in [media.first, ...media.skip(1).toList().reversed]) {
      expect(workspace.latestPlayback?.id, tab.id);
      expect(workspace.close(tab.id), isTrue);
    }
    expect(workspace.latestPlayback, isNull);
  });

  test('latest playback survives root navigation and bounded Back history', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/video/A'));
    final first = workspace.active;
    workspace.acceptRoute(Uri.parse('/video/B'));
    final second = workspace.active;
    workspace.select(first.id);
    workspace.acceptRoute(Uri.parse('/?channel=dynamic'));
    for (var index = 0; index < WorkspaceTabs.maximumHistory * 2; index++) {
      workspace.acceptRoute(Uri.parse('/user/${index % 2}'));
    }
    expect(workspace.latestPlayback?.id, first.id);
    expect(workspace.close(first.id), isTrue);
    expect(workspace.latestPlayback?.id, second.id);
    workspace.setSingleMode(false);
    workspace.setDualMode(true);
    expect(workspace.playbackId, second.id);
    expect(workspace.latestPlayback?.id, second.id);
  });

  test('Back and closing the selected tab count as playback visits', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/video/A'));
    final first = workspace.active;
    workspace.acceptRoute(Uri.parse('/video/B'));
    final second = workspace.active;
    expect(workspace.goBack(), isTrue);
    expect(workspace.latestPlayback?.id, first.id);
    workspace.select(second.id);
    workspace.acceptRoute(Uri.parse('/user/42'));
    expect(workspace.close(workspace.activeId), isTrue);
    expect(workspace.activeId, second.id);
    expect(workspace.latestPlayback?.id, second.id);
  });

  test('single player Home closes media and restores the entry search', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/?channel=popular'));
    workspace.acceptRoute(Uri.parse('/search?q=cat'));
    final entry = workspace.active;
    workspace.acceptRoute(Uri.parse('/video/A'));
    workspace.acceptRoute(Uri.parse('/user/42'));
    workspace.acceptRoute(Uri.parse('/video/B'));
    for (var index = 0; index < 100; index++) {
      workspace.acceptRoute(Uri.parse(index.isEven ? '/user/42' : '/video/B'));
    }
    workspace.returnFromPlayback();
    expect(workspace.activeId, entry.id);
    expect(workspace.active.location, entry.location);
    expect(workspace.tabs.where((tab) => tab.isPlayback), isEmpty);
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.location, Uri.parse('/?channel=popular'));
  });

  test('single player Home protects its entry page at capacity', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/search?q=cat'));
    final entry = workspace.active;
    workspace.acceptRoute(Uri.parse('/video/A'));
    for (var index = 0; index < 40; index++) {
      workspace.acceptRoute(Uri.parse('/user/$index'));
    }
    workspace.acceptRoute(Uri.parse('/video/B'));
    workspace.returnFromPlayback();
    expect(workspace.activeId, entry.id);
    expect(workspace.tabs.where((tab) => tab.isPlayback), isEmpty);
  });

  test('dual player Home preserves media and the browsing destination', () {
    final workspace = WorkspaceTabs()..setDualMode(true);
    workspace.acceptRoute(Uri.parse('/search?q=cat'));
    final entry = workspace.active;
    workspace.acceptRoute(Uri.parse('/video/A'));
    workspace.acceptRoute(Uri.parse('/video/B'));
    final media = workspace.active;
    final history = workspace.playbackHistory;
    workspace.returnFromPlayback();
    expect(workspace.activeId, entry.id);
    expect(workspace.tabs, contains(media));
    expect(workspace.playbackHistory, history);
    expect(workspace.playbackId, media.id);
  });

  test('multiple player Home opens the home root and retains media tabs', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/me'));
    workspace.acceptRoute(Uri.parse('/video/A'));
    workspace.acceptRoute(Uri.parse('/video/B'));
    final media = workspace.tabs.where((tab) => tab.isPlayback).toList();
    workspace.returnFromPlayback();
    expect(workspace.activeId, 'home');
    expect(workspace.active.location.path, '/');
    expect(workspace.tabs, containsAll(media));
  });

  test('single page can always return home after bounded repeated visits', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/video/A'));
    for (var index = 0; index < 100; index++) {
      workspace.acceptRoute(Uri.parse(index.isEven ? '/user/42' : '/video/A'));
    }
    var count = 0;
    while (workspace.canGoBack) {
      final destination = workspace.backDestination();
      expect(workspace.goBack(), isTrue);
      expect(workspace.active.id, destination?.id);
      count++;
      expect(count, lessThanOrEqualTo(WorkspaceTabs.maximumHistory + 1));
    }
    expect(workspace.activeId, 'home');
    expect(workspace.tabs, hasLength(1));
  });

  for (final media in [
    '/video/A?cid=2',
    '/pgc/episode/3',
    '/live/42',
    '/offline/task',
  ]) {
    test(
      'single page returns through spaces to $media and releases popped pages',
      () {
        final workspace = WorkspaceTabs()..setSingleMode(true);
        workspace.acceptRoute(Uri.parse(media));
        final playback = workspace.active;
        workspace.acceptRoute(Uri.parse('/user/42'));
        final profile = workspace.active;
        workspace.acceptRoute(Uri.parse('/search?q=cat'));
        final search = workspace.active;
        expect(workspace.backDestination()?.id, profile.id);
        expect(workspace.goBack(), isTrue);
        expect(workspace.active.id, profile.id);
        expect(workspace.tabs.map((tab) => tab.id), isNot(contains(search.id)));
        workspace.acceptRoute(workspace.active.route);
        expect(workspace.backDestination()?.id, playback.id);
        expect(workspace.goBack(), isTrue);
        expect(workspace.active.location, playback.location);
        expect(workspace.active.id, playback.id);
        expect(
          workspace.tabs.map((tab) => tab.id),
          isNot(contains(profile.id)),
        );
        expect(
          workspace.updateLocation(profile.id, Uri.parse('/user/99')),
          isFalse,
        );
        expect(workspace.goBack(), isTrue);
        expect(workspace.activeId, 'home');
        expect(workspace.tabs, hasLength(1));
        expect(workspace.canGoBack, isFalse);
      },
    );
  }

  test('single page keeps repeated visits until their last pop', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/video/A?cid=2'));
    final first = workspace.active;
    workspace.acceptRoute(Uri.parse('/user/42'));
    final profile = workspace.active;
    workspace.acceptRoute(Uri.parse('/video/B'));
    final second = workspace.active;
    workspace.acceptRoute(profile.location);
    expect(workspace.active.id, profile.id);
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.id, second.id);
    expect(workspace.tabs.map((tab) => tab.id), contains(profile.id));
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.id, profile.id);
    expect(workspace.tabs.map((tab) => tab.id), isNot(contains(second.id)));
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.id, first.id);
    expect(workspace.active.location.queryParameters['cid'], '2');
    expect(workspace.tabs, hasLength(2));
  });

  test('single page bounds its cache and preserves the last playback behind spaces', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/video/A'));
    final playback = workspace.activeId;
    for (var index = 0; index < 80; index++) {
      expect(workspace.acceptRoute(Uri.parse('/user/$index')), isTrue);
    }
    expect(workspace.tabs, hasLength(WorkspaceTabs.maximumTabs));
    var backs = 0;
    while (!workspace.active.isPlayback && workspace.goBack()) {
      backs++;
    }
    expect(backs, WorkspaceTabs.maximumTabs - 2);
    expect(workspace.activeId, playback);
    expect(workspace.goBack(), isTrue);
    expect(workspace.tabs, hasLength(1));
  });

  test('history selects the fixed root tab instead of opening a page tab', () {
    final workspace = WorkspaceTabs();
    for (var trip = 0; trip < 3; trip++) {
      workspace.acceptRoute(Uri.parse('/history'));
      expect(workspace.activeId, 'home', reason: 'trip $trip history');
      expect(workspace.active.location.path, '/history');
      expect(workspace.tabs, hasLength(1), reason: 'trip $trip history');
      for (final location in [
        '/?channel=recommended&tab=home',
        '/me',
        '/downloads',
      ]) {
        workspace.acceptRoute(Uri.parse(location));
        expect(workspace.tabs, hasLength(1), reason: location);
      }
    }
    // Primary selections share one identity, so none of the trips above pushed
    // a visit and Back cannot bounce between 首页 and 历史.
    expect(workspace.canGoBack, isFalse);
    // Detail pages keep owning a closable tab.
    workspace.acceptRoute(Uri.parse('/user/42'));
    expect(workspace.tabs, hasLength(2));
  });

  test('switching from dual to single keeps media history before consuming the page', () {
    final workspace = WorkspaceTabs()..setDualMode(true);
    workspace.acceptRoute(Uri.parse('/video/A?cid=2'));
    final playback = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/video/B'));
    workspace.setDualMode(false);
    workspace.setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/user/42'));
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, playback);
    expect(workspace.active.location.path, '/video/B');
    expect(workspace.backDestination()?.location, Uri.parse('/video/A?cid=2'));
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, playback);
    expect(workspace.active.location, Uri.parse('/video/A?cid=2'));
    expect(workspace.goBack(), isTrue);
    expect(workspace.tabs, hasLength(1));
  });

  test('single page treats root selection and same-page changes as history boundaries', () {
    final workspace = WorkspaceTabs()..setSingleMode(true);
    workspace.acceptRoute(Uri.parse('/video/A'));
    final playback = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/video/A?cid=2&tab=$playback'));
    workspace.acceptRoute(Uri.parse('/user/42'));
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.location.queryParameters['cid'], '2');
    workspace.acceptRoute(Uri.parse('/settings'));
    expect(workspace.canGoBack, isFalse);
    workspace.acceptRoute(Uri.parse('/settings?section=playback&tab=home'));
    workspace.acceptRoute(Uri.parse('/user/43'));
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.location.path, '/settings');
    expect(workspace.canGoBack, isFalse);
  });

  for (final dual in [true, false]) {
    test(
      'Back previews match commits without consuming history in dual=$dual',
      () {
        final workspace = WorkspaceTabs()..setDualMode(dual);
        for (final location in [
          '/history',
          '/user/42',
          '/video/A',
          '/video/B',
        ]) {
          workspace.acceptRoute(Uri.parse(location));
        }
        while (workspace.canGoBack) {
          final current = workspace.active;
          final tabs = workspace.tabs;
          final preview = workspace.backDestination();
          expect(preview, isNotNull);
          expect(workspace.active, same(current));
          expect(workspace.tabs, tabs);
          expect(workspace.backDestination()?.location, preview?.location);
          expect(workspace.goBack(), isTrue);
          expect(workspace.active.id, preview?.id);
          expect(workspace.active.location, preview?.location);
        }
        expect(workspace.backDestination(), isNull);
      },
    );

    test('inbox preview restores root identity in dual=$dual', () {
      final workspace = WorkspaceTabs()..setDualMode(dual);
      workspace.acceptRoute(Uri.parse('/settings?section=shortcuts'));
      workspace.acceptRoute(Uri.parse('/messages'));
      final preview = workspace.backDestination(fromMessages: true);
      expect(workspace.active.isMessages, isTrue);
      expect(preview?.location.toString(), '/settings?section=shortcuts');
      expect(workspace.returnFromMessages(), isTrue);
      expect(workspace.active.location, preview?.location);
    });
  }

  test('inbox Back to playback keeps its browsing slot and media history', () {
    final workspace = WorkspaceTabs()..setDualMode(true);
    workspace.acceptRoute(Uri.parse('/search?q=cat'));
    final search = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/video/A'));
    workspace.acceptRoute(Uri.parse('/video/B'));
    final playback = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/messages'));
    expect(workspace.returnFromMessages(), isTrue);
    expect(workspace.activeId, playback);
    expect(workspace.active.location.path, '/video/B');
    expect(workspace.browseId, search);
    expect(workspace.goBack(), isTrue);
    expect(workspace.active.location.path, '/video/A');
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, search);
  });

  for (final dual in [true, false]) {
    test('inbox Back restores its root entry and query in dual=$dual', () {
      final workspace = WorkspaceTabs()..setDualMode(dual);
      for (final route in [
        '/?channel=popular&section=每周必看',
        '/settings?section=shortcuts',
        '/me',
      ]) {
        workspace.acceptRoute(Uri.parse(route));
        final origin = workspace.active.location;
        workspace.acceptRoute(Uri.parse('/messages?talker=2'));
        workspace.acceptRoute(Uri.parse('/messages?tab=home'));
        expect(workspace.canReturnFromMessages, isTrue);
        expect(workspace.returnFromMessages(), isTrue);
        expect(workspace.active.location, origin);
        expect(workspace.activeId, 'home');
        expect(workspace.tabs, hasLength(1));
        expect(workspace.canReturnFromMessages, isFalse);
        expect(workspace.returnFromMessages(), isFalse);
        expect(workspace.goBack(), isFalse);
      }
    });

    test(
      'inbox Back restores the entry page and its history in dual=$dual',
      () {
        final workspace = WorkspaceTabs()..setDualMode(dual);
        final root = Uri.parse('/?channel=videoDynamic');
        workspace.acceptRoute(root);
        workspace.acceptRoute(Uri.parse('/search?q=cat'));
        final search = workspace.active;
        workspace.acceptRoute(Uri.parse('/user/42'));
        final profile = workspace.active;
        workspace.acceptRoute(Uri.parse('/messages?talker=42'));
        workspace.acceptRoute(Uri.parse('/messages'));
        expect(workspace.returnFromMessages(), isTrue);
        expect(workspace.activeId, profile.id);
        expect(workspace.tabs.first.location, root);
        workspace.acceptRoute(workspace.active.route);
        expect(workspace.goBack(), isTrue);
        expect(workspace.activeId, search.id);
        expect(workspace.goBack(), isTrue);
        expect(workspace.active.location, root);
        expect(workspace.canReturnFromMessages, isFalse);
        expect(workspace.goBack(), isFalse);
      },
    );

    test('inbox Back never recreates a closed entry page in dual=$dual', () {
      final workspace = WorkspaceTabs()..setDualMode(dual);
      workspace.acceptRoute(Uri.parse('/me'));
      workspace.acceptRoute(Uri.parse('/search?q=cat'));
      final search = workspace.activeId;
      workspace.acceptRoute(Uri.parse('/messages'));
      expect(workspace.close(search), isTrue);
      expect(workspace.returnFromMessages(), isTrue);
      expect(workspace.active.location.path, '/me');
      expect(workspace.tabs, hasLength(1));
      expect(workspace.goBack(), isFalse);
    });

    test(
      'a profile starting another chat cannot loop into inbox in dual=$dual',
      () {
        final workspace = WorkspaceTabs()..setDualMode(dual);
        workspace.acceptRoute(Uri.parse('/messages'));
        workspace.acceptRoute(Uri.parse('/user/42'));
        final profile = workspace.activeId;
        workspace.acceptRoute(Uri.parse('/messages?talker=42'));
        expect(workspace.returnFromMessages(), isTrue);
        expect(workspace.activeId, profile);
        expect(workspace.goBack(), isTrue);
        expect(workspace.active.location.path, '/');
        expect(workspace.goBack(), isFalse);
      },
    );
  }

  test('desktop browser back skips playback visits and keeps the player', () {
    final workspace = WorkspaceTabs()..setDualMode(true);
    workspace.acceptRoute(Uri.parse('/search?q=cat'));
    final search = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/video/A'));
    final playback = workspace.activeId;
    // A profile is a transient browsing visit; /history now shares the fixed
    // root tab and would not exercise the skip-and-close path.
    workspace.acceptRoute(Uri.parse('/user/7'));
    final profile = workspace.activeId;
    expect(workspace.canGoBackBrowsing, isTrue);
    expect(workspace.goBackBrowsing(), isTrue);
    expect(workspace.activeId, search);
    expect(workspace.tabs.map((tab) => tab.id), isNot(contains(profile)));
    expect(workspace.playbackId, playback);
    expect(
      workspace.tabs.where((tab) => tab.id == playback).single.location.path,
      '/video/A',
    );
    expect(workspace.goBackBrowsing(), isTrue);
    expect(workspace.activeId, 'home');
    expect(workspace.tabs.map((tab) => tab.id), isNot(contains(search)));
    expect(workspace.goBackBrowsing(), isFalse);
  });

  test(
    'dual slots reuse media, back restores URI and close returns to browsing',
    () {
      final workspace = WorkspaceTabs()..setDualMode(true);
      workspace.acceptRoute(Uri.parse('/search?q=cat'));
      final browse = workspace.active;
      workspace.acceptRoute(Uri.parse('/video/A?cid=2&queue=test'));
      final playback = workspace.active.id;
      workspace.acceptRoute(Uri.parse('/video/B'));
      workspace.acceptRoute(Uri.parse('/pgc/episode/3'));
      expect(workspace.visibleTabs.map((tab) => tab.id), [browse.id, playback]);
      expect(workspace.tabs, hasLength(3));
      expect(workspace.goBack(), isTrue);
      expect(workspace.active.location.path, '/video/B');
      // Committing the selected route must not reinsert the item just popped.
      workspace.acceptRoute(workspace.active.route);
      expect(workspace.goBack(), isTrue);
      expect(workspace.active.location, Uri.parse('/video/A?cid=2&queue=test'));
      expect(workspace.close(playback), isTrue);
      expect(workspace.active, same(browse));
      expect(workspace.visibleTabs, hasLength(1));
      expect(workspace.close(browse.id), isFalse);
    },
  );

  test(
    'dual history ignores advancement and rejects an obsolete page callback',
    () {
      final workspace = WorkspaceTabs()..setDualMode(true);
      workspace.acceptRoute(Uri.parse('/video/A'));
      final first = workspace.active;
      workspace.acceptRoute(Uri.parse('/video/B'));
      expect(
        workspace.updateLocation(
          first.id,
          Uri.parse('/video/stale'),
          expectedLocation: first.location,
        ),
        isFalse,
      );
      workspace.updateLocation(first.id, Uri.parse('/video/C?queue=test'));
      workspace.goBack();
      expect(workspace.active.location.path, '/video/A');
      workspace.goBack();
      expect(workspace.active.id, 'home');
      expect(workspace.playbackId, isNull);
      expect(workspace.tabs.map((tab) => tab.id), isNot(contains(first.id)));
      workspace.cycle();
      expect(workspace.active.id, 'home');
      expect(
        workspace.updateLocation(first.id, Uri.parse('/video/late')),
        isFalse,
      );
      workspace.acceptRoute(Uri.parse('/video/fresh'));
      expect(workspace.active.id, isNot(first.id));
      workspace.goBack();
      expect(workspace.active.id, 'home');
    },
  );

  test(
    'mode changes retain old tabs and dual history and browsing are bounded',
    () {
      final workspace = WorkspaceTabs();
      workspace.acceptRoute(Uri.parse('/video/old'));
      final old = workspace.active;
      workspace.acceptRoute(Uri.parse('/video/current'));
      workspace.setDualMode(true);
      for (var index = 0; index < 40; index++) {
        workspace.acceptRoute(Uri.parse('/video/$index'));
        workspace.acceptRoute(Uri.parse('/search?q=$index'));
      }
      expect(workspace.tabs, hasLength(WorkspaceTabs.maximumTabs));
      expect(workspace.visibleTabs, hasLength(2));
      workspace.select(workspace.playbackId!);
      var count = 0;
      while (workspace.active.isPlayback) {
        workspace.goBack();
        count++;
      }
      expect(count, WorkspaceTabs.maximumTabs + 1);
      // Capacity eviction is permitted; mode changes themselves never discard.
      workspace.setDualMode(false);
      expect(workspace.visibleTabs, workspace.tabs);
      expect(workspace.tabs.where((tab) => tab.id == old.id), isEmpty);
    },
  );

  test('switching modes alone preserves all retained pages and selection', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/video/A'));
    workspace.acceptRoute(Uri.parse('/video/B'));
    workspace.acceptRoute(Uri.parse('/search?q=keep'));
    final before = workspace.tabs;
    final active = workspace.active;
    workspace.setDualMode(true);
    expect(workspace.visibleTabs, hasLength(2));
    workspace.setDualMode(false);
    expect(workspace.tabs, before);
    expect(workspace.active, same(active));
  });
  test(
    'profile recipients reuse the inbox and consume intent without a visit',
    () {
      final workspace = WorkspaceTabs();
      workspace.acceptRoute(Uri.parse('/messages'));
      final inboxId = workspace.activeId;
      workspace.acceptRoute(Uri.parse('/user/2'));
      final profileId = workspace.activeId;
      workspace.acceptRoute(Uri.parse('/messages?talker=2'));
      expect(workspace.activeId, inboxId);
      expect(workspace.tabs, hasLength(2));
      expect(workspace.active.location.queryParameters['talker'], '2');
      workspace.acceptRoute(Uri.parse('/messages?tab=$inboxId'));
      expect(workspace.goBack(), isFalse);
      expect(workspace.activeId, 'home');
      expect(workspace.tabs.map((tab) => tab.id), contains(profileId));
    },
  );
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

  test('settings categories stay on the primary root without a visit', () {
    final workspace = WorkspaceTabs();
    workspace.acceptRoute(Uri.parse('/?channel=bangumi&tab=home'));
    workspace.acceptRoute(Uri.parse('/settings'));
    workspace.acceptRoute(
      Uri.parse('/settings?section=playback&tab=${workspace.activeId}'),
    );
    expect(workspace.goBack(), isFalse);
    expect(workspace.active.location.queryParameters['section'], 'playback');
    expect(workspace.canGoBack, isFalse);
    expect(workspace.tabs, hasLength(1));
  });

  test(
    'workspace back keeps repeated destinations and their retained pages',
    () {
      final workspace = WorkspaceTabs();
      workspace.acceptRoute(Uri.parse('/search?q=test'));
      final search = workspace.active;
      workspace.acceptRoute(Uri.parse('/video/BV1234567890'));
      final video = workspace.active;
      workspace.acceptRoute(Uri.parse('/search?q=test'));
      workspace.goBack();
      expect(workspace.activeId, video.id);
      expect(workspace.tabs.map((tab) => tab.id), contains(search.id));
      workspace.goBack();
      expect(workspace.activeId, search.id);
      expect(workspace.tabs.map((tab) => tab.id), contains(video.id));
      workspace.goBack();
      expect(workspace.tabs, hasLength(3));
      expect(workspace.goBack(), isFalse);
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
    expect(workspace.goBack(), isFalse);
    expect(workspace.active.location.path, '/settings');
    expect(workspace.activeId, 'home');
    expect(workspace.canGoBack, isFalse);
  });

  test('dual browsing evicts old pages and remains bounded past 16', () {
    final workspace = WorkspaceTabs()..setDualMode(true);
    for (var i = 0; i < 40; i++) {
      expect(workspace.acceptRoute(Uri.parse('/search?q=$i')), isTrue);
    }
    expect(workspace.tabs, hasLength(WorkspaceTabs.maximumTabs));
    expect(workspace.active.location.queryParameters['q'], '39');
    expect(workspace.tabs.first.id, 'home');
    var backCount = 0;
    while (workspace.goBack()) {
      backCount++;
    }
    expect(backCount, WorkspaceTabs.maximumTabs - 1);
    expect(workspace.activeId, 'home');
    expect(workspace.tabs, hasLength(1));
  });

  test('all primary routes share the protected root without visits', () {
    final workspace = WorkspaceTabs();
    for (final route in [
      '/me',
      '/messages?talker=2&tab=old-inbox',
      '/downloads?tab=old-downloads',
      '/settings?section=shortcuts&tab=old-settings',
      '/?channel=popular&section=每周必看',
      '/me?tab=obsolete',
      '/?channel=live&section=我的关注&tab=home',
    ]) {
      workspace.acceptRoute(Uri.parse(route));
      expect(workspace.activeId, 'home');
      expect(workspace.active.isRoot, isTrue);
      expect(workspace.active.pinned, isTrue);
      expect(workspace.tabs, hasLength(1));
      expect(workspace.canGoBack, isFalse);
      expect(workspace.close('home'), isFalse);
    }
    expect(workspace.updateLocation('home', Uri.parse('/me')), isTrue);
    expect(workspace.active.isAccount, isTrue);
    expect(workspace.active.title, '我的');
    expect(workspace.updateLocation('home', Uri.parse('/user/2')), isFalse);
    final browse = workspace.addBrowseTab();
    workspace.acceptRoute(Uri.parse('/?channel=popular&tab=${browse.id}'));
    expect(workspace.activeId, browse.id);
    expect(workspace.active.pinned, isFalse);
    workspace.acceptRoute(Uri.parse('/me?tab=${browse.id}'));
    expect(workspace.activeId, 'home');
    expect(workspace.tabs, hasLength(2));
  });

  test('dual Back consumes transient pages and falls back to the My root', () {
    final workspace = WorkspaceTabs()..setDualMode(true);
    workspace.acceptRoute(Uri.parse('/me'));
    workspace.acceptRoute(Uri.parse('/search?q=keep'));
    final search = workspace.activeId;
    workspace.acceptRoute(Uri.parse('/user/42'));
    final profile = workspace.activeId;
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, search);
    expect(workspace.tabs.map((tab) => tab.id), isNot(contains(profile)));
    expect(workspace.updateLocation(profile, Uri.parse('/user/43')), isFalse);
    expect(workspace.goBack(), isTrue);
    expect(workspace.activeId, 'home');
    expect(workspace.active.isAccount, isTrue);
    expect(workspace.tabs, hasLength(1));
    expect(workspace.goBack(), isFalse);
    workspace.setDualMode(false);
    expect(workspace.goBack(), isFalse);
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

  test('messages reuse the fixed root while keeping the video tab', () {
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
    workspace.acceptRoute(Uri.parse('/messages?tab=$video'));
    expect(workspace.activeId, 'home');
    expect(workspace.tabs.firstWhere((tab) => tab.id == video).isVideo, isTrue);
    expect(messages, 'home');
    expect(workspace.tabs, hasLength(2));
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
