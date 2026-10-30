import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/ui/app_dialog.dart';
import '../shared/ui/app_notice.dart';
import '../domain/video.dart';
import '../features/downloads/domain/download_models.dart';
import '../features/downloads/application/download_controller.dart';
import '../features/downloads/presentation/downloads_screen.dart';
import '../features/downloads/presentation/offline_screen.dart';
import '../domain/user.dart';
import '../core/platform/external_links.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/messages/application/messages_controller.dart';
import '../features/messages/presentation/messages_screen.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../core/input/input_stroke.dart';
import '../core/input/shortcut_dispatcher.dart';
import '../core/presentation/input_scope.dart';
import '../core/presentation/app_input_host.dart';
import '../core/presentation/workspace_activity.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/domain/settings_category.dart';
import '../features/settings/domain/shortcut_settings.dart';
import '../features/library/application/library_controller.dart';
import '../features/video/application/video_controller.dart';
import '../features/video/application/video_extras_controller.dart';
import '../features/playback/application/playback_session.dart';
import '../features/playback/application/playback_manager.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/comments/application/comment_link_resolver.dart';
import '../features/auth/presentation/account_button.dart';
import '../features/auth/presentation/account_screen.dart';
import '../features/feed/application/feed_controller.dart';
import '../features/feed/application/home_controller.dart';
import '../features/feed/domain/home_channel.dart';
import '../features/feed/presentation/feed_screen.dart';
import '../features/library/presentation/history_screen.dart';
import '../features/search/application/search_controller.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/video/presentation/video_screen.dart';
import '../features/video/application/watch_later_queue_registry.dart';
import '../core/network/api_requests.dart';
import '../features/pgc/application/pgc_controller.dart';
import '../features/pgc/domain/pgc_repository.dart';
import '../features/pgc/presentation/pgc_screen.dart';
import '../features/live/application/live_controller.dart';
import '../features/live/presentation/live_screen.dart';
import '../features/live/domain/live_room.dart';
import '../shared/ui/state_view.dart';
import 'shell.dart';
import 'workspace_tabs.dart';
import 'workspace_root_page.dart';
import 'workspace_navigation.dart';
import 'platform_defaults.dart';

