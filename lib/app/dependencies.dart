import '../features/downloads/data/android_public_download_storage.dart';

import 'dart:async';
import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/network/api_requests.dart';
import '../domain/media_cdn.dart';
import '../domain/audio_quality.dart';
import '../core/logging/playback_diagnostic_log.dart';
import '../core/platform/window_service.dart';
import '../core/platform/app_icon_service.dart';
import '../core/platform/audio_service_media_controls.dart';
import '../core/platform/system_media_controls.dart';
import '../core/platform/detached_playback_window.dart';
import '../core/platform/file_access_service.dart';
import '../features/comments/data/comment_image_picker.dart';
import '../features/downloads/application/download_controller.dart';
import '../features/downloads/data/api_download_source_repository.dart';
import '../features/downloads/data/sqlite_download_repository.dart';
import '../features/downloads/data/download_file_store.dart';
import '../features/downloads/data/native_download_muxer.dart';
import '../features/playback/data/offline_playback_repository.dart';
import '../core/platform/external_links.dart';
import '../core/platform/system_font_catalog.dart';
import '../core/storage/app_database.dart';
import '../core/storage/credential_store.dart';
import '../core/storage/image_byte_cache.dart';
import '../core/presentation/app_image_provider.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/account_overview_controller.dart';
import '../features/auth/data/api_account_overview_repository.dart';
import '../features/messages/application/messages_controller.dart';
import '../features/messages/data/api_message_repository.dart';
import '../features/image_viewer/application/image_viewer_controller.dart';
import '../features/image_viewer/data/network_original_image_repository.dart';
import '../core/platform/image_export_service.dart';
import '../features/auth/data/session_repository.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/data/api_profile_repository.dart';
import '../features/feed/application/feed_controller.dart';
import '../features/feed/data/api_feed_repository.dart';
import '../features/feed/data/app_recommendation_identity_store.dart';
import '../features/feed/application/app_recommendation_identity.dart';
import '../features/feed/application/home_controller.dart';
import '../features/feed/application/watch_later_removal_controller.dart';
import '../features/feed/data/api_home_repository.dart';
import '../features/feed/application/favorite_folder_controller.dart';
import '../features/feed/data/api_favorite_folder_repository.dart';
import '../features/search/application/search_controller.dart';
import '../features/search/data/api_search_repository.dart';
import '../features/video/application/video_controller.dart';
import '../features/video/application/video_card_controller.dart';
import '../features/video/application/video_card_preview_playback.dart';
import '../features/video/application/video_actions_controller.dart';
import '../features/video/data/api_video_actions_repository.dart';
import '../features/video/application/video_author_controller.dart';
import '../features/video/data/api_video_author_repository.dart';
import '../features/video/application/collection_subscription_controller.dart';
import '../features/video/data/api_collection_subscription_repository.dart';
import '../features/video/application/video_comments_controller.dart';
import '../features/comments/data/api_comments_repository.dart';
import '../features/comments/application/comments_controller.dart';
import '../features/comments/application/comment_link_resolver.dart';
import '../features/comments/data/public_comment_video_link_repository.dart';
import '../features/dynamic/application/dynamic_actions_controller.dart';
import '../features/dynamic/data/api_dynamic_repository.dart';
import '../features/playback/data/api_sponsor_repository.dart';
import '../features/video/data/api_video_repository.dart';
import '../features/video/application/video_extras_controller.dart';
import '../features/video/data/api_video_extras_repository.dart';
import '../features/library/application/library_controller.dart';
import '../features/library/data/sqlite_library_repository.dart';
import '../features/library/data/api_library_repository.dart';
import '../features/playback/application/playback_session.dart';
import '../features/playback/application/playback_manager.dart';
import '../features/playback/application/playback_rate_memory.dart';
import '../features/playback/application/playback_volume_memory.dart';
import '../features/playback/data/api_playback_repository.dart';
import '../features/playback/data/api_video_preview_repository.dart';
import '../features/playback/data/api_playback_history_repository.dart';
import '../features/playback/data/api_content_playback_repository.dart';
import '../features/pgc/application/pgc_controller.dart';
import '../features/pgc/data/api_pgc_repository.dart';
import '../features/pgc/application/pgc_danmaku_controller.dart';
import '../features/pgc/data/api_pgc_danmaku_repository.dart';
import '../features/live/application/live_danmaku_controller.dart';
import '../features/live/data/api_live_danmaku_repository.dart';
import '../features/live/application/live_controller.dart';
import '../features/live/data/api_live_repository.dart';
import '../features/playback/data/local_progress_store.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/application/cdn_speed_test_controller.dart';
import '../features/settings/data/api_cdn_speed_test_repository.dart';
import '../features/settings/application/app_update_controller.dart';
import '../features/settings/data/github_update_repository.dart';
import '../features/settings/data/installed_app_version.dart';
import '../features/settings/data/sqlite_update_check_store.dart';
import '../features/settings/application/system_fonts_controller.dart';
import '../features/settings/data/sqlite_settings_repository.dart';
import 'platform_defaults.dart';
import '../features/playback/application/playback_viewers_controller.dart';
import '../features/playback/application/casting_controller.dart';
import '../features/playback/data/api_cast_media_repository.dart';
import '../features/playback/data/dlna_cast_repository.dart';

