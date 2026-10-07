import 'package:bilisail/features/video/application/video_author_controller.dart';

import '../support/follow_repository_fake.dart';

import '../support/input_test_app.dart';

import 'dart:async';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';

import '../features/messages/message_fakes.dart';

import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_screen.dart';
import 'package:bilisail/features/live/application/live_controller.dart';
import 'package:bilisail/features/live/domain/live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/live/presentation/live_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/search/application/search_controller.dart';
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_screen.dart';
import 'package:bilisail/features/search/presentation/search_category_bar.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'profile private messages reuse inbox and drafts in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(375, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final auth = AuthFake();
        final messages = MessageRepositoryFake();
        final settings = _SettingsRepository()
          ..settings = const AppSettings.defaults().copyWith(
            navigationMode: mode,
          );
        final router = createBiliRouter(
          initialLocation: '/user/2',
          playerBuilder: (_, _, _) => const SizedBox(),
          accountBuilder: (_) => const SizedBox(),
        );
        addTearDown(() async {
          router.dispose();
          await auth.stream.close();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              settingsRepositoryProvider.overrideWithValue(settings),
              profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
              videoAuthorRepositoryProvider.overrideWithValue(
                FollowRepositoryFake()..accountScope = 'user:1',
              ),
              messageRepositoryProvider.overrideWithValue(messages),
              feedRepositoryProvider.overrideWithValue(_FeedRepository()),
              homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            ],
            child: InputTestApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('profile-message')));
        await tester.pumpAndSettle();
        expect(find.text('我的消息'), findsWidgets);
        final inbox = ProviderScope.containerOf(
          tester.element(find.byType(MessagesScreen)),
        );
        expect(
          inbox.read(messagesControllerProvider).selected?.userId,
          const UserId('2'),
        );
        expect(
          router.routeInformationProvider.value.uri.queryParameters.containsKey(
            'talker',
          ),
          isFalse,
        );
        final composer = find.widgetWithText(TextField, '输入私信消息');
        await tester.enterText(composer, '用户2草稿');
        router.go('/user/3493276401272849');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('profile-message')));
        await tester.pumpAndSettle();
        expect(
          ProviderScope.containerOf(
            tester.element(find.byType(MessagesScreen)),
          ),
          same(inbox),
        );
        expect(
          inbox.read(messagesControllerProvider).selected?.userId,
          const UserId('3493276401272849'),
        );
        expect(
          inbox.read(messagesControllerProvider).selected?.title,
          '用户3493276401272849',
        );
        expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
        router.go('/user/2');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('profile-message')));
        await tester.pumpAndSettle();
        expect(
          inbox.read(messagesControllerProvider).selected?.userId,
          const UserId('2'),
        );
        expect(tester.widget<TextField>(composer).controller?.text, '用户2草稿');
        expect(messages.sends + messages.marks, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'search header shares its tab state and preserves categories in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final settings = _SettingsRepository()
          ..settings = const AppSettings.defaults().copyWith(
            navigationMode: mode,
          );
        final search = _SearchRepository(
          countsByQuery: const {
            'cat': {SearchCategory.video: 123, SearchCategory.user: 0},
            'dog': {SearchCategory.video: 2},
          },
        );
        final router = createBiliRouter(
          initialLocation: '/search?q=cat',
          playerBuilder: (_, _, _) => const SizedBox(),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settings),
              searchRepositoryProvider.overrideWithValue(search),
              feedRepositoryProvider.overrideWithValue(_FeedRepository()),
              homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            ],
            child: InputTestApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        final root = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
          listen: false,
        );
        ProviderContainer tabScope() => ProviderScope.containerOf(
          tester.element(find.byType(SearchScreen)),
          listen: false,
        );
        final catScope = tabScope();
        expect(root.read(searchControllerProvider).query, isEmpty);
        expect(find.byKey(const ValueKey('home-channel-strip')), findsNothing);
        expect(find.byType(SearchCategoryBar), findsOneWidget);
        expect(find.text('99+'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SearchScreen),
            matching: find.byKey(const ValueKey('search-category-video')),
          ),
          findsNothing,
        );
        await tester.tap(find.text('最多收藏'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-more-filters')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('60分钟以上'));
        await tester.pumpAndSettle();
        final priorSignal = search.cancellations.last;
        await tester.tap(find.byKey(const ValueKey('search-category-user')));
        await tester.pumpAndSettle();
        expect(priorSignal.isCancelled, isTrue);
        expect(search.calls.last, (
          query: 'cat',
          page: 1,
          category: SearchCategory.user,
          order: SearchOrder.relevance,
          duration: SearchDuration.any,
          userType: SearchUserType.any,
        ));
        expect(
          catScope.read(searchControllerProvider).category,
          SearchCategory.user,
        );
        expect(find.text('全部用户'), findsNothing);
        expect(find.text('粉丝数由高到低'), findsOneWidget);
        expect(
          router.routeInformationProvider.value.uri.queryParameters['q'],
          'cat',
        );
        expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
        router.go('/search?q=dog');
        await tester.pumpAndSettle();
        expect(identical(catScope, tabScope()), isFalse);
        expect(
          tabScope().read(searchControllerProvider).category,
          SearchCategory.all,
        );
        expect(find.text('99+'), findsNothing);
        expect(find.text('2'), findsOneWidget);
        final callsBeforeReturn = search.calls.length;
        if (mode == WorkspaceNavigationMode.singlePage) {
          await tester.tap(find.byKey(const ValueKey('workspace-back')));
        } else {
          await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
        }
        await tester.pumpAndSettle();
        expect(identical(catScope, tabScope()), isTrue);
        expect(catScope.read(searchControllerProvider).query, 'cat');
        expect(
          catScope.read(searchControllerProvider).category,
          SearchCategory.user,
        );
        expect(find.text('99+'), findsOneWidget);
        expect(find.text('粉丝数由高到低'), findsOneWidget);
        expect(search.calls.length, callsBeforeReturn);
        expect(root.read(searchControllerProvider).query, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets(
      'video tag opens search in $mode and retains the part',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const tag = 'Flutter & Dart/中文+测试';
        final search = _SearchRepository();
        final settings = _SettingsRepository();
        settings.settings = settings.settings.copyWith(navigationMode: mode);
        var created = 0;
        final router = createBiliRouter(
          initialLocation: '/video/BV1234567890?cid=2',
          playerBuilder: (_, _, part) =>
              _TagTestPlayer(part: part, onCreate: () => created++),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settings),
              videoRepositoryProvider.overrideWithValue(_VideoRepository()),
              videoTagsProvider.overrideWith((ref, id) async => [tag]),
              relatedVideosProvider.overrideWith((ref, id) async => []),
              searchRepositoryProvider.overrideWithValue(search),
              feedRepositoryProvider.overrideWithValue(_FeedRepository()),
              homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            ],
            child: InputTestApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('播放 第二集'), findsOneWidget);
        await tester.tap(find.widgetWithText(ActionChip, tag));
        await tester.pumpAndSettle();
        expect(search.queries, [tag]);
        final uri = router.routeInformationProvider.value.uri;
        expect(uri.path, '/search');
        expect(uri.queryParameters['q'], tag);
        expect(find.text('“$tag” 的搜索结果'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('播放 第二集'), findsOneWidget);
        expect(created, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    _workspaceTestWidgets(
      '$platform uses its default while loading and preserves a saved override',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(420, 850);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = _PendingSettingsRepository();
        final router = createBiliRouter(
          playerBuilder: (_, _, _) => const SizedBox(),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settings),
              feedRepositoryProvider.overrideWithValue(_FeedRepository()),
              homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            ],
            child: InputTestApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        final singlePage =
            workspaceNavigationModeForPlatform(platform) ==
            WorkspaceNavigationMode.singlePage;
        expect(
          find.byKey(const ValueKey('workspace-tab-strip')),
          singlePage ? findsNothing : findsOneWidget,
        );
        settings.loaded.complete(
          AppSettings(
            navigationMode: singlePage
                ? WorkspaceNavigationMode.multipleTabs
                : WorkspaceNavigationMode.singlePage,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
        expect(
          find.byKey(const ValueKey('single-page-header')),
          platform == TargetPlatform.android ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      platform: platform,
    );
  }
  _workspaceTestWidgets(
    'saved navigation mode applies live and single-page back retains real search state',
    (tester) async {
      final settings = _SettingsRepository();
      final search = _SearchRepository();
      final router = createBiliRouter(
        initialLocation: '/search?q=cat',
        playerBuilder: (_, _, _) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settings),
            searchRepositoryProvider.overrideWithValue(search),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(search.queries, ['cat']);
      router.go('/settings');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '单标签页'));
      await tester.pumpAndSettle();
      expect(
        settings.settings.navigationMode,
        WorkspaceNavigationMode.singlePage,
      );
      expect(find.byKey(const ValueKey('single-page-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
      expect(find.byKey(const ValueKey('new-workspace-tab')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '多标签页'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '单标签页'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('“cat” 的搜索结果'), findsOneWidget);
      expect(search.queries, ['cat']);
      final signals = search.cancellations.toList();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(signals.every((signal) => signal.isCancelled), isTrue);
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  _workspaceTestWidgets(
    'account destinations mount and preserve messages and select profile/live sections',
    (tester) async {
      final auth = AuthFake();
      final router = createBiliRouter(
        initialLocation: '/messages',
        playerBuilder: (_, _, _) => const SizedBox(),
        accountBuilder: (_) => const SizedBox(),
      );
      addTearDown(() async {
        router.dispose();
        await auth.stream.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            messageRepositoryProvider.overrideWithValue(
              MessageRepositoryFake(),
            ),
            settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            videoAuthorRepositoryProvider.overrideWithValue(
              FollowRepositoryFake(),
            ),
            profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MessagesScreen), findsOneWidget);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      router.go('/settings');
      await tester.pumpAndSettle();
      router.go('/messages');
      await tester.pumpAndSettle();
      expect(find.text('测试私信正文'), findsOneWidget);
      router.go('/user/1?section=followers');
      await tester.pumpAndSettle();
      final profile = ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
      );
      expect(
        profile.read(profileControllerProvider(const UserId('1'))).section,
        ProfileSection.followers,
      );
      router.go('/?channel=live&section=我的关注');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FeedScreen>(find.byType(FeedScreen)).initialSection,
        '我的关注',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  _workspaceTestWidgets(
    'close shortcut works on every real workspace page after unfocus',
    (tester) async {
      final auth = _AuthRepository();
      final router = createBiliRouter(
        playerBuilder: (_, _, _) => const SizedBox(),
      );
      addTearDown(() async {
        router.dispose();
        await auth.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            searchRepositoryProvider.overrideWithValue(_SearchRepository()),
            libraryRepositoryProvider.overrideWithValue(_HistoryRepository()),
            videoAuthorRepositoryProvider.overrideWithValue(
              FollowRepositoryFake(),
            ),
            profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
            videoRepositoryProvider.overrideWithValue(_VideoRepository()),
            pgcRepositoryProvider.overrideWithValue(_ContentPgcRepository()),
            liveRepositoryProvider.overrideWithValue(_ContentLiveRepository()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      for (final path in [
        '/',
        '/search?q=test',
        '/history',
        '/settings?section=shortcuts',
        '/downloads',
        '/user/42',
        '/video/BV1234567890',
        '/pgc/season/28747',
        '/live/42',
      ]) {
        await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
        await tester.pumpAndSettle();
        final tabId =
            router.routeInformationProvider.value.uri.queryParameters['tab']!;
        final uri = Uri.parse(path);
        router.go(
          uri
              .replace(queryParameters: {...uri.queryParameters, 'tab': tabId})
              .toString(),
        );
        await tester.pumpAndSettle();
        // Clicking outside a toolbar editor can leave the route scope focused.
        FocusScope.of(
          tester.element(find.byKey(ValueKey('workspace-tab-$tabId'))),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('workspace-tab-$tabId')),
          findsNothing,
          reason: path,
        );
        expect(
          router.routeInformationProvider.value.uri.queryParameters['tab'],
          'home',
          reason: path,
        );
        expect(tester.takeException(), isNull, reason: path);
      }
    },
  );

  _workspaceTestWidgets('PGC related season opens its own workspace player', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = _AuthRepository();
    final router = createBiliRouter(
      initialLocation: '/pgc/season/28747',
      playerBuilder: (_, _, _) => const SizedBox(),
      pgcPlayerBuilder: (_, season, _) => Text('影视作品 ${season.seasonId}'),
    );
    addTearDown(() async {
      router.dispose();
      await auth.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          pgcRepositoryProvider.overrideWithValue(_ContentPgcRepository()),
        ],
        child: InputTestApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final related = find.byKey(const ValueKey('pgc-related-99999'));
    await tester.ensureVisible(related);
    await tester.tap(related);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/pgc/season/99999');
    expect(find.text('影视作品 99999'), findsOneWidget);
    expect(find.byType(PgcScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final channel in [
    HomeChannel.bangumi,
    HomeChannel.guochuang,
    HomeChannel.cinema,
    HomeChannel.live,
  ]) {
    _workspaceTestWidgets(
      '${channel.label} card opens the in-app content player',
      (tester) async {
        final auth = _AuthRepository();
        final isLive = channel == HomeChannel.live;
        final router = createBiliRouter(
          initialLocation: '/?channel=${channel.name}',
          playerBuilder: (_, _, _) => const Text('视频播放器'),
          pgcPlayerBuilder: (_, _, episode) =>
              Text('影视播放器 ${episode.episodeId}'),
          livePlayerBuilder: (_, room) => Text('直播播放器 ${room.id.value}'),
        );
        addTearDown(() async {
          router.dispose();
          await auth.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              feedRepositoryProvider.overrideWithValue(_FeedRepository()),
              homeRepositoryProvider.overrideWithValue(
                _HomeRepository(
                  entries: [
                    HomeEntry(
                      id: isLive ? '42' : '28747:123',
                      title: '频道播放样本',
                      kind: isLive ? HomeEntryKind.live : HomeEntryKind.season,
                    ),
                  ],
                ),
              ),
              pgcRepositoryProvider.overrideWithValue(_ContentPgcRepository()),
              liveRepositoryProvider.overrideWithValue(
                _ContentLiveRepository(),
              ),
            ],
            child: InputTestApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('频道播放样本').last);
        await tester.pumpAndSettle();
        if (isLive) {
          expect(find.byType(LiveScreen), findsOneWidget);
          expect(find.text('直播播放器 42'), findsOneWidget);
        } else {
          expect(find.byType(PgcScreen), findsOneWidget);
          expect(find.text('影视播放器 123'), findsOneWidget);
          expect(
            router.routeInformationProvider.value.uri.queryParameters['ep'],
            '123',
          );
        }
        expect(find.text('外部打开 ↗'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
  _workspaceTestWidgets(
    'PGC refresh key reloads current detail without another owner session',
    (tester) async {
      final auth = _AuthRepository();
      final pgc = _ContentPgcRepository();
      final router = createBiliRouter(
        initialLocation: '/pgc/episode/123',
        playerBuilder: (_, _, _) => const SizedBox(),
        pgcPlayerBuilder: (_, _, episode) => Text('影视播放器 ${episode.episodeId}'),
      );
      addTearDown(() async {
        router.dispose();
        await auth.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
            pgcRepositoryProvider.overrideWithValue(pgc),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(pgc.reads, 1);
      expect(find.text('影视播放器 123'), findsOneWidget);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(pgc.reads, 2);
      expect(tester.takeException(), isNull);
    },
  );
  _workspaceTestWidgets(
    'settings deep links and category changes show only their matching controls',
    (tester) async {
      final router = createBiliRouter(
        initialLocation: '/settings?section=shortcuts',
        playerBuilder: (_, _, _) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('关闭当前标签页'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'HarmonyOS Sans'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('settings-category-appearance')),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'HarmonyOS Sans'), findsOneWidget);
      expect(find.text('关闭当前标签页'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('settings-category-playback')),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动播放'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'HarmonyOS Sans'), findsNothing);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  _workspaceTestWidgets(
    'user routes isolate and retain profiles until their tab closes',
    (tester) async {
      final profiles = _ProfileRepository();
      final auth = _AuthRepository();
      addTearDown(auth.dispose);
      final router = createBiliRouter(
        initialLocation: '/user/42',
        playerBuilder: (_, _, _) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            videoAuthorRepositoryProvider.overrideWithValue(
              FollowRepositoryFake(),
            ),
            profileRepositoryProvider.overrideWithValue(profiles),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('用户42'), findsOneWidget);
      final first = ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
      );
      router.go('/user/99');
      await tester.pumpAndSettle();
      expect(find.text('用户99'), findsOneWidget);
      final second = ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
      );
      expect(identical(first, second), isFalse);
      router.go('/user/42');
      await tester.pumpAndSettle();
      expect(find.text('用户42'), findsOneWidget);
      expect(profiles.loaded, ['42', '99']);
      final signals = profiles.signals['42']!;
      expect(signals.every((signal) => !signal.isCancelled), isTrue);
      await tester.tap(find.byKey(const ValueKey('close-workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(signals.every((signal) => signal.isCancelled), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  _workspaceTestWidgets('invalid user deep links do not request a profile', (
    tester,
  ) async {
    final profiles = _ProfileRepository();
    final router = createBiliRouter(
      initialLocation: '/user/0',
      playerBuilder: (_, _, _) => const SizedBox(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoAuthorRepositoryProvider.overrideWithValue(
            FollowRepositoryFake(),
          ),
          profileRepositoryProvider.overrideWithValue(profiles),
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          homeRepositoryProvider.overrideWithValue(_HomeRepository()),
        ],
        child: InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('用户地址无效'), findsOneWidget);
    expect(profiles.loaded, isEmpty);
  });

  for (final mode in WorkspaceNavigationMode.values) {
    _workspaceTestWidgets('profile live entry opens and reuses room in $mode', (
      tester,
    ) async {
      final profiles = _ProfileRepository(
        liveRoom: const ProfileLiveRoom(id: RoomId('1024'), isLive: true),
      );
      final auth = _AuthRepository();
      final settings = _SettingsRepository()
        ..settings = const AppSettings.defaults().copyWith(
          navigationMode: mode,
        );
      addTearDown(auth.dispose);
      final router = createBiliRouter(
        initialLocation: '/user/42',
        playerBuilder: (_, _, _) => const SizedBox(),
        livePlayerBuilder: (_, room) => Text('直播播放器 ${room.id.value}'),
        liveComposerBuilder: (_, _) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            settingsRepositoryProvider.overrideWithValue(settings),
            videoAuthorRepositoryProvider.overrideWithValue(
              FollowRepositoryFake(),
            ),
            profileRepositoryProvider.overrideWithValue(profiles),
            liveRepositoryProvider.overrideWithValue(_ContentLiveRepository()),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
          ],
          child: InputTestApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-live-room')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/live/1024');
      expect(find.text('直播播放器 1024'), findsOneWidget);
      final roomScope = ProviderScope.containerOf(
        tester.element(find.byType(LiveScreen)),
      );
      router.go('/user/42');
      await tester.pumpAndSettle();
      expect(profiles.loaded, ['42']);
      await tester.tap(find.byKey(const ValueKey('profile-live-room')));
      await tester.pumpAndSettle();
      expect(
        identical(
          roomScope,
          ProviderScope.containerOf(tester.element(find.byType(LiveScreen))),
        ),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  _workspaceTestWidgets(
    'workspace shortcuts work after focusing a real channel section',
    (tester) async {
      final router = createBiliRouter(
        playerBuilder: (_, detail, part) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      final bangumi = find.byKey(const ValueKey('channel-bangumi'));
      await tester.ensureVisible(bangumi);
      await tester.tap(bangumi);
      await tester.pumpAndSettle();
      final timetable = find.byKey(const ValueKey('home-section-时间表'));
      await tester.tap(timetable);
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(
          find.descendant(of: timetable, matching: find.text('时间表')),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        'tab-2',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        'home',
      );
    },
  );

  _workspaceTestWidgets(
    'selected video part survives switching to another tab',
    (tester) async {
      final router = createBiliRouter(
        initialLocation: '/video/BV1abc123456',
        playerBuilder: (_, detail, part) => Text('正在播放 ${part.cid}'),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('第二集'));
      await tester.tap(find.text('第二集'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['cid'],
        '2',
      );
      expect(find.text('正在播放 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
      await tester.pumpAndSettle();
      expect(find.text('正在播放 2'), findsNothing);
      expect(find.text('正在播放 2', skipOffstage: false), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('正在播放 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _workspaceTestWidgets('browse tabs isolate their selected feed channel', (
    tester,
  ) async {
    final router = createBiliRouter(
      playerBuilder: (_, detail, part) => const SizedBox(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          homeRepositoryProvider.overrideWithValue(_HomeRepository()),
        ],
        child: InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final homeElement = tester.element(find.byType(FeedScreen));
    final homeScope = ProviderScope.containerOf(homeElement);
    await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
    await tester.pumpAndSettle();
    final browseScope = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    );
    expect(identical(homeScope, browseScope), isFalse);
    await tester.tap(find.byKey(const ValueKey('channel-popular')));
    await tester.pumpAndSettle();
    expect(
      browseScope.read(feedControllerProvider).channel,
      HomeChannel.popular,
    );
    expect(
      homeScope.read(feedControllerProvider).channel,
      HomeChannel.recommended,
    );
    await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
    await tester.pumpAndSettle();
    expect(
      homeScope.read(feedControllerProvider).channel,
      HomeChannel.recommended,
    );
  });

  _workspaceTestWidgets(
    'at capacity new navigation preserves all existing tabs',
    (tester) async {
      final search = _SearchRepository();
      final router = createBiliRouter(
        playerBuilder: (_, detail, part) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            searchRepositoryProvider.overrideWithValue(search),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 15; index++) {
        router.go('/search?q=query$index');
        await tester.pumpAndSettle();
      }
      final previousSignal = search.cancellations.last;
      await tester.enterText(
        find.byKey(const ValueKey('workspace-search')),
        'old draft',
      );
      router.go('/search?q=replacement');
      await tester.pumpAndSettle();
      expect(previousSignal.isCancelled, isFalse);
      expect(
        find.byKey(const ValueKey('workspace-tab-tab-15')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('workspace-tab-tab-16')), findsNothing);
      expect(find.text('“query14” 的搜索结果'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('workspace-search')),
      );
      expect(field.controller?.text, 'old draft');
      expect(search.cancellations.last.isCancelled, isFalse);
    },
  );

  _workspaceTestWidgets(
    'deep links isolate cached search queries and close cancels their controller',
    (tester) async {
      final search = _SearchRepository();
      final router = createBiliRouter(
        initialLocation: '/search?q=cat',
        playerBuilder: (_, detail, part) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            searchRepositoryProvider.overrideWithValue(search),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(search.queries, ['cat']);
      expect(find.text('“cat” 的搜索结果'), findsOneWidget);
      router.go('/search?q=dog');
      await tester.pumpAndSettle();
      expect(search.queries, ['cat', 'dog']);
      expect(find.text('“dog” 的搜索结果'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('“cat” 的搜索结果'), findsOneWidget);
      expect(search.queries, ['cat', 'dog']);
      expect(
        search.cancellations.every((signal) => !signal.isCancelled),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('close-workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(search.cancellations.first.isCancelled, isTrue);
      expect(search.cancellations.last.isCancelled, isFalse);
      router.go('/search?q=dog');
      await tester.pumpAndSettle();
      expect(find.text('“dog” 的搜索结果'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);
      expect(search.cancellations[1].isCancelled, isFalse);
      expect(search.queries, ['cat', 'dog']);
    },
  );

  _workspaceTestWidgets(
    'account transition discards all cached tab scopes and reloads their queries',
    (tester) async {
      final search = _SearchRepository();
      final auth = _AuthRepository();
      final router = createBiliRouter(
        initialLocation: '/search?q=cat',
        accountBuilder: (_) => const Text('account'),
        playerBuilder: (_, detail, part) => const SizedBox(),
      );
      addTearDown(router.dispose);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(_HomeRepository()),
            searchRepositoryProvider.overrideWithValue(search),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/search?q=dog');
      await tester.pumpAndSettle();
      final oldSignals = search.cancellations.toList();
      auth.setState(
        const AuthState(status: AuthStatus.signedIn, userName: 'tester'),
      );
      await tester.pumpAndSettle();
      expect(oldSignals.every((signal) => signal.isCancelled), isTrue);
      expect(search.queries.where((query) => query == 'cat').length, 2);
      expect(search.queries.where((query) => query == 'dog').length, 2);
      expect(find.text('“dog” 的搜索结果'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('“cat” 的搜索结果'), findsOneWidget);
      expect(search.queries.length, 4);
    },
  );
}

final class _HistoryRepository implements LibraryRepository {
  @override
  String get accountScope => 'user:1';
  @override
  Future<WatchHistoryPage> loadHistory({
    String? cursor,
    required RequestCancellation cancellation,
  }) async => const WatchHistoryPage([], hasMore: false);
}

final class _SettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings.defaults();
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async {
    settings = value;
  }
}

final class _PendingSettingsRepository implements SettingsRepository {
  final loaded = Completer<AppSettings>();
  @override
  Future<AppSettings> load() => loaded.future;
  @override
  Future<void> save(AppSettings value) async {}
}

void _workspaceTestWidgets(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.windows,
}) => testWidgets(
  description,
  callback,
  variant: TargetPlatformVariant.only(platform),
);

final class _VideoRepository implements VideoRepository {
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => VideoDetail(
    summary: VideoSummary(
      id: id,
      title: '多分 P 视频',
      coverUrl: '',
      author: '测试 UP',
      duration: const Duration(minutes: 2),
    ),
    description: '',
    parts: const [
      VideoPart(
        cid: '1',
        page: 1,
        title: '第一集',
        duration: Duration(minutes: 1),
      ),
      VideoPart(
        cid: '2',
        page: 2,
        title: '第二集',
        duration: Duration(minutes: 1),
      ),
    ],
  );
}

final class _TagTestPlayer extends StatefulWidget {
  const _TagTestPlayer({required this.part, required this.onCreate});
  final VideoPart part;
  final VoidCallback onCreate;
  @override
  State<_TagTestPlayer> createState() => _TagTestPlayerState();
}

final class _TagTestPlayerState extends State<_TagTestPlayer> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => Text('播放 ${widget.part.title}');
}

final class _SearchRepository implements SearchRepository {
  _SearchRepository({this.countsByQuery = const {}});
  final Map<String, Map<SearchCategory, int>> countsByQuery;
  final queries = <String>[];
  final cancellations = <RequestCancellation>[];
  final calls =
      <
        ({
          String query,
          int page,
          SearchCategory category,
          SearchOrder order,
          SearchDuration duration,
          SearchUserType userType,
        })
      >[];
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) async {
    queries.add(query);
    cancellations.add(cancellation);
    calls.add((
      query: query,
      page: page,
      category: category,
      order: order,
      duration: duration,
      userType: userType,
    ));
    return SearchPage(
      items: [],
      hasMore: false,
      counts: countsByQuery[query] ?? const {},
    );
  }
}

final class _FeedRepository implements FeedRepository {
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
}

final class _AuthRepository implements AuthRepository {
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  AuthState _current = const AuthState();
  void setState(AuthState state) {
    _current = state;
    _changes.add(state);
  }

  @override
  AuthState get current => _current;
  @override
  Stream<AuthState> get changes => _changes.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async => setState(const AuthState());
  @override
  void cancelSignIn() {}
  Future<void> dispose() => _changes.close();
}

final class _HomeRepository implements HomeRepository {
  _HomeRepository({this.entries = const []});
  final List<HomeEntry> entries;
  @override
  String get accountScope => 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => HomePage(query.section == '全部分区' ? [] : entries, hasMore: false);
}

final class _ProfileRepository implements ProfileRepository {
  _ProfileRepository({this.liveRoom});
  final ProfileLiveRoom? liveRoom;
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    signals.putIfAbsent(id.value, () => []).add(cancellation);
    return liveRoom;
  }

  final loaded = <String>[];
  final signals = <String, List<RequestCancellation>>{};
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    loaded.add(id.value);
    signals.putIfAbsent(id.value, () => []).add(cancellation);
    return UserProfile(id: id, name: '用户${id.value}');
  }

  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    required RequestCancellation cancellation,
  }) async {
    signals.putIfAbsent(id.value, () => []).add(cancellation);
    return const ProfilePage(items: [], hasMore: false);
  }
}

final class _ContentPgcRepository implements PgcRepository {
  int reads = 0;
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    return PgcSeason(
      id: seasonId ?? const PgcSeasonId('28747'),
      title: '作品样本',
      relatedSeasons: const [
        PgcSeasonSummary(id: PgcSeasonId('99999'), title: '系列作品样本'),
      ],
      episodes: const [
        PgcEpisode(
          id: PgcEpisodeId('123'),
          title: '1',
          bvid: 'BV1234567890',
          cid: '1',
        ),
      ],
    );
  }
}

final class _ContentLiveRepository implements LiveRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => LiveRoom(id: id, title: '房间样本', anchorName: '主播', isLive: true);
  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) async => LivePlayInfo(roomId: id, isLive: true, streams: const []);
}