GoRouter createBiliRouter({
  required VideoPlayerBuilder playerBuilder,
  PgcPlayerBuilder? pgcPlayerBuilder,
  PgcCommentsBuilder? pgcCommentsBuilder,
  LivePlayerBuilder? livePlayerBuilder,
  LiveComposerBuilder? liveComposerBuilder,
  VideoPlayerBuilder? actionsBuilder,
  VideoPlayerBuilder? menuBuilder,
  Widget Function(BuildContext, DownloadTask)? offlinePlayerBuilder,
  void Function(BuildContext, PgcSeason, PgcEpisode?)? onDownloadSeason,
  Future<void> Function(String)? onOpenDownloadDirectory,
  bool allowCustomDownloadDirectory = false,
  ImageProvider<Object>? Function(DownloadTask)? downloadCoverProvider,
  WidgetBuilder? accountBuilder,
  WidgetBuilder? windowControlsBuilder,
  DragRegionBuilder? dragRegionBuilder,
  WorkspaceWindowBuilder? playbackWindowBuilder,
  VoidCallback? onActivateBrowser,
  Future<void> Function()? onExitRequested,
  String initialLocation = '/',
  InputRouteObserver? inputObserver,
}) => GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) {
    final uri = state.uri;
    if (uri.path != '/') return null;
    final parameters = {...uri.queryParameters};
    if (parameters['channel'] == 'ranking') {
      parameters['channel'] = 'popular';
      parameters['section'] = '排行榜';
    } else if (parameters['channel'] == 'live' &&
        parameters['section'] == '全部分区') {
      parameters['section'] = '推荐直播';
    } else {
      return null;
    }
    return uri.replace(queryParameters: parameters).toString();
  },
  observers: [?inputObserver],
  routes: [
    ShellRoute(
      observers: [?inputObserver?.child()],
      builder: (context, state, child) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              AppSettings.defaults(
                navigationMode: defaultWorkspaceNavigationMode,
              );
          return BiliAppShell(
            accountIdentity: accountBuilder == null
                ? null
                : ref.watch(
                    authControllerProvider.select(
                      (auth) => (
                        auth.isSignedIn,
                        auth.mid,
                        ref.read(sessionEpochProvider)(),
                      ),
                    ),
                  ),
            navigationMode: settings.navigationMode,
            navigationBarMode: settings.navigationBarMode,
            sidebarStyle: settings.sidebarStyle,
            sidebarCollapsed: settings.sidebarCollapsed,
            onSidebarCollapsedChanged: (collapsed) async {
              try {
                await ref
                    .read(settingsControllerProvider.notifier)
                    .setSidebarCollapsed(collapsed);
              } catch (_) {
                if (context.mounted) {
                  showAppNotice(context, '侧栏设置保存失败，请重试');
                }
              }
            },
            shortcuts: settings.shortcuts,
            location: state.uri.toString(),
            accountBuilder: accountBuilder,
            windowControlsBuilder: windowControlsBuilder,
            dragRegionBuilder: dragRegionBuilder,
            playbackWindowBuilder: playbackWindowBuilder,
            onActivateBrowser: onActivateBrowser,
            onExitRequested: onExitRequested,
            pageScopeBuilder: (context, tab, child) => _WorkspacePageScope(
              tab: tab,
              observeAccount: accountBuilder != null,
              allowConcurrentPlayback: settings.concurrentPlaybackEnabled,
              child: child,
            ),
            pageBuilder: (context, tab) => _WorkspacePage(
              tab: tab,
              playerBuilder: playerBuilder,
              pgcPlayerBuilder: pgcPlayerBuilder,
              pgcCommentsBuilder: pgcCommentsBuilder,
              livePlayerBuilder: livePlayerBuilder,
              liveComposerBuilder: liveComposerBuilder,
              actionsBuilder: actionsBuilder,
              menuBuilder: menuBuilder,
              offlinePlayerBuilder: offlinePlayerBuilder,
              onDownloadSeason: onDownloadSeason,
              onOpenDownloadDirectory: onOpenDownloadDirectory,
              allowCustomDownloadDirectory: allowCustomDownloadDirectory,
              downloadCoverProvider: downloadCoverProvider,
              observeAccount: accountBuilder != null,
              allowConcurrentPlayback: settings.concurrentPlaybackEnabled,
            ),
            child: child,
          );
        },
      ),
      // The shell owns cached pages; these routes retain go_router's deep-link
      // parsing and location updates without mounting a duplicate page/player.
      routes: [
        for (final path in [
          '/',
          '/search',
          '/video/:bvid',
          '/pgc/season/:id',
          '/pgc/episode/:id',
          '/live/:roomId',
          '/user/:mid',
          '/history',
          '/messages',
          '/settings',
          '/downloads',
          '/me',
          '/offline/:taskId',
        ])
          GoRoute(
            path: path,
            builder: (context, state) => const SizedBox.shrink(),
          ),
      ],
    ),
  ],
  errorBuilder: (context, state) =>
      const Scaffold(body: StateView.empty(message: '找不到这个页面')),
);