class AppDependencies {
  AppDependencies._(
    this.database,
    this.requests,
    this.api,
    this.session,
    this.library,
    this.playback,
    this.playbackVolumeMemory,
    this.window,
    this.sponsorTransport,
    this.playbackLog,
    this.images,
    this.updates,
    this.cardPreviews,
    this.settings,
    this.downloads,
    this.downloadSources,
    this._downloadAccountSubscription,
    this._appRecommendationCredentials,
  );

  final AppDatabase database;
  final ApiRequests requests;
  final BiliApiClient api;
  final SessionRepository session;
  final CredentialStore _appRecommendationCredentials;
  late final appRecommendationIdentity = AppRecommendationIdentityStore(
    database: database,
    credentials: _appRecommendationCredentials,
    accountScope: () => session.accountScope,
    accountChanges: session.changes,
    sessionCredentials: session,
  );
  final SqliteLibraryRepository library;
  final PlaybackManager playback;
  final PlaybackVolumeMemory playbackVolumeMemory;
  final WindowService window;
  final playbackWindow = DesktopPlaybackWindowController();
  final DioApiTransport sponsorTransport;
  final PlaybackDiagnosticLog? playbackLog;
  final AppImageCache images;
  final GitHubUpdateRepository updates;
  final VideoCardPreviewPlayback cardPreviews;
  final SqliteSettingsRepository settings;
  final SqliteDownloadRepository downloads;
  final ApiDownloadSourceRepository downloadSources;
  final StreamSubscription<Object?> _downloadAccountSubscription;
  final files = const FileAccessService();
  Future<void>? _closing;

