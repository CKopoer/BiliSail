import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;

import '../shared/ui/app_dialog.dart';
import '../core/platform/desktop_window_chrome.dart';
import '../core/platform/detached_playback_window.dart';
import '../core/platform/window_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/downloads/domain/download_models.dart';
import '../features/downloads/presentation/download_dialog.dart';
import '../features/auth/presentation/account_button.dart';
import '../features/feed/application/feed_controller.dart';
import '../features/feed/application/watch_later_removal_controller.dart';
import '../features/search/application/search_controller.dart';
import '../features/video/application/video_controller.dart';
import '../features/video/application/video_card_controller.dart';
import '../features/video/application/watch_later_queue_registry.dart';
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
import '../features/playback/application/playback_session.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/presentation/app_update_host.dart';
import '../features/settings/domain/app_settings.dart';
import '../shared/ui/app_notice.dart';
import '../shared/ui/video_card_interaction_scope.dart';
import '../shared/ui/smooth_scroll_behavior.dart';
import '../core/presentation/app_input_host.dart';
import '../core/presentation/android_system_ui.dart';
import '../core/presentation/window_orientation_host.dart';
import 'shortcut_coordinator.dart';
import 'image_cache_binding.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';
import 'workspace_playback_window.dart';

class BiliApp extends ConsumerStatefulWidget {
  const BiliApp({
    super.key,
    required this.dependencies,
    this.videoComposition = const FlutterVideoCompositionAdapter(),
  });
  final AppDependencies dependencies;
  final VideoCompositionAdapter videoComposition;
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
  final _input = ShortcutCoordinator();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _router = createBiliRouter(
      onExitRequested: widget.dependencies.close,
      onActivateBrowser: () => unawaited(widget.dependencies.window.activate()),
      playbackWindowBuilder: DetachedPlaybackWindow.isSupported
          ? (
              context, {
              required child,
              required playback,
              required keepPlaybackMounted,
              required activationToken,
              required onClose,
              required onBack,
              required onHome,
              required onError,
            }) => DesktopPlaybackWindow(
              keepPlaybackMounted: keepPlaybackMounted,
              controller: widget.dependencies.playbackWindow,
              activationToken: activationToken,
              onCloseRequested: onClose,
              onError: onError,
              playback: playback == null
                  ? null
                  : WorkspacePlaybackWindow(
                      theme: Theme.of(context),
                      shortcuts:
                          (ref.read(settingsControllerProvider).value ??
                                  ref.read<AppSettings>(
                                    settingsDefaultsProvider,
                                  ))
                              .shortcuts,
                      onClose: onClose,
                      onBack: onBack,
                      onHome: onHome,
                      onActivateBrowser: () =>
                          unawaited(widget.dependencies.window.activate()),
                      child: playback,
                    ),
              child: child,
            )
          : null,
      inputObserver: _input.routes,
      onOpenDownloadDirectory: widget.dependencies.files.canOpenDirectory
          ? widget.dependencies.files.openDirectory
          : null,
      allowCustomDownloadDirectory:
          widget.dependencies.files.canChooseDownloadDirectory,
      downloadCoverProvider: (task) =>
          FileImage(File(path.join(task.directory, 'cover.img'))),
      onDownloadSeason: (context, season, selected) {
        final settings =
            ref.read(settingsControllerProvider).value ??
            ref.read<AppSettings>(settingsDefaultsProvider);
        final items = DownloadItem.fromSeason(season);
        final current = items
            .where((item) => item.episodeId == selected?.episodeId)
            .firstOrNull;
        unawaited(
          showDownloadDialog(
            context,
            items: items,
            initialKey: current?.key,
            initialSelection: DownloadSelection(
              quality: settings.preferredQuality,
              codec: settings.preferredVideoCodec,
            ),
          ),
        );
      },
      offlinePlayerBuilder: (context, task) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              ref.read<AppSettings>(settingsDefaultsProvider);
          return PlaybackPanel(
            detail: VideoDetail(
              summary: task.item.video,
              description: '',
              parts: [task.item.part],
              aid: task.item.aid,
            ),
            part: task.item.part,
            target: OfflinePlaybackTarget(
              task.id,
              episodeId: task.item.episodeId,
            ),
            title: '${task.item.video.title} · ${task.item.part.title}',
            settings: settings,
            window:
                WindowServiceScope.maybeOf(context) ??
                widget.dependencies.window,
            onToggleComments: () => ref
                .read(settingsControllerProvider.notifier)
                .setDanmakuEnabled(!settings.danmakuEnabled),
          );
        },
      ),
      pgcPlayerBuilder: (context, season, episode) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              ref.read<AppSettings>(settingsDefaultsProvider);
          final detail = _episodeDetail(season, episode);
          return PlaybackPanel(
            detail: detail,
            part: detail.parts.first,
            target: PgcPlaybackTarget(
              episode.episodeId,
              cid: episode.cid,
              seasonId: season.id.value,
            ),
            title: '${season.title} · ${episode.displayTitle}',
            settings: settings,
            danmakuComposerBuilder: (context) => PgcDanmakuComposer(
              episode: episode,
              onLogin: () => showAppDialog<void>(
                context: context,
                builder: (_) => const AccountDialog(),
              ),
            ),
            window:
                WindowServiceScope.maybeOf(context) ??
                widget.dependencies.window,
            onToggleComments: () => ref
                .read(settingsControllerProvider.notifier)
                .setDanmakuEnabled(!settings.danmakuEnabled),
          );
        },
      ),
      pgcCommentsBuilder: (context, season, episode) => VideoCommentsPanel(
        detail: _episodeDetail(season, episode),
        onOpenUser: (user) => context.go('/user/${user.value}'),
        onLogin: () => showAppDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
      ),
      livePlayerBuilder: (context, room) => Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsControllerProvider).value ??
              ref.read<AppSettings>(settingsDefaultsProvider);
          final requestedId =
              LiveDanmakuRoomScope.requestedIdOf(context) ?? room.id;
          return LivePlayerDanmaku(
            roomId: requestedId,
            settings: settings,
            builder: (context, overlay) => PlaybackPanel(
              target: LivePlaybackTarget(room.id.value),
              title: room.title,
              danmakuComposerBuilder: (context) => LiveDanmakuComposer(
                roomId: requestedId,
                playerStyle: true,
                onLogin: () => showAppDialog<void>(
                  context: context,
                  builder: (_) => const AccountDialog(),
                ),
              ),
              settings: settings,
              danmakuOverlayBuilder: (_) => overlay,
              window:
                  WindowServiceScope.maybeOf(context) ??
                  widget.dependencies.window,
              onToggleComments: () => ref
                  .read(settingsControllerProvider.notifier)
                  .setDanmakuEnabled(!settings.danmakuEnabled),
            ),
          );
        },
      ),
      liveComposerBuilder: (context, roomId) => LiveDanmakuComposer(
        roomId: roomId,
        onLogin: () => showAppDialog<void>(
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
        onDownload: () => _downloadVideo(context, detail, part),
        onLogin: () => showAppDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
      ),
      menuBuilder: (context, detail, part) => VideoActionsBar(
        detail: detail,
        onDownload: () => _downloadVideo(context, detail, part),
        menuOnly: true,
        onLogin: () => showAppDialog<void>(
          context: context,
          builder: (_) => const AccountDialog(),
        ),
        onReload: () {
          ref.invalidate(relatedVideosProvider(detail.summary.id));
          final pageContainer = ProviderScope.containerOf(
            context,
            listen: false,
          );
          pageContainer.invalidate(videoTagsProvider(detail.summary.id));
          final session = pageContainer.read(playbackSessionProvider);
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
              ref.read<AppSettings>(settingsDefaultsProvider);
          return PlaybackPanel(
            detail: detail,
            part: part,
            settings: settings,
            danmakuComposerBuilder: (context) => VideoDanmakuComposer(
              detail: detail,
              part: part,
              onLogin: () => showAppDialog<void>(
                context: context,
                builder: (_) => const AccountDialog(),
              ),
            ),
            window:
                WindowServiceScope.maybeOf(context) ??
                widget.dependencies.window,
            onToggleComments: () => ref
                .read(settingsControllerProvider.notifier)
                .setDanmakuEnabled(!settings.danmakuEnabled),
          );
        },
      ),
    );
    _router.routeInformationProvider.addListener(_routeChanged);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused &&
            widget.dependencies.files.pauseDownloadsInBackground) {
          unawaited(widget.dependencies.downloads.pauseAll());
        }
      },
      onExitRequested: () async {
        await widget.dependencies.close();
        return AppExitResponse.exit;
      },
    );
    unawaited(widget.dependencies.session.restore());
  }

  void _downloadVideo(
    BuildContext context,
    VideoDetail detail,
    VideoPart selected,
  ) {
    final settings =
        ref.read(settingsControllerProvider).value ??
        ref.read<AppSettings>(settingsDefaultsProvider);
    final items = DownloadItem.fromVideo(detail);
    final current = items
        .where((item) => item.part.cid == selected.cid)
        .firstOrNull;
    unawaited(
      showDownloadDialog(
        context,
        items: items,
        initialKey: current?.key,
        initialSelection: DownloadSelection(
          quality: settings.preferredQuality,
          codec: settings.preferredVideoCodec,
        ),
      ),
    );
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
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      // Session epoch may change while the visible MID and name stay the same.
      ref.invalidate(watchLaterQueueRegistryProvider);
      if (previous?.isSignedIn != next.isSignedIn ||
          previous?.mid != next.mid ||
          previous?.userName != next.userName) {
        unawaited(
          widget.dependencies.images.changeScope(
            widget.dependencies.session.accountScope,
          ),
        );
        ref.invalidate(feedControllerProvider);
        ref.invalidate(watchLaterRemovalProvider);
        ref.invalidate(searchControllerProvider);
        ref.invalidate(videoDetailProvider);
        ref.invalidate(videoActionsControllerProvider);
        ref.invalidate(relatedVideosProvider);
        ref.invalidate(videoTagsProvider);
        ref.invalidate(videoCommentsProvider);
        ref.invalidate(historyProvider);
      }
    });
    final settings =
        ref.watch(settingsControllerProvider).value ??
        ref.watch<AppSettings>(settingsDefaultsProvider);
    final cardInteractions = ref.watch(videoCardControllerProvider);
    _input.configure(settings.shortcuts);
    widget.dependencies.playbackVolumeMemory.configure(
      enabled: settings.rememberVolumeGlobally,
      defaultVolume: settings.defaultVolume,
    );
    return ImageCacheBinding(
      cache: widget.dependencies.images,
      child: MaterialApp.router(
        title: 'BiliSail',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const SmoothScrollBehavior(),
        builder: (context, child) => WindowOrientationHost(
          window: widget.dependencies.window,
          child: VideoCompositionScope(
            adapter: widget.videoComposition,
            child: SmoothScrollScope(
              dampingRatio: settings.wheelDampingRatio,
              child: AppInputHost<Object>(
                dispatcher: _input,
                routes: _input.routes,
                onEditingChanged: widget.dependencies.window.setTextInputActive,
                child: AppUpdateHost(
                  navigatorKey: _router.routerDelegate.navigatorKey,
                  child: AppNoticeHost(
                    child: VideoCardInteractionScope(
                      interactions: cardInteractions,
                      onNotice: showAppNotice,
                      hoverPlaybackEnabled: settings.videoCardHoverPlayback,
                      child: AndroidSystemUi(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: BiliTheme.light(
          font: settings.font,
          systemFontFamily: settings.systemFontFamily,
        ),
        darkTheme: BiliTheme.dark(
          font: settings.font,
          systemFontFamily: settings.systemFontFamily,
        ),
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