final class _WorkspacePageScope extends ConsumerWidget {
  const _WorkspacePageScope({
    required this.tab,
    required this.observeAccount,
    required this.allowConcurrentPlayback,
    required this.child,
  });
  final WorkspaceTab tab;
  final bool observeAccount, allowConcurrentPlayback;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackManagerProvider);
    final selectedPlayback = WorkspacePlaybackSelection.of(context);
    if (playback != null &&
        WorkspaceActivity.isActive(context) &&
        (selectedPlayback == null || selectedPlayback == tab.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !WorkspaceActivity.isActive(context)) return;
        unawaited(
          playback.updateWorkspace(
            allowConcurrent: allowConcurrentPlayback,
            activeTabId: tab.id,
          ),
        );
      });
    }
    final account = observeAccount
        ? ref.watch(
            authControllerProvider.select(
              (auth) => (
                auth.isSignedIn,
                auth.mid,
                auth.userName,
                ref.read(sessionEpochProvider)(),
              ),
            ),
          )
        : (false, null, null, 0);
    return ProviderScope(
      // An expired restored login can cancel reads while still displaying
      // guest. Include the epoch so cancelled pages restart in that case too.
      key: ValueKey(account),
      overrides: [
        commentVideoNavigatorProvider.overrideWithValue(
          (video) => context.go('/video/${video.value}'),
        ),
        if (playback != null)
          playbackSessionProvider.overrideWith((ref) {
            final session = playback.acquire(tab.id);
            ref.onDispose(() => playback.release(tab.id, session));
            return session;
          }),
        feedControllerProvider.overrideWith(FeedController.new),
        homeControllerProvider.overrideWith2(HomeController.new),
        profileControllerProvider.overrideWith2(ProfileController.new),
        liveControllerProvider.overrideWith2(LiveController.new),
        pgcControllerProvider.overrideWith2(PgcController.new),
        searchControllerProvider.overrideWith(SearchController.new),
        messagesControllerProvider.overrideWith(MessagesController.new),
      ],
      child: child,
    );
  }
}

final class _WorkspacePage extends ConsumerWidget {
  const _WorkspacePage({
    required this.tab,
    required this.playerBuilder,
    this.pgcPlayerBuilder,
    this.pgcCommentsBuilder,
    this.livePlayerBuilder,
    this.liveComposerBuilder,
    this.actionsBuilder,
    this.menuBuilder,
    this.offlinePlayerBuilder,
    this.onDownloadSeason,
    this.onOpenDownloadDirectory,
    this.allowCustomDownloadDirectory = false,
    this.downloadCoverProvider,
    required this.observeAccount,
    required this.allowConcurrentPlayback,
  });
  final WorkspaceTab tab;
  final VideoPlayerBuilder playerBuilder;
  final PgcPlayerBuilder? pgcPlayerBuilder;
  final PgcCommentsBuilder? pgcCommentsBuilder;
  final LivePlayerBuilder? livePlayerBuilder;
  final LiveComposerBuilder? liveComposerBuilder;
  final VideoPlayerBuilder? actionsBuilder;
  final VideoPlayerBuilder? menuBuilder;
  final Widget Function(BuildContext, DownloadTask)? offlinePlayerBuilder;
  final void Function(BuildContext, PgcSeason, PgcEpisode?)? onDownloadSeason;
  final Future<void> Function(String)? onOpenDownloadDirectory;
  final bool allowCustomDownloadDirectory;
  final ImageProvider<Object>? Function(DownloadTask)? downloadCoverProvider;
  final bool observeAccount;
  final bool allowConcurrentPlayback;

  HomeChannel _channelFor(Uri location) =>
      HomeChannel.values
          .where(
            (channel) => channel.name == location.queryParameters['channel'],
          )
          .firstOrNull ??
      HomeChannel.recommended;

  // Feature controllers keep their tab owner. Repeating family overrides here
  // would invalidate retained queries; AccountContent isolates its own queries.
  Widget _rootBranch({
    required WorkspaceRootSection section,
    required Uri location,
    required WidgetBuilder builder,
  }) => ProviderScope(
    key: ValueKey(section),
    child: Builder(
      builder: (context) => _PageCommandTarget(
        commands: {
          if ((section == WorkspaceRootSection.feed &&
                  _channelFor(location).hasVideoFeed) ||
              section == WorkspaceRootSection.messages ||
              section == WorkspaceRootSection.downloads)
            ShortcutAction.refresh: (stroke) => _refresh(context, stroke),
        },
        child: builder(context),
      ),
    ),
  );