  static Future<AppDependencies> create({
    CredentialStore? credentials,
    CredentialStore? appRecommendationCredentials,
    AppDatabase? databaseOverride,
    WindowService? windowOverride,
  }) async {
    initializePlayerBackend();
    final window = windowOverride ?? WindowService();
    await window.initialize();
    final database = databaseOverride ?? await AppDatabase.open();
    await database.readSetting('schema_probe');
    final requests = ApiRequests();
    final images = AppImageCache(
      ImageByteCache(
        enabled: false,
        directory: () async {
          final root = await getApplicationCacheDirectory();
          return Directory(path.join(root.path, 'public_images_v1'));
        },
      ),
    );
    final api = BiliApiClient(sessionProvider: requests);
    late final SessionRepository session;
    late final AppDependencies dependencies;
    final library = SqliteLibraryRepository(
      database,
      accountScope: () => session.accountScope,
    );
    final sponsorTransport = DioApiTransport();
    final playbackLog = await PlaybackDiagnosticLog.create();
    final settings = SqliteSettingsRepository(
      database,
      defaultNavigationMode: defaultWorkspaceNavigationMode,
      defaultShortcuts: defaultShortcuts,
      defaultHighEnergyProgressEnabled: defaultHighEnergyProgressEnabled,
      defaultDanmakuArea: defaultDanmakuArea,
      defaultDanmakuFontScale: defaultDanmakuFontScale,
      defaultPlayerControlsMode: defaultPlayerControlsMode,
      defaultVideoCardHoverPlayback: defaultVideoCardHoverPlayback,
    );
    Future<MediaCdnPreference> cdnPreference() async =>
        (await settings.load()).mediaCdn;
    Future<AudioQualityPreference> audioQualityPreference() async =>
        (await settings.load()).preferredAudioQuality;
    final playbackRepository = ApiPlaybackRepository(
      api,
      requests,
      cdnPreference: cdnPreference,
      audioQualityPreference: audioQualityPreference,
      imageDimensions: images.dimensions,
    );
    final downloadSources = ApiDownloadSourceRepository(
      api,
      requests,
      accountScope: () => session.accountScope,
      cdnPreference: cdnPreference,
    );
    final downloads = SqliteDownloadRepository(
      database,
      downloadSources,
      muxer: NativeDownloadMuxer(),
      publicStorage: Platform.isAndroid
          ? const AndroidPublicDownloadStorage()
          : null,
      defaultDirectory: const FileAccessService().defaultDownloadDirectory,
      files: DownloadFileStore(
        trustedDocumentsDirectory:
            const FileAccessService().trustedDownloadDocumentsDirectory,
      ),
    );
    final cardPreviews = VideoCardPreviewPlayback(
      createEngine: () => MediaKitEngine(onDiagnostic: playbackLog?.record),
    );
    final playbackRateMemory = PlaybackRateMemory();
    final playbackVolumeMemory = PlaybackVolumeMemory(
      savedVolume: await settings.loadRememberedVolume(),
      saveVolume: settings.saveRememberedVolume,
      onSaveError: (error, stack) => FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playback volume persistence',
        ),
      ),
    );
    SystemMediaControls? systemMedia;
    try {
      systemMedia = await createSystemMediaControls();
    } catch (_) {
      reportSystemMediaFailure();
    }
    final playback = PlaybackManager(
      systemMediaControls: systemMedia,
      createSession: () {
        final repository = OfflinePlaybackRepository(
          downloads: downloads,
          network: playbackRepository,
          networkMetadata: playbackRepository,
          networkContent: ApiContentPlaybackRepository(
            PgcClient(api),
            LiveClient(api),
            requests,
            cdnPreference: cdnPreference,
            audioQualityPreference: audioQualityPreference,
          ),
        );
        return PlaybackSession(
          rateMemory: playbackRateMemory,
          volumeMemory: playbackVolumeMemory,
          sponsorRepository: ApiSponsorRepository(
            SponsorBlockClient(sponsorTransport),
          ),
          engine: MediaKitEngine(onDiagnostic: playbackLog?.record),
          repository: repository,
          historyRepository: ApiPlaybackHistoryRepository(
            PlaybackHistoryClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
          sessionEpoch: () => requests.sessionEpoch,
          metadataRepository: repository,
          contentRepository: repository.content,
          accountScope: () => session.accountScope,
          progress: LocalProgressStore(
            readProgress: library.resumePosition,
            writeProgress:
                (scope, video, part, position, duration, {episodeId}) =>
                    library.saveProgress(
                      scope: scope,
                      video: video,
                      part: part,
                      position: position,
                      duration: duration,
                      episodeId: episodeId,
                    ),
          ),
        );
      },
    );
    session = SessionRepository(
      loadAppDevice: () => dependencies.appRecommendationIdentity.deviceId(),
      api: api,
      requests: requests,
      credentials: credentials ?? SystemCredentialStore(),
      onSessionChanged: (scope) async {
        try {
          await downloads.sessionChanged();
        } finally {
          await images.clearSession(scope);
          try {
            await cardPreviews.stop();
            await playback.stop();
          } finally {
            if (scope != 'guest') await database.clearPrivateHistory(scope);
          }
        }
      },
    );
    await downloads.initialize();
    var downloadAccount = (session.accountScope, requests.sessionEpoch);
    final downloadAccountSubscription = session.changes.listen((_) {
      final next = (session.accountScope, requests.sessionEpoch);
      if (next != downloadAccount) {
        downloadAccount = next;
        // The repository publishes storage errors in the queue state.
        unawaited(downloads.sessionChanged().catchError((Object _) {}));
      }
    });
    dependencies = AppDependencies._(
      database,
      requests,
      api,
      session,
      library,
      playback,
      playbackVolumeMemory,
      window,
      sponsorTransport,
      playbackLog,
      images,
      GitHubUpdateRepository(versionLoader: loadInstalledAppVersion),
      cardPreviews,
      settings,
      downloads,
      downloadSources,
      downloadAccountSubscription,
      appRecommendationCredentials ??
          SystemCredentialStore(keyPrefix: 'bilisail.app_recommendation.v1'),
    );
    return dependencies;
  }

  Widget scope(Widget child) {
    final live = ApiLiveRepository(
      LiveClient(api),
      requests,
      accountScope: () => session.accountScope,
    );
    return ProviderScope(
      overrides: [
        commentVideoLinkRepositoryProvider.overrideWithValue(
          PublicCommentVideoLinkRepository(api, requests),
        ),
        downloadRepositoryProvider.overrideWithValue(downloads),
        publicDownloadStorageProvider.overrideWithValue(
          Platform.isAndroid ? const AndroidPublicDownloadStorage() : null,
        ),
        downloadSourceRepositoryProvider.overrideWithValue(downloadSources),
        sessionEpochProvider.overrideWithValue(() => requests.sessionEpoch),
        castMediaRepositoryProvider.overrideWithValue(
          ApiCastMediaRepository(
            api,
            requests,
            credentials: () => session.appCredentials,
          ),
        ),
        castDeviceRepositoryFactoryProvider.overrideWithValue(
          DlnaCastRepository.new,
        ),
        castLifetimeTrackerProvider.overrideWithValue(requests.trackLifetime),
        playbackViewerRepositoryProvider.overrideWithValue(
          ApiPlaybackRepository(api, requests),
        ),
        appUpdateRepositoryProvider.overrideWithValue(updates),
        updateCheckStoreProvider.overrideWithValue(
          SqliteUpdateCheckStore(database),
        ),
        appUpdateLinkOpenerProvider.overrideWith(
          (ref) => ref.watch(externalLinkOpenerProvider),
        ),
        accountMessageIndicatorProvider.overrideWith((ref) {
          final unread = ref.watch(unreadMessagesProvider);
          return AccountMessageIndicator(
            count: unread.isLoading || unread.hasError
                ? 0
                : unread.value?.values.fold<int>(0, (a, b) => a + b) ?? 0,
            failed: unread.hasError,
            refresh: () => ref.invalidate(unreadMessagesProvider),
          );
        }),
        accountOverviewRepositoryProvider.overrideWithValue(
          ApiAccountOverviewRepository(AccountClient(api), requests),
        ),
        messageRepositoryProvider.overrideWithValue(
          ApiMessageRepository(
            MessageClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        pgcRepositoryProvider.overrideWithValue(
          ApiPgcRepository(
            PgcClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        pgcDanmakuRepositoryProvider.overrideWithValue(
          ApiPgcDanmakuRepository(
            VideoActionsClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        liveRepositoryProvider.overrideWithValue(live),
        liveViewerRepositoryProvider.overrideWithValue(live),
        liveChatRepositoryProvider.overrideWithValue(live),
        liveDanmakuRepositoryProvider.overrideWithValue(
          ApiLiveDanmakuRepository(
            LiveClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        feedRepositoryProvider.overrideWithValue(
          ApiFeedRepository(
            api,
            requests,
            appIdentity: appRecommendationIdentity,
          ),
        ),
        appRecommendationIdentityRepositoryProvider.overrideWithValue(
          appRecommendationIdentity,
        ),
        homeRepositoryProvider.overrideWithValue(
          ApiHomeRepository(
            HomeClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        favoriteFolderRepositoryProvider.overrideWithValue(
          ApiFavoriteFolderRepository(
            FavoriteFolderClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        searchRepositoryProvider.overrideWithValue(
          ApiSearchRepository(api, requests),
        ),
        profileRepositoryProvider.overrideWithValue(
          ApiProfileRepository(
            ProfileClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        videoActionsRepositoryProvider.overrideWithValue(
          ApiVideoActionsRepository(
            VideoActionsClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        videoRepositoryProvider.overrideWithValue(
          ApiVideoRepository(api, requests),
        ),
        videoCardPreviewPlaybackProvider.overrideWithValue(cardPreviews),
        videoCardWatchLaterAddedProvider.overrideWith(
          (ref) =>
              (id) => ref
                  .read(
                    watchLaterRemovalProvider(session.accountScope).notifier,
                  )
                  .restore(id.value),
        ),
        videoCardPlaybackRepositoryProvider.overrideWithValue(
          ApiVideoPreviewRepository(
            api,
            requests,
            cdnPreference: () async => (await settings.load()).mediaCdn,
          ),
        ),
        collectionSubscriptionRepositoryProvider.overrideWithValue(
          ApiCollectionSubscriptionRepository(
            CollectionSubscriptionClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        videoAuthorRepositoryProvider.overrideWithValue(
          ApiVideoAuthorRepository(
            VideoAuthorClient(api),
            FollowGroupClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        videoExtrasRepositoryProvider.overrideWithValue(
          ApiVideoExtrasRepository(api, requests),
        ),
        commentImagePickerProvider.overrideWithValue(pickCommentImages),
        videoCommentsRepositoryProvider.overrideWithValue(
          ApiCommentsRepository(
            api,
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        commentsRepositoryProvider.overrideWith(
          (ref, type) => ApiCommentsRepository(
            api,
            requests,
            type: type,
            accountScope: () => session.accountScope,
          ),
        ),
        dynamicRepositoryProvider.overrideWithValue(
          ApiDynamicRepository(
            DynamicClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        libraryRepositoryProvider.overrideWithValue(
          ApiLibraryRepository(
            WatchHistoryClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        settingsRepositoryProvider.overrideWithValue(settings),
        appIconServiceProvider.overrideWithValue(const NativeAppIconService()),
        cdnSpeedTestRepositoryProvider.overrideWithValue(
          ApiCdnSpeedTestRepository(api, requests),
        ),
        settingsDefaultsProvider.overrideWithValue(settings.defaults),
        systemFontCatalogProvider.overrideWithValue(
          const NativeSystemFontCatalog(),
        ),
        authRepositoryProvider.overrideWithValue(session),
        originalImageRepositoryProvider.overrideWithValue(
          NetworkOriginalImageRepository(),
        ),
        imageExportServiceProvider.overrideWithValue(
          const NativeImageExportService(),
        ),
        imageViewerSessionProvider.overrideWith(
          (ref) => ref.watch(
            authControllerProvider.select((state) => (state.status, state.mid)),
          ),
        ),
        playbackManagerProvider.overrideWithValue(playback),
      ],
      child: child,
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    updates.close();
    try {
      await _downloadAccountSubscription.cancel();
      await downloads.close();
      await cardPreviews.close();
      // Flush the final history observation while its account epoch is valid.
      await playback.close();
    } finally {
      try {
        // SDK-managed HWNDs must retire while the shared engine and its message
        // loop are still alive, after their Flutter views have unmounted.
        await playbackWindow.close();
      } finally {
        requests.advanceSession();
        try {
          try {
            await appRecommendationIdentity.close();
          } finally {
            await session.dispose();
          }
        } finally {
          try {
            sponsorTransport.close();
            api.close();
          } finally {
            try {
              try {
                await playbackVolumeMemory.flush();
              } finally {
                await database.close();
              }
            } finally {
              try {
                await playbackLog?.close();
                await images.close();
              } finally {
                await window.dispose();
              }
            }
          }
        }
      }
    }
  }
}
