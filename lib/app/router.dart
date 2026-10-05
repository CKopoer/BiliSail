import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/video.dart';
import '../domain/user.dart';
import '../core/platform/external_links.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/messages/application/messages_controller.dart';
import '../features/messages/presentation/messages_screen.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../core/presentation/keyboard_shortcuts.dart';
import '../core/presentation/workspace_activity.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/domain/settings_category.dart';
import '../features/settings/domain/shortcut_settings.dart';
import '../features/library/application/library_controller.dart';
import '../features/video/application/video_controller.dart';
import '../features/video/application/video_extras_controller.dart';
import '../features/playback/application/playback_session.dart';
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
import '../features/pgc/application/pgc_controller.dart';
import '../features/pgc/presentation/pgc_screen.dart';
import '../features/live/application/live_controller.dart';
import '../features/live/presentation/live_screen.dart';
import '../features/live/domain/live_room.dart';
import '../shared/ui/state_view.dart';
import 'shell.dart';
import 'workspace_tabs.dart';

GoRouter createBiliRouter({
  required VideoPlayerBuilder playerBuilder,
  PgcPlayerBuilder? pgcPlayerBuilder,
  PgcCommentsBuilder? pgcCommentsBuilder,
  LivePlayerBuilder? livePlayerBuilder,
  LiveComposerBuilder? liveComposerBuilder,
  VideoPlayerBuilder? actionsBuilder,
  VideoPlayerBuilder? menuBuilder,
  WidgetBuilder? accountBuilder,
  WidgetBuilder? windowControlsBuilder,
  DragRegionBuilder? dragRegionBuilder,
  String initialLocation = '/',
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => Consumer(
        builder: (context, ref, _) => BiliAppShell(
          shortcuts:
              (ref.watch(settingsControllerProvider).value ??
                      const AppSettings.defaults())
                  .shortcuts,
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
            observeAccount: accountBuilder != null,
          ),
          child: child,
        ),
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
    required this.observeAccount,
  });
  final WorkspaceTab tab;
  final VideoPlayerBuilder playerBuilder;
  final PgcPlayerBuilder? pgcPlayerBuilder;
  final PgcCommentsBuilder? pgcCommentsBuilder;
  final LivePlayerBuilder? livePlayerBuilder;
  final LiveComposerBuilder? liveComposerBuilder;
  final VideoPlayerBuilder? actionsBuilder;
  final VideoPlayerBuilder? menuBuilder;
  final bool observeAccount;

  bool _shortcut(BuildContext context, String key) {
    if (!WorkspaceActivity.isActive(context) || shortcutsBlocked(context)) {
      return false;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final settings =
        container.read(settingsControllerProvider).value ??
        const AppSettings.defaults();
    if (settings.shortcuts.actionFor(key) != ShortcutAction.refresh) {
      return false;
    }
    final uri = tab.location;
    if (tab.isBrowse) {
      container.invalidate(homeControllerProvider);
      unawaited(container.read(feedControllerProvider.notifier).refresh());
    } else if (uri.path == '/search') {
      unawaited(
        container
            .read(searchControllerProvider.notifier)
            .search(uri.queryParameters['q'] ?? ''),
      );
    } else if (uri.path == '/history') {
      container.invalidate(historyProvider);
    } else if (uri.path == '/messages') {
      unawaited(container.read(messagesControllerProvider.notifier).refresh());
    } else if (tab.isProfile) {
      final id = UserId(uri.pathSegments.last);
      if (!id.isValid) return false;
      unawaited(
        container.read(profileControllerProvider(id).notifier).refresh(),
      );
    } else if (tab.isLive) {
      final id = RoomId(uri.pathSegments.last);
      if (!id.isValid) return false;
      unawaited(container.read(liveControllerProvider(id).notifier).load());
    } else if (tab.isVideo) {
      final id = VideoId(uri.pathSegments.last);
      container.invalidate(relatedVideosProvider(id));
      final session = container.read(playbackSessionProvider);
      if (session.detail?.summary.id == id) {
        unawaited(session.retry());
      } else {
        container.invalidate(videoDetailProvider(id));
      }
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = observeAccount
        ? ref.watch(
            authControllerProvider.select(
              (auth) => (auth.isSignedIn, auth.mid, auth.userName),
            ),
          )
        : (false, null, null);
    return ProviderScope(
      // Account changes dispose every cached tab's controller/request and
      // rebuild its page. SearchScreen then re-runs its own preserved query.
      key: ValueKey(account),
      overrides: [
        feedControllerProvider.overrideWith(FeedController.new),
        homeControllerProvider.overrideWith2(HomeController.new),
        profileControllerProvider.overrideWith2(ProfileController.new),
        liveControllerProvider.overrideWith2(LiveController.new),
        pgcControllerProvider.overrideWith2(PgcController.new),
        searchControllerProvider.overrideWith(SearchController.new),
        messagesControllerProvider.overrideWith(MessagesController.new),
      ],
      child: Builder(
        builder: (context) => MouseShortcutListener(
          onShortcut: (key) => _shortcut(context, key),
          child: Focus(
            onKeyEvent: (_, event) {
              final key = shortcutKey(event);
              return event is KeyDownEvent &&
                      key != null &&
                      _shortcut(context, key)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored;
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
                                  channel.name ==
                                  uri.queryParameters['channel'],
                            )
                            .firstOrNull ??
                        HomeChannel.recommended;
                    return FeedScreen(
                      key: PageStorageKey('feed-${tab.id}'),
                      channel: channel,
                      initialSection: uri.queryParameters['section'],
                      isSignedIn: account.$1,
                      onLogin: observeAccount
                          ? () => showDialog<void>(
                              context: context,
                              builder: (_) => const AccountDialog(),
                            )
                          : null,
                    );
                  case '/search':
                    return SearchScreen(
                      key: PageStorageKey('search-${tab.id}'),
                      query: uri.queryParameters['q'] ?? '',
                    );
                  case '/history':
                    return HistoryScreen(
                      key: PageStorageKey('history-${tab.id}'),
                    );
                  case '/messages':
                    return MessagesScreen(
                      key: PageStorageKey('messages-${tab.id}'),
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
                    return const StateView.empty(
                      message: '下载功能尚未接入',
                      icon: Icons.download_outlined,
                    );
                  default:
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
                            (_, _) =>
                                const StateView.empty(message: '直播播放服务未配置'),
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
                            )
                          : const StateView.empty(message: '用户地址无效');
                    }
                    if (tab.isVideo) {
                      final id = VideoId(uri.pathSegments.last);
                      return id.isValid
                          ? VideoScreen(
                              key: PageStorageKey('video-${tab.id}'),
                              id: id,
                              initialCid: uri.queryParameters['cid'],
                              playerBuilder: playerBuilder,
                              actionsBuilder: actionsBuilder,
                              menuBuilder: menuBuilder,
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
                              onPartChanged: (part) => context.go(
                                uri
                                    .replace(
                                      queryParameters: {
                                        ...uri.queryParameters,
                                        'cid': part.cid,
                                        'tab': tab.id,
                                      },
                                    )
                                    .toString(),
                              ),
                            )
                          : const StateView.empty(message: '视频地址无效');
                    }
                    return const StateView.empty(message: '找不到这个页面');
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