  Widget _rootPage(BuildContext context, bool signedIn) => WorkspaceRootPage(
    location: tab.location,
    feedBuilder: (context, location) => _rootBranch(
      section: WorkspaceRootSection.feed,
      location: location,
      builder: (context) {
        final channel = _channelFor(location);
        final compact = MediaQuery.sizeOf(context).width < 600;
        return FeedScreen(
          key: PageStorageKey('feed-${tab.id}'),
          channel: channel,
          initialSection: location.queryParameters['section'],
          showLiveSectionTabs: compact,
          channelGroups: channelGroupsForNavigation(compact: compact),
          animateChannelSelection: (from, to) =>
              shouldAnimateChannelSelection(from, to, compact: compact),
          onSectionChanged: (section) => context.go(
            Uri(
              path: '/',
              queryParameters: {
                ...location.queryParameters,
                'channel': channel.name,
                'section': section,
                'tab': tab.id,
              },
            ).toString(),
          ),
          onChannelChanged: (channel) => context.go(
            Uri(
              path: '/',
              queryParameters: {'channel': channel.name, 'tab': tab.id},
            ).toString(),
          ),
          isSignedIn: signedIn,
          onLogin: observeAccount
              ? () => showAppDialog<void>(
                  context: context,
                  builder: (_) => const AccountDialog(),
                )
              : null,
        );
      },
    ),
    accountBuilder: (context, location) => _rootBranch(
      section: WorkspaceRootSection.account,
      location: location,
      builder: (context) {
        void login() => showAppDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        );
        return AccountScreen(
          key: PageStorageKey('me-${tab.id}'),
          initialTab: AccountContentTab.values
              .where((tab) => tab.name == location.queryParameters['section'])
              .firstOrNull,
          onTabChanged: (section) => context.go(
            Uri(
              path: '/me',
              queryParameters: {'section': section.name, 'tab': tab.id},
            ).toString(),
          ),
          onNavigate: context.go,
          onLogin: login,
          contentBuilder: (context, section) =>
              _accountContent(context, section, signedIn, login),
        );
      },
    ),
    messagesBuilder: (context, location) => _rootBranch(
      section: WorkspaceRootSection.messages,
      location: location,
      builder: (context) => _messagesPage(context, location),
    ),
    downloadsBuilder: (context, location) => _rootBranch(
      section: WorkspaceRootSection.downloads,
      location: location,
      builder: (context) => _downloadsPage(context),
    ),
    settingsBuilder: (context, location) => _rootBranch(
      section: WorkspaceRootSection.settings,
      location: location,
      builder: (context) => _settingsPage(context, location),
    ),
  );

  Widget _messagesPage(BuildContext context, Uri uri) => MessagesScreen(
    key: PageStorageKey('messages-${tab.id}'),
    initialUserId: UserId.tryParse(uri.queryParameters['talker']),
    initialUserName: uri.queryParameters['name'],
    initialUserAvatar: switch (uri.queryParameters['avatar']) {
      final avatar? => Uri.tryParse(avatar),
      _ => null,
    },
    onInitialConversationOpened: () {
      // A recipient can finish opening after another primary destination was
      // selected. Consuming it must not bring a hidden inbox to the foreground.
      if (context.mounted && WorkspaceActivity.isActive(context)) {
        context.go('/messages?tab=${tab.id}');
      }
    },
    onLogin: () => showAppDialog<void>(
      context: context,
      builder: (_) => const AccountDialog(),
    ),
    onOpenUser: (user) => context.go('/user/${user.value}'),
    onOpenTarget: (target) {
      final parts = target.pathSegments;
      if (target.host == 'www.bilibili.com' &&
          parts.length >= 2 &&
          parts.first == 'video' &&
          VideoId(parts[1]).isValid) {
        context.go('/video/${parts[1]}');
      } else {
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(externalLinkOpenerProvider)(target);
      }
    },
  );

  Widget _settingsPage(BuildContext context, Uri uri) => SettingsScreen(
    key: PageStorageKey('settings-${tab.id}'),
    category: SettingsCategory.fromName(uri.queryParameters['section']),
    onCategoryChanged: (category) => context.go(
      Uri(
        path: '/settings',
        queryParameters: {'tab': tab.id, 'section': category.name},
      ).toString(),
    ),
  );

  Widget _downloadsPage(BuildContext context) => DownloadsScreen(
    key: PageStorageKey('downloads-${tab.id}'),
    onPlay: (task) => context.go('/offline/${task.id}'),
    onOpenDirectory: onOpenDownloadDirectory,
    allowCustomDirectory: allowCustomDownloadDirectory,
    coverProvider: downloadCoverProvider,
  );

  Widget _accountContent(
    BuildContext context,
    AccountContentTab section,
    bool signedIn,
    VoidCallback onLogin,
  ) => ProviderScope(
    key: ValueKey(('account-content', tab.id, section)),
    overrides: [
      if (section == AccountContentTab.history)
        historyProvider.overrideWith(HistoryController.new),
      if (section == AccountContentTab.watchLater ||
          section == AccountContentTab.favorites) ...[
        feedControllerProvider.overrideWith(FeedController.new),
        homeControllerProvider.overrideWith2(HomeController.new),
      ],
    ],
    child: Consumer(
      builder: (context, ref, _) => _PageCommandTarget(
        commands: {
          if ((signedIn && section == AccountContentTab.history) ||
              section == AccountContentTab.downloads)
            ShortcutAction.refresh: (stroke) async {
              if (stroke.phase != InputPhase.down) return CommandOutcome.noOp;
              switch (section) {
                case AccountContentTab.history:
                  await ref.read(historyProvider.notifier).refresh();
                case AccountContentTab.watchLater:
                case AccountContentTab.favorites:
                  return CommandOutcome.noOp;
                case AccountContentTab.downloads:
                  await ref.read(downloadControllerProvider.notifier).refresh();
              }
              return CommandOutcome.completed;
            },
        },
        child: switch (section) {
          AccountContentTab.history =>
            signedIn
                ? const HistoryScreen(showHeading: false)
                : SingleChildScrollView(
                    child: StateView.empty(
                      message: '登录后可查看历史记录',
                      icon: Icons.history_rounded,
                      actionLabel: '登录账号',
                      onAction: onLogin,
                    ),
                  ),
          AccountContentTab.watchLater ||
          AccountContentTab.favorites => FeedScreen(
            channel: section == AccountContentTab.watchLater
                ? HomeChannel.watchLater
                : HomeChannel.favorites,
            isSignedIn: signedIn,
            onLogin: onLogin,
          ),
          AccountContentTab.downloads => DownloadsScreen(
            showHeading: false,
            onPlay: (task) => context.go('/offline/${task.id}'),
            onOpenDirectory: onOpenDownloadDirectory,
            allowCustomDirectory: allowCustomDownloadDirectory,
            coverProvider: downloadCoverProvider,
          ),
        },
      ),
    ),
  );

  Future<CommandOutcome> _refresh(
    BuildContext context,
    InputStroke stroke,
  ) async {
    if (stroke.phase != InputPhase.down) return CommandOutcome.noOp;
    final container = ProviderScope.containerOf(context, listen: false);
    final uri = tab.location;
    if (tab.isBrowse) {
      await container.read(feedControllerProvider.notifier).refresh();
    } else if (uri.path == '/search') {
      await container.read(searchControllerProvider.notifier).refresh();
    } else if (uri.path == '/history') {
      container.invalidate(historyProvider);
    } else if (uri.path == '/messages') {
      await container.read(messagesControllerProvider.notifier).refresh();
    } else if (uri.path == '/downloads') {
      await container.read(downloadControllerProvider.notifier).refresh();
    } else if (tab.isOffline) {
      final session = container.read(playbackSessionProvider);
      await session.retry();
      if (session.error != null) return CommandOutcome.failed;
    } else if (tab.isProfile) {
      final id = UserId(uri.pathSegments.last);
      if (!id.isValid) return CommandOutcome.noOp;
      await container.read(profileControllerProvider(id).notifier).refresh();
    } else if (tab.isLive) {
      final id = RoomId(uri.pathSegments.last);
      if (!id.isValid) return CommandOutcome.noOp;
      final provider = liveControllerProvider(id);
      await container.read(provider.notifier).load();
      if (!context.mounted) return CommandOutcome.stale;
      if (container.read(provider).roomMessage != null) {
        return CommandOutcome.failed;
      }
    } else if (tab.isVideo) {
      final id = VideoId(uri.pathSegments.last);
      container.invalidate(relatedVideosProvider(id));
      container.invalidate(videoTagsProvider(id));
      final session = container.read(playbackSessionProvider);
      if (session.detail?.summary.id == id) {
        await session.retry();
        if (session.error != null) return CommandOutcome.failed;
      } else {
        container.invalidate(videoDetailProvider(id));
      }
    } else {
      return CommandOutcome.noOp;
    }
    return CommandOutcome.completed;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultShowComments = tab.isVideo || tab.isPgc
        ? ref.watch(
            settingsControllerProvider.select(
              (settings) =>
                  settings.value?.defaultShowComments ??
                  (settings.isLoading ? null : false),
            ),
          )
        : false;
    final account = observeAccount
        ? ref.watch(
            authControllerProvider.select(
              (auth) => (
                auth.isSignedIn,
                auth.mid,
                auth.userName,
                ref.read(sessionEpochProvider)(),
              ),
            ),
          )
        : (false, null, null, 0);
    return Builder(
      builder: (context) => _PageCommandTarget(
        commands: {
          if (!tab.isRoot &&
              !tab.isPgc &&
              (tab.isVideo ||
                  tab.isLive ||
                  tab.isProfile ||
                  tab.isOffline ||
                  const ['/search', '/history'].contains(tab.location.path)))
            ShortcutAction.refresh: (stroke) => _refresh(context, stroke),
        },
        child: Builder(
          builder: (context) {
            final uri = tab.location;
            if (tab.isRoot) return _rootPage(context, account.$1);
            switch (uri.path) {
              case '/search':
                return WorkspacePageHeader.wrap(
                  context,
                  SearchScreen(
                    key: PageStorageKey('search-${tab.id}'),
                    query: uri.queryParameters['q'] ?? '',
                  ),
                );
              case '/history':
                return HistoryScreen(key: PageStorageKey('history-${tab.id}'));
              default:
                if (tab.isOffline) {
                  return OfflineScreen(
                    key: PageStorageKey('offline-${tab.id}'),
                    taskId: uri.pathSegments.last,
                    playerBuilder: (context, task) => _workspacePlayer(
                      context,
                      () =>
                          offlinePlayerBuilder?.call(context, task) ??
                          const StateView.empty(message: '离线播放服务未配置'),
                    ),
                    onBackToDownloads: () => context.go('/downloads'),
                    coverProvider: downloadCoverProvider,
                  );
                }
                if (tab.isPgc) {
                  final id = uri.pathSegments.last;
                  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
                    return const StateView.empty(message: '影视地址无效');
                  }
                  return PgcScreen(
                    key: PageStorageKey('pgc-${tab.id}'),
                    defaultShowComments: defaultShowComments,
                    seasonId: uri.pathSegments[1] == 'season' ? id : null,
                    episodeId: uri.pathSegments[1] == 'episode'
                        ? id
                        : uri.queryParameters['ep'],
                    playerBuilder: (context, season, episode) =>
                        _workspacePlayer(
                          context,
                          () =>
                              pgcPlayerBuilder?.call(
                                context,
                                season,
                                episode,
                              ) ??
                              const StateView.empty(message: '影视播放服务未配置'),
                        ),
                    commentsBuilder: pgcCommentsBuilder,
                    onDownload: onDownloadSeason == null
                        ? null
                        : (season, selected) =>
                              onDownloadSeason?.call(context, season, selected),
                    onOpenSeason: (season) =>
                        context.go('/pgc/season/${season.seasonId}'),
                    onEpisodeChanged: (episode) {
                      final target = uri.replace(
                        path: uri.pathSegments[1] == 'episode'
                            ? '/pgc/episode/${episode.episodeId}'
                            : uri.path,
                        queryParameters: {
                          ...uri.queryParameters,
                          'ep': episode.episodeId,
                          'tab': tab.id,
                        },
                      );
                      final navigation = WorkspacePageNavigation.maybeOf(
                        context,
                      );
                      if (navigation != null) {
                        navigation.navigate(target);
                      } else {
                        context.go(target.toString());
                      }
                    },
                  );
                }
                if (tab.isLive) {
                  return LiveScreen(
                    key: PageStorageKey('live-${tab.id}'),
                    roomId: uri.pathSegments.last,
                    composerBuilder: liveComposerBuilder,
                    playerBuilder: (context, room) => _workspacePlayer(
                      context,
                      () =>
                          livePlayerBuilder?.call(context, room) ??
                          const StateView.empty(message: '直播播放服务未配置'),
                    ),
                    onOpenUser: (user) => context.go('/user/${user.value}'),
                  );
                }
                if (tab.isProfile) {
                  final id = UserId(uri.pathSegments.last);
                  return id.isValid
                      ? ProfileScreen(
                          key: PageStorageKey('profile-${tab.id}'),
                          id: id,
                          isSelf: account.$1 && account.$2 == id.value,
                          initialSection:
                              ProfileSection.values
                                  .where(
                                    (s) =>
                                        s.name ==
                                        uri.queryParameters['section'],
                                  )
                                  .firstOrNull ??
                              ProfileSection.videos,
                          onOpenUser: (user) =>
                              context.go('/user/${user.value}'),
                          onOpenVideo: (video) =>
                              context.go('/video/${video.id.value}'),
                          onOpenPlaylist: (video, queueId) => context.go(
                            Uri(
                              path: '/video/${video.id.value}',
                              queryParameters: {'queue': queueId},
                            ).toString(),
                          ),
                          onOpenLiveRoom: (room) =>
                              context.go('/live/${room.value}'),
                          onLogin: () => showAppDialog<void>(
                            context: context,
                            builder: (_) => const AccountDialog(),
                          ),
                          onMessage: (profile) => context.go(
                            Uri(
                              path: '/messages',
                              queryParameters: {
                                'talker': profile.id.value,
                                'name': profile.name,
                                if (profile.avatarUrl case final avatar?)
                                  'avatar': avatar.toString(),
                              },
                            ).toString(),
                          ),
                        )
                      : const StateView.empty(message: '用户地址无效');
                }
                if (tab.isVideo) {
                  final id = VideoId(uri.pathSegments.last);
                  final queueId = uri.queryParameters['queue'];
                  final queue = queueId == null
                      ? null
                      : ref
                            .watch(watchLaterQueueRegistryProvider)
                            .resolve(
                              queueId,
                              scope: ref
                                  .read(homeRepositoryProvider)
                                  .accountScope,
                              sessionEpoch: ref.read(sessionEpochProvider)(),
                            );
                  return id.isValid
                      ? VideoScreen(
                          key: PageStorageKey('video-${tab.id}'),
                          defaultShowComments: defaultShowComments,
                          id: id,
                          queue: queue?.indexOf(id) == -1 ? null : queue,
                          initialCid: uri.queryParameters['cid'],
                          playerBuilder: (context, detail, part) =>
                              _workspacePlayer(
                                context,
                                () => playerBuilder(context, detail, part),
                              ),
                          actionsBuilder: actionsBuilder,
                          menuBuilder: menuBuilder,
                          onSearchTag: (tag) => context.go(
                            Uri(
                              path: '/search',
                              queryParameters: {'q': tag},
                            ).toString(),
                          ),
                          onOpenUser: (user) =>
                              context.go('/user/${user.value}'),
                          onLogin: observeAccount
                              ? () => showAppDialog<void>(
                                  context: context,
                                  builder: (_) => const AccountDialog(),
                                )
                              : null,
                          onOpenVideoPart: (id, cid) => context.go(
                            Uri(
                              path: '/video/${id.value}',
                              queryParameters: cid == null
                                  ? null
                                  : {'cid': cid},
                            ).toString(),
                          ),
                          onOpenVideo: (video) =>
                              context.go('/video/${video.id.value}'),
                          onAdvanceVideo: (video, cid) {
                            final target = Uri(
                              path: '/video/${video.value}',
                              queryParameters: cid == null
                                  ? null
                                  : {'cid': cid},
                            );
                            final navigation = WorkspacePageNavigation.maybeOf(
                              context,
                            );
                            if (navigation != null) {
                              navigation.navigate(target);
                            } else {
                              context.go(
                                target
                                    .replace(
                                      queryParameters: {
                                        ...target.queryParameters,
                                        'tab': tab.id,
                                      },
                                    )
                                    .toString(),
                              );
                            }
                          },
                          onOpenQueueVideo: queue == null
                              ? null
                              : (video) {
                                  final target = Uri(
                                    path: '/video/${video.value}',
                                    queryParameters: {'queue': queue.id},
                                  );
                                  final navigation =
                                      WorkspacePageNavigation.maybeOf(context);
                                  if (navigation != null) {
                                    navigation.navigate(target);
                                  } else {
                                    context.go(
                                      target
                                          .replace(
                                            queryParameters: {
                                              ...target.queryParameters,
                                              'tab': tab.id,
                                            },
                                          )
                                          .toString(),
                                    );
                                  }
                                },
                          onPartChanged: (part) {
                            final target = uri.replace(
                              queryParameters: {
                                ...uri.queryParameters,
                                'cid': part.cid,
                              },
                            );
                            final navigation = queue == null
                                ? null
                                : WorkspacePageNavigation.maybeOf(context);
                            if (navigation != null) {
                              navigation.navigate(target);
                            } else {
                              context.go(
                                target
                                    .replace(
                                      queryParameters: {
                                        ...target.queryParameters,
                                        'tab': tab.id,
                                      },
                                    )
                                    .toString(),
                              );
                            }
                          },
                        )
                      : const StateView.empty(message: '视频地址无效');
                }
                return const StateView.empty(message: '找不到这个页面');
            }
          },
        ),
      ),
    );
  }
}

Widget _workspacePlayer(BuildContext context, Widget Function() build) =>
    WorkspaceMediaPermission.isAllowed(context)
    ? build()
    : const ColoredBox(
        key: ValueKey('workspace-preview-player'),
        color: Colors.black,
      );

/// Visibility updates only the input registration, not the page factory.
class _PageCommandTarget extends StatelessWidget {
  const _PageCommandTarget({required this.commands, required this.child});
  final Map<Object, InputCommand> commands;
  final Widget child;

  @override
  Widget build(BuildContext context) => CommandTargetScope<Object>(
    scope: CommandScope.page,
    active: WorkspaceActivity.isActive(context),
    merge: const {ShortcutAction.refresh},
    commands: commands,
    child: child,
  );
}
