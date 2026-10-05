import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/platform/desktop_window_chrome.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/account_button.dart';
import '../features/feed/application/feed_controller.dart';
import '../features/search/application/search_controller.dart';
import '../features/video/application/video_controller.dart';
import '../features/video/application/video_actions_controller.dart';
import '../features/video/presentation/video_actions_bar.dart';
import '../features/video/presentation/video_danmaku_composer.dart';
import '../features/video/presentation/video_comments_panel.dart';
import '../features/pgc/domain/pgc_repository.dart';
import '../features/pgc/presentation/pgc_danmaku_composer.dart';
import '../features/live/presentation/live_player_danmaku.dart';
import '../features/live/presentation/live_danmaku_composer.dart';
import '../features/playback/domain/content_playback.dart';
import '../domain/video.dart';
import '../features/video/application/video_extras_controller.dart';
import '../features/library/application/library_controller.dart';
import '../features/playback/presentation/playback_panel.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/domain/app_settings.dart';
import '../shared/ui/app_notice.dart';
import '../shared/ui/smooth_scroll_behavior.dart';
import 'image_cache_binding.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';

class BiliApp extends ConsumerStatefulWidget {
  const BiliApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  ConsumerState<BiliApp> createState() => _BiliAppState();
}

VideoDetail _episodeDetail(PgcSeason season, PgcEpisode episode) => VideoDetail(
  summary: VideoSummary(
    id: VideoId(episode.bvid ?? ''),
    title: '${season.title} · ${episode.displayTitle}',
    coverUrl: (episode.coverUrl ?? season.coverUrl)?.toString() ?? '',
    author: season.title,
    duration: episode.duration ?? Duration.zero,
  ),
  description: season.description,
  aid: episode.aid,
  parts: [
    VideoPart(
      cid: episode.cid ?? '',
      page: 1,
      title: episode.displayTitle,
      duration: episode.duration ?? Duration.zero,
    ),
  ],
);

class _BiliAppState extends ConsumerState<BiliApp> {
  late final GoRouter _router;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _router = createBiliRouter(
      pgcPlayerBuilder: (context, season, episode) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              const AppSettings.defaults();
          final detail = _episodeDetail(season, episode);
          return PlaybackPanel(
            detail: detail,
            part: detail.parts.first,
            target: PgcPlaybackTarget(episode.episodeId, cid: episode.cid),
            title: '${season.title} · ${episode.displayTitle}',
            settings: settings,
            danmakuComposerBuilder: (context) => PgcDanmakuComposer(
              episode: episode,
              onLogin: () => showDialog<void>(
                context: context,
                builder: (_) => const AccountDialog(),
              ),
            ),
            window: widget.dependencies.window,
            onToggleComments: () => ref
                .read(settingsControllerProvider.notifier)
                .setDanmakuEnabled(!settings.danmakuEnabled),
          );
        },
      ),
      pgcCommentsBuilder: (context, season, episode) => VideoCommentsPanel(
        detail: _episodeDetail(season, episode),
        onOpenUser: (user) => context.go('/user/${user.value}'),
        onLogin: () => showDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
      ),
      livePlayerBuilder: (context, room) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              const AppSettings.defaults();
          final requestedId =
              LiveDanmakuRoomScope.requestedIdOf(context) ?? room.id;
          return PlaybackPanel(
            target: LivePlaybackTarget(room.id.value),
            title: room.title,
            danmakuComposerBuilder: (context) => LiveDanmakuComposer(
              roomId: requestedId,
              playerStyle: true,
              onLogin: () => showDialog<void>(
                context: context,
                builder: (_) => const AccountDialog(),
              ),
            ),
            settings: settings,
            danmakuOverlayBuilder: (_) =>
                LivePlayerDanmaku(roomId: requestedId, settings: settings),
            window: widget.dependencies.window,
            onToggleComments: () => ref
                .read(settingsControllerProvider.notifier)
                .setDanmakuEnabled(!settings.danmakuEnabled),
          );
        },
      ),
      liveComposerBuilder: (context, roomId) => LiveDanmakuComposer(
        roomId: roomId,
        onLogin: () => showDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
      ),
      accountBuilder: (context) => AccountButton(
        onOpenUser: (user) => context.go('/user/${user.value}'),
        onNavigate: (path) => context.go(path),
      ),
      actionsBuilder: (context, detail, part) => VideoActionsBar(
        detail: detail,
        onLogin: () => showDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
      ),
      menuBuilder: (context, detail, part) => VideoActionsBar(
        detail: detail,
        menuOnly: true,
        onLogin: () => showDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
        onReload: () {
          ref.invalidate(relatedVideosProvider(detail.summary.id));
          final session = widget.dependencies.playback;
          if (session.detail?.summary.id == detail.summary.id &&
              session.part?.cid == part.cid) {
            unawaited(session.retry());
          }
        },
      ),
      windowControlsBuilder: widget.dependencies.window.hasCustomTitleBar
          ? (_) => const DesktopWindowControls()
          : null,
      dragRegionBuilder: widget.dependencies.window.hasCustomTitleBar
          ? (_, child) => DesktopDragRegion(child: child)
          : null,
      playerBuilder: (context, detail, part) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              const AppSettings.defaults();
          return PlaybackPanel(
            detail: detail,
            part: part,
            settings: settings,
            danmakuComposerBuilder: (context) => VideoDanmakuComposer(
              detail: detail,
              part: part,
              onLogin: () => showDialog<void>(
                context: context,
                builder: (_) => const AccountDialog(),
              ),
            ),
            window: widget.dependencies.window,
            onToggleComments: () => ref
                .read(settingsControllerProvider.notifier)
                .setDanmakuEnabled(!settings.danmakuEnabled),
          );
        },
      ),
    );
    _router.routeInformationProvider.addListener(_routeChanged);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.dependencies.close();
        return AppExitResponse.exit;
      },
    );
    unawaited(widget.dependencies.session.restore());
  }

  void _routeChanged() {
    if (_router.routeInformationProvider.value.uri.path == '/history') {
      ref.invalidate(historyProvider);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.routeInformationProvider.removeListener(_routeChanged);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.isSignedIn != next.isSignedIn ||
          previous?.mid != next.mid ||
          previous?.userName != next.userName) {
        unawaited(
          widget.dependencies.images.changeScope(
            widget.dependencies.session.accountScope,
          ),
        );
        ref.invalidate(feedControllerProvider);
        ref.invalidate(searchControllerProvider);
        ref.invalidate(videoDetailProvider);
        ref.invalidate(videoActionsControllerProvider);
        ref.invalidate(relatedVideosProvider);
        ref.invalidate(videoCommentsProvider);
        ref.invalidate(historyProvider);
      }
    });
    final settings =
        ref.watch(settingsControllerProvider).value ??
        const AppSettings.defaults();
    return ImageCacheBinding(
      cache: widget.dependencies.images,
      child: MaterialApp.router(
        title: 'Bili Lite',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const SmoothScrollBehavior(),
        builder: AppNoticeHost.builder,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: BiliTheme.light(font: settings.font),
        darkTheme: BiliTheme.dark(font: settings.font),
        themeMode: switch (settings.theme) {
          AppThemePreference.system => ThemeMode.system,
          AppThemePreference.light => ThemeMode.light,
          AppThemePreference.dark => ThemeMode.dark,
        },
        routerConfig: _router,
      ),
    );
  }
}
