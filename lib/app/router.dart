import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../features/auth/presentation/account_button.dart';
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
  String initialLocation = '/',
  InputRouteObserver? inputObserver,
}) => GoRouter(
  initialLocation: initialLocation,
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
            navigationMode: settings.navigationMode,
            shortcuts: settings.shortcuts,
            location: state.uri.toString(),
            accountBuilder: accountBuilder,
            windowControlsBuilder: windowControlsBuilder,
            dragRegionBuilder: dragRegionBuilder,
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

  Future<CommandOutcome> _refresh(
    BuildContext context,
    InputStroke stroke,
  ) async {
    if (stroke.phase != InputPhase.down) return CommandOutcome.noOp;
    final container = ProviderScope.containerOf(context, listen: false);
    final uri = tab.location;
    if (tab.isBrowse) {
      container.invalidate(homeControllerProvider);
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
    final playback = ref.watch(playbackManagerProvider);
    if (playback != null && WorkspaceActivity.isActive(context)) {
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
      child: Builder(
        builder: (context) => CommandTargetScope<Object>(
          scope: CommandScope.page,
          active: WorkspaceActivity.isActive(context),
          merge: const {ShortcutAction.refresh},
          commands: {
            if (!tab.isPgc &&
                (tab.isBrowse ||
                    tab.isVideo ||
                    tab.isLive ||
                    tab.isProfile ||
                    tab.isOffline ||
                    const [
                      '/search',
                      '/history',
                      '/messages',
                      '/downloads',
                    ].contains(tab.location.path)))
              ShortcutAction.refresh: (stroke) => _refresh(context, stroke),
          },
          child: Builder(
            builder: (context) {
              final uri = tab.location;
              switch (uri.path) {
                case '/':
                  final channel =
                      HomeChannel.values
                          .where(
                            (channel) =>
                                channel.name == uri.queryParameters['channel'],
                          )
                          .firstOrNull ??
                      HomeChannel.recommended;
                  return FeedScreen(
                    key: PageStorageKey('feed-${tab.id}'),
                    channel: channel,
                    initialSection: uri.queryParameters['section'],
                    onChannelChanged: (channel) => context.go(
                      Uri(
                        path: '/',
                        queryParameters: {
                          'channel': channel.name,
                          'tab': tab.id,
                        },
                      ).toString(),
                    ),
                    isSignedIn: account.$1,
                    onLogin: observeAccount
                        ? () => showDialog<void>(
                            context: context,
                            builder: (_) => const AccountDialog(),
                          )
                        : null,
                  );
                case '/search':
                  return WorkspacePageHeader.wrap(
                    context,
                    SearchScreen(
                      key: PageStorageKey('search-${tab.id}'),
                      query: uri.queryParameters['q'] ?? '',
                    ),
                  );
                case '/history':
                  return HistoryScreen(
                    key: PageStorageKey('history-${tab.id}'),
                  );
                case '/messages':
                  return MessagesScreen(
                    key: PageStorageKey('messages-${tab.id}'),
                    initialUserId: UserId.tryParse(
                      uri.queryParameters['talker'],
                    ),
                    initialUserName: uri.queryParameters['name'],
                    initialUserAvatar: switch (uri.queryParameters['avatar']) {
                      final avatar? => Uri.tryParse(avatar),
                      _ => null,
                    },
                    onInitialConversationOpened: () =>
                        context.go('/messages?tab=${tab.id}'),
                    onLogin: () => showDialog<void>(
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
                        ref.read(externalLinkOpenerProvider)(target);
                      }
                    },
                  );
                case '/settings':
                  return SettingsScreen(
                    key: PageStorageKey('settings-${tab.id}'),
                    category: SettingsCategory.fromName(
                      uri.queryParameters['section'],
                    ),
                  );
                case '/downloads':
                  return DownloadsScreen(
                    key: PageStorageKey('downloads-${tab.id}'),
                    onPlay: (task) => context.go('/offline/${task.id}'),
                    onOpenDirectory: onOpenDownloadDirectory,
                    allowCustomDirectory: allowCustomDownloadDirectory,
                    coverProvider: downloadCoverProvider,
                  );
                default:
                  if (tab.isOffline) {
                    return OfflineScreen(
                      key: PageStorageKey('offline-${tab.id}'),
                      taskId: uri.pathSegments.last,
                      playerBuilder:
                          offlinePlayerBuilder ??
                          (_, _) => const StateView.empty(message: '离线播放服务未配置'),
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
                      seasonId: uri.pathSegments[1] == 'season' ? id : null,
                      episodeId: uri.pathSegments[1] == 'episode'
                          ? id
                          : uri.queryParameters['ep'],
                      playerBuilder:
                          pgcPlayerBuilder ??
                          (_, _, _) =>
                              const StateView.empty(message: '影视播放服务未配置'),
                      commentsBuilder: pgcCommentsBuilder,
                      onDownload: onDownloadSeason == null
                          ? null
                          : (season, selected) => onDownloadSeason?.call(
                              context,
                              season,
                              selected,
                            ),
                      onOpenSeason: (season) =>
                          context.go('/pgc/season/${season.seasonId}'),
                      onEpisodeChanged: (episode) => context.go(
                        uri
                            .replace(
                              path: uri.pathSegments[1] == 'episode'
                                  ? '/pgc/episode/${episode.episodeId}'
                                  : uri.path,
                              queryParameters: {
                                ...uri.queryParameters,
                                'ep': episode.episodeId,
                                'tab': tab.id,
                              },
                            )
                            .toString(),
                      ),
                    );
                  }
                  if (tab.isLive) {
                    return LiveScreen(
                      key: PageStorageKey('live-${tab.id}'),
                      roomId: uri.pathSegments.last,
                      composerBuilder: liveComposerBuilder,
                      playerBuilder:
                          livePlayerBuilder ??
                          (_, _) => const StateView.empty(message: '直播播放服务未配置'),
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
                            onOpenLiveRoom: (room) =>
                                context.go('/live/${room.value}'),
                            onLogin: () => showDialog<void>(
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
                            id: id,
                            queue: queue?.indexOf(id) == -1 ? null : queue,
                            initialCid: uri.queryParameters['cid'],
                            playerBuilder: playerBuilder,
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
                                ? () => showDialog<void>(
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
                            onOpenQueueVideo: queue == null
                                ? null
                                : (video) {
                                    final target = Uri(
                                      path: '/video/${video.value}',
                                      queryParameters: {'queue': queue.id},
                                    );
                                    final navigation =
                                        WorkspacePageNavigation.maybeOf(
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
      ),
    );
  }
}
