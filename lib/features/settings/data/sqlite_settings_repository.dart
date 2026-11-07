import 'dart:convert';

import '../../../domain/playback_rates.dart';

import '../../../domain/recommendation_settings.dart';

import '../../../core/storage/app_database.dart';
import '../domain/app_settings.dart';
import '../domain/shortcut_settings.dart';
import '../domain/settings_repository.dart';

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(
    this.database, {
    this.defaultNavigationMode = WorkspaceNavigationMode.dualTabs,
    this.defaultHighEnergyProgressEnabled = false,
    this.defaultDanmakuArea = 0.75,
    this.defaultDanmakuFontScale = 1.0,
    this.defaultPlayerControlsMode = PlayerControlsMode.click,
    this.defaultVideoCardHoverPlayback = true,
    this.defaultShortcuts = const ShortcutSettings.defaults(),
  });
  final AppDatabase database;
  final WorkspaceNavigationMode defaultNavigationMode;
  final bool defaultHighEnergyProgressEnabled;
  final double defaultDanmakuArea;
  final double defaultDanmakuFontScale;
  final PlayerControlsMode defaultPlayerControlsMode;
  final bool defaultVideoCardHoverPlayback;
  final ShortcutSettings defaultShortcuts;

  AppSettings get defaults => AppSettings.defaults(
    shortcuts: defaultShortcuts,
    navigationMode: defaultNavigationMode,
    highEnergyProgressEnabled: defaultHighEnergyProgressEnabled,
    danmakuArea: defaultDanmakuArea,
    danmakuFontScale: defaultDanmakuFontScale,
    playerControlsMode: defaultPlayerControlsMode,
    videoCardHoverPlayback: defaultVideoCardHoverPlayback,
  );

  @override
  Future<AppSettings> load() async {
    final value = await database.readSetting('preferences.v1');
    if (value == null) {
      return defaults;
    }
    final Object? decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid settings snapshot');
    }
    bool boolean(String key, bool fallback) =>
        decoded[key] is bool ? decoded[key] as bool : fallback;
    double number(String key, double fallback) {
      final value = decoded[key];
      return value is num ? value.toDouble() : fallback;
    }

    List<String> strings(String key, List<String> fallback) {
      final value = decoded[key];
      return value is List ? value.whereType<String>().toList() : fallback;
    }

    final danmakuArea = number('danmakuArea', defaultDanmakuArea);
    final danmakuFontScale = number(
      'danmakuFontScale',
      defaultDanmakuFontScale,
    );
    return AppSettings(
      recommendations: RecommendationSettings.fromJson(
        decoded['recommendations'],
      ),
      navigationMode:
          WorkspaceNavigationMode.values
              .where((item) => item.name == decoded['navigationMode'])
              .firstOrNull ??
          defaultNavigationMode,
      shortcuts: ShortcutSettings.fromJson(
        decoded['shortcuts'],
        useAppleDefaults: defaultShortcuts.useAppleDefaults,
      ),
      sidebarStyle:
          SidebarStyle.values
              .where((item) => item.name == decoded['sidebarStyle'])
              .firstOrNull ??
          SidebarStyle.automatic,
      navigationBarMode:
          NavigationBarMode.values
              .where((item) => item.name == decoded['navigationBarMode'])
              .firstOrNull ??
          NavigationBarMode.automatic,
      sidebarCollapsed: boolean('sidebarCollapsed', false),
      defaultDynamicTab:
          DynamicPageTab.values
              .where((item) => item.name == decoded['defaultDynamicTab'])
              .firstOrNull ??
          DynamicPageTab.dynamic,
      allowConcurrentPlayback: boolean('allowConcurrentPlayback', false),
      cacheImages: boolean('cacheImages', true),
      recordSearchHistory: boolean('recordSearchHistory', true),
      checkPrereleaseUpdates: boolean('checkPrereleaseUpdates', false),
      wheelDampingRatio: number('wheelDampingRatio', 1.3),
      systemFontFamily: decoded['systemFontFamily'] is String
          ? decoded['systemFontFamily'] as String
          : '',
      danmakuSystemFontFamily: decoded['danmakuSystemFontFamily'] is String
          ? decoded['danmakuSystemFontFamily'] as String
          : '',
      font:
          AppFontPreference.values
              .where((item) => item.name == decoded['font'])
              .firstOrNull ??
          AppFontPreference.harmonyOsSans,
      theme:
          AppThemePreference.values
              .where((item) => item.name == decoded['theme'])
              .firstOrNull ??
          AppThemePreference.system,
      appIcon:
          AppIconPreference.values
              .where((item) => item.name == decoded['appIcon'])
              .firstOrNull ??
          AppIconPreference.bilisail,
      danmakuEnabled: boolean('danmakuEnabled', true),
      danmakuShowVip: boolean('danmakuShowVip', true),
      danmakuOpacity: number('danmakuOpacity', 0.8),
      danmakuSendStyle: (
        colorful: boolean('danmakuSendColorful', false),
        mode: switch (decoded['danmakuSendMode']) {
          final int mode => mode,
          _ => 1,
        },
        color: switch (decoded['danmakuSendColor']) {
          final int color => color,
          _ => 0xffffff,
        },
      ),
      danmakuFontScale: danmakuFontScale.isFinite
          ? danmakuFontScale
          : defaultDanmakuFontScale,
      autoPlay: boolean('autoPlay', true),
      defaultShowComments: boolean('defaultShowComments', false),
      videoCardHoverPlayback: boolean(
        'videoCardHoverPlayback',
        defaultVideoCardHoverPlayback,
      ),
      continuousPlayback: boolean('continuousPlayback', false),
      continuousRelatedPlayback: boolean('continuousRelatedPlayback', false),
      playbackMode: decoded.containsKey('playbackMode')
          ? PlaybackMode.values
                    .where((mode) => mode.name == decoded['playbackMode'])
                    .firstOrNull ??
                PlaybackMode.pause
          : null,
      resumePlayback: boolean('resumePlayback', true),
      showCollapsedProgress: boolean('showCollapsedProgress', true),
      highEnergyProgressEnabled: boolean(
        'highEnergyProgressEnabled',
        defaultHighEnergyProgressEnabled,
      ),
      playerControlsMode:
          PlayerControlsMode.values
              .where((item) => item.name == decoded['playerControlsMode'])
              .firstOrNull ??
          defaultPlayerControlsMode,
      preferredQuality: switch (decoded['preferredQuality']) {
        final int quality => quality,
        _ => 80,
      },
      preferredLiveQuality: switch (decoded['preferredLiveQuality']) {
        final int quality => quality,
        _ => 10000,
      },
      preferredVideoCodec:
          VideoCodecPreference.values
              .where((item) => item.name == decoded['preferredVideoCodec'])
              .firstOrNull ??
          VideoCodecPreference.h264,
      liveStreamPreference: LiveStreamPreference.fromJson(
        decoded['liveStreamPreference'],
      ),
      preferredAudioQuality:
          AudioQualityPreference.values
              .where((item) => item.name == decoded['preferredAudioQuality'])
              .firstOrNull ??
          AudioQualityPreference.aac192,
      mediaCdn:
          MediaCdnPreference.values
              .where((item) => item.name == decoded['mediaCdn'])
              .firstOrNull ??
          MediaCdnPreference.automatic,
      videoDecoding:
          VideoDecodingPreference.values
              .where((item) => item.name == decoded['videoDecoding'])
              .firstOrNull ??
          VideoDecodingPreference.automatic,
      playbackBackend:
          PlaybackBackendPreference.values
              .where((item) => item.name == decoded['playbackBackend'])
              .firstOrNull ??
          PlaybackBackendPreference.mediaKit,
      androidVideoOutput:
          AndroidVideoOutputPreference.values
              .where((item) => item.name == decoded['androidVideoOutput'])
              .firstOrNull ??
          AndroidVideoOutputPreference.renderedTexture,
      defaultPlaybackRate: number('defaultPlaybackRate', 1.0),
      playbackRates: PlaybackRates.fromJson(decoded['playbackRates']),
      rememberPlaybackRate: boolean('rememberPlaybackRate', true),
      fullscreenSwipeControls: boolean('fullscreenSwipeControls', true),
      playerFullscreenGestureReverse: boolean(
        'playerFullscreenGestureReverse',
        false,
      ),
      playerFullscreenGesture: boolean('playerFullscreenGesture', true),
      playerShrinkVideo: boolean('playerShrinkVideo', true),
      defaultVolume: number('defaultVolume', 100.0),
      rememberVolumeGlobally: boolean('rememberVolumeGlobally', false),
      audioNormalization:
          AudioNormalizationMode.values
              .where((item) => item.name == decoded['audioNormalization'])
              .firstOrNull ??
          AudioNormalizationMode.off,
      danmakuArea: danmakuArea.isFinite ? danmakuArea : defaultDanmakuArea,
      danmakuTopMargin: number('danmakuTopMargin', 0),
      danmakuLineSpacing: number('danmakuLineSpacing', 5),
      danmakuSpeed: number('danmakuSpeed', 1.0),
      danmakuMaxPerSecond: number('danmakuMaxPerSecond', 20.0).isFinite
          ? number('danmakuMaxPerSecond', 20.0).toInt()
          : 20,
      danmakuScrollEnabled: boolean('danmakuScrollEnabled', true),
      danmakuMaxOnScreen: number('danmakuMaxOnScreen', 0).isFinite
          ? number('danmakuMaxOnScreen', 0).clamp(0, 120).toInt()
          : 0,
      danmakuTopEnabled: boolean('danmakuTopEnabled', true),
      danmakuBottomEnabled: boolean('danmakuBottomEnabled', true),
      danmakuFont:
          DanmakuFontPreference.values
              .where((v) => v.name == decoded['danmakuFont'])
              .firstOrNull ??
          DanmakuFontPreference.system,
      danmakuBold: boolean('danmakuBold', false),
      danmakuStyle:
          DanmakuStylePreference.values
              .where((v) => v.name == decoded['danmakuStyle'])
              .firstOrNull ??
          DanmakuStylePreference.shadow,
      danmakuMergeDuplicates: boolean('danmakuMergeDuplicates', false),
      danmakuBlockColored: boolean('danmakuBlockColored', false),
      danmakuMinimumWeight: number('danmakuMinimumWeight', 0).isFinite
          ? number('danmakuMinimumWeight', 0).toInt()
          : 0,
      danmakuOffset: Duration(
        milliseconds: number('danmakuOffsetMs', 0).isFinite
            ? number('danmakuOffsetMs', 0).clamp(-60000, 60000).toInt()
            : 0,
      ),
      danmakuBlockedWords: strings('danmakuBlockedWords', const []),
      subtitlesEnabled: boolean('subtitlesEnabled', false),
      subtitleFontScale: number('subtitleFontScale', 1.0),
      subtitleBackgroundOpacity: number('subtitleBackgroundOpacity', 0.45),
      subtitleBottomPadding: number('subtitleBottomPadding', 24.0),
      sponsorBlockMode:
          SponsorBlockMode.values
              .where((item) => item.name == decoded['sponsorBlockMode'])
              .firstOrNull ??
          const AppSettings.defaults().sponsorBlockMode,
      sponsorBlockCategories: strings(
        'sponsorBlockCategories',
        AppSettings.supportedSponsorCategories,
      ),
    ).normalized();
  }

  @override
  Future<void> save(AppSettings settings) {
    final value = settings.normalized();
    return database.writeSetting(
      'preferences.v1',
      jsonEncode({
        'schemaVersion': 42,
        'appIcon': value.appIcon.name,
        'recommendations': value.recommendations.toJson(),
        'navigationBarMode': value.navigationBarMode.name,
        'sidebarStyle': value.sidebarStyle.name,
        'sidebarCollapsed': value.sidebarCollapsed,
        'defaultDynamicTab': value.defaultDynamicTab.name,
        'fullscreenSwipeControls': value.fullscreenSwipeControls,
        'playerFullscreenGestureReverse': value.playerFullscreenGestureReverse,
        'playerFullscreenGesture': value.playerFullscreenGesture,
        'playerShrinkVideo': value.playerShrinkVideo,
        'navigationMode': value.navigationMode.name,
        'allowConcurrentPlayback': value.allowConcurrentPlayback,
        'cacheImages': value.cacheImages,
        'recordSearchHistory': value.recordSearchHistory,
        'checkPrereleaseUpdates': value.checkPrereleaseUpdates,
        'wheelDampingRatio': value.wheelDampingRatio,
        'shortcuts': value.shortcuts.toJson(),
        'theme': value.theme.name,
        'font': value.font.name,
        'systemFontFamily': value.systemFontFamily,
        'danmakuSystemFontFamily': value.danmakuSystemFontFamily,
        'danmakuEnabled': value.danmakuEnabled,
        'danmakuOpacity': value.danmakuOpacity,
        'danmakuSendMode': value.danmakuSendStyle.mode,
        'danmakuSendColor': value.danmakuSendStyle.color,
        'danmakuSendColorful': value.danmakuSendStyle.colorful,
        'danmakuShowVip': value.danmakuShowVip,
        'danmakuFontScale': value.danmakuFontScale,
        'autoPlay': value.autoPlay,
        'defaultShowComments': value.defaultShowComments,
        'videoCardHoverPlayback': value.videoCardHoverPlayback,
        'continuousPlayback': value.continuousPlayback,
        'continuousRelatedPlayback': value.continuousRelatedPlayback,
        'playbackMode': value.playbackMode.name,
        'resumePlayback': value.resumePlayback,
        'showCollapsedProgress': value.showCollapsedProgress,
        'highEnergyProgressEnabled': value.highEnergyProgressEnabled,
        'playerControlsMode': value.playerControlsMode.name,
        'preferredQuality': value.preferredQuality,
        'preferredLiveQuality': value.preferredLiveQuality,
        'liveStreamPreference': value.liveStreamPreference.toJson(),
        'preferredAudioQuality': value.preferredAudioQuality.name,
        'preferredVideoCodec': value.preferredVideoCodec.name,
        'mediaCdn': value.mediaCdn.name,
        'videoDecoding': value.videoDecoding.name,
        'androidVideoOutput': value.androidVideoOutput.name,
        'playbackBackend': value.playbackBackend.name,
        'defaultPlaybackRate': value.defaultPlaybackRate,
        'playbackRates': value.playbackRates,
        'rememberPlaybackRate': value.rememberPlaybackRate,
        'defaultVolume': value.defaultVolume,
        'rememberVolumeGlobally': value.rememberVolumeGlobally,
        'audioNormalization': value.audioNormalization.name,
        'danmakuArea': value.danmakuArea,
        'danmakuTopMargin': value.danmakuTopMargin,
        'danmakuLineSpacing': value.danmakuLineSpacing,
        'danmakuSpeed': value.danmakuSpeed,
        'danmakuMaxPerSecond': value.danmakuMaxPerSecond,
        'danmakuMaxOnScreen': value.danmakuMaxOnScreen,
        'danmakuScrollEnabled': value.danmakuScrollEnabled,
        'danmakuTopEnabled': value.danmakuTopEnabled,
        'danmakuBottomEnabled': value.danmakuBottomEnabled,
        'danmakuFont': value.danmakuFont.name,
        'danmakuBold': value.danmakuBold,
        'danmakuStyle': value.danmakuStyle.name,
        'danmakuMergeDuplicates': value.danmakuMergeDuplicates,
        'danmakuBlockColored': value.danmakuBlockColored,
        'danmakuMinimumWeight': value.danmakuMinimumWeight,
        'danmakuOffsetMs': value.danmakuOffset.inMilliseconds,
        'danmakuBlockedWords': value.danmakuBlockedWords,
        'subtitlesEnabled': value.subtitlesEnabled,
        'subtitleFontScale': value.subtitleFontScale,
        'subtitleBackgroundOpacity': value.subtitleBackgroundOpacity,
        'subtitleBottomPadding': value.subtitleBottomPadding,
        'sponsorBlockMode': value.sponsorBlockMode.name,
        'sponsorBlockCategories': value.sponsorBlockCategories,
      }),
    );
  }

  // Keep frequent player changes separate from preference snapshots so a
  // concurrent settings save cannot overwrite the most recent volume.
  Future<double?> loadRememberedVolume() async {
    final stored = await database.readSetting('playback.volume.v1');
    final volume = stored == null ? null : double.tryParse(stored);
    return volume != null && volume.isFinite && volume >= 0 && volume <= 100
        ? volume
        : null;
  }

  Future<void> saveRememberedVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 100) {
      throw ArgumentError.value(volume, 'volume');
    }
    return database.writeSetting('playback.volume.v1', volume.toString());
  }
}
