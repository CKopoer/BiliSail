import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/network/api_requests.dart';
import '../domain/media_cdn.dart';
import '../core/logging/playback_diagnostic_log.dart';
import '../core/platform/window_service.dart';
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
import '../features/auth/data/session_repository.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/data/api_profile_repository.dart';
import '../features/feed/application/feed_controller.dart';
import '../features/feed/data/api_feed_repository.dart';
import '../features/feed/application/home_controller.dart';
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
import '../features/video/data/api_video_comments_repository.dart';
import '../features/playback/data/api_sponsor_repository.dart';
import '../features/video/data/api_video_repository.dart';
import '../features/video/application/video_extras_controller.dart';
import '../features/video/data/api_video_extras_repository.dart';
import '../features/library/application/library_controller.dart';
import '../features/library/data/sqlite_library_repository.dart';
import '../features/playback/application/playback_session.dart';
import '../features/playback/application/playback_manager.dart';
import '../features/playback/data/api_playback_repository.dart';
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
import '../features/settings/application/app_update_controller.dart';
import '../features/settings/data/github_update_repository.dart';
import '../features/settings/data/installed_app_version.dart';
import '../features/settings/data/sqlite_update_check_store.dart';
import '../features/settings/application/system_fonts_controller.dart';
import '../features/settings/data/sqlite_settings_repository.dart';
import 'platform_defaults.dart';

class AppDependencies {
  AppDependencies._(
    this.database,
    this.requests,
    this.api,
    this.session,
    this.library,
    this.playback,
    this.window,
    this.sponsorTransport,
    this.playbackLog,
    this.images,
    this.updates,
    this.cardPreviews,
    this.settings,
  );

  final AppDatabase database;
  final ApiRequests requests;
  final BiliApiClient api;
  final SessionRepository session;
  final SqliteLibraryRepository library;
  final PlaybackManager playback;
  final WindowService window;
  final DioApiTransport sponsorTransport;
  final PlaybackDiagnosticLog? playbackLog;
  final AppImageCache images;
  final GitHubUpdateRepository updates;
  final VideoCardPreviewPlayback cardPreviews;
  final SqliteSettingsRepository settings;
  bool _closed = false;

  static Future<AppDependencies> create() async {
    initializePlayerBackend();
    final window = WindowService();
    await window.initialize();
    final database = await AppDatabase.open();
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
    final library = SqliteLibraryRepository(
      database,
      accountScope: () => session.accountScope,
    );
    final sponsorTransport = DioApiTransport();
    final playbackLog = await PlaybackDiagnosticLog.create();
    final settings = SqliteSettingsRepository(
      database,
      defaultNavigationMode: defaultWorkspaceNavigationMode,
    );
    Future<MediaCdnPreference> cdnPreference() async =>
        (await settings.load()).mediaCdn;
    final playbackRepository = ApiPlaybackRepository(
      api,
      requests,
      cdnPreference: cdnPreference,
    );
    final cardPreviews = VideoCardPreviewPlayback(
      createEngine: () => MediaKitEngine(onDiagnostic: playbackLog?.record),
    );
    final playback = PlaybackManager(
      createSession: () => PlaybackSession(
        sponsorRepository: ApiSponsorRepository(
          SponsorBlockClient(sponsorTransport),
        ),
        engine: MediaKitEngine(onDiagnostic: playbackLog?.record),
        repository: playbackRepository,
        historyRepository: ApiPlaybackHistoryRepository(
          PlaybackHistoryClient(api),
          requests,
          accountScope: () => session.accountScope,
        ),
        sessionEpoch: () => requests.sessionEpoch,
        metadataRepository: playbackRepository,
        contentRepository: ApiContentPlaybackRepository(
          PgcClient(api),
          LiveClient(api),
          requests,
          cdnPreference: cdnPreference,
        ),
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
      ),
    );
    session = SessionRepository(
      api: api,
      requests: requests,
      credentials: SystemCredentialStore(),
      onSessionChanged: (scope) async {
        await images.clearSession(scope);
        try {
          await cardPreviews.stop();
          await playback.stop();
        } finally {
          if (scope != 'guest') await database.clearPrivateHistory(scope);
        }
      },
    );
    return AppDependencies._(
      database,
      requests,
      api,
      session,
      library,
      playback,
      window,
      sponsorTransport,
      playbackLog,
      images,
      GitHubUpdateRepository(versionLoader: loadInstalledAppVersion),
      cardPreviews,
      settings,
    );
  }

  Widget scope(Widget child) {
    final live = ApiLiveRepository(
      LiveClient(api),
      requests,
      accountScope: () => session.accountScope,
    );
    return ProviderScope(
      overrides: [
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
        liveChatRepositoryProvider.overrideWithValue(live),
        liveDanmakuRepositoryProvider.overrideWithValue(
          ApiLiveDanmakuRepository(
            LiveClient(api),
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        feedRepositoryProvider.overrideWithValue(
          ApiFeedRepository(api, requests),
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
        videoCardPlaybackRepositoryProvider.overrideWithValue(
          ApiPlaybackRepository(
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
        videoCommentsRepositoryProvider.overrideWithValue(
          ApiVideoCommentsRepository(
            api,
            requests,
            accountScope: () => session.accountScope,
          ),
        ),
        libraryRepositoryProvider.overrideWithValue(library),
        settingsRepositoryProvider.overrideWithValue(settings),
        systemFontCatalogProvider.overrideWithValue(
          const NativeSystemFontCatalog(),
        ),
        authRepositoryProvider.overrideWithValue(session),
        originalImageRepositoryProvider.overrideWithValue(
          NetworkOriginalImageRepository(),
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    updates.close();
    try {
      await cardPreviews.close();
      // Flush the final history observation while its account epoch is valid.
      await playback.close();
    } finally {
      requests.advanceSession();
      try {
        await session.dispose();
      } finally {
        try {
          sponsorTransport.close();
          api.close();
        } finally {
          try {
            await database.close();
          } finally {
            await playbackLog?.close();
            await images.close();
          }
        }
      }
    }
  }
}
