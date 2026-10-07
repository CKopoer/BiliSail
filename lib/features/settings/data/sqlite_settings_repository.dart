import 'dart:convert';

import '../../../core/storage/app_database.dart';
import '../domain/app_settings.dart';
import '../domain/shortcut_settings.dart';
import '../domain/settings_repository.dart';

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(
    this.database, {
    this.defaultNavigationMode = WorkspaceNavigationMode.multipleTabs,
  });
  final AppDatabase database;
  final WorkspaceNavigationMode defaultNavigationMode;
  @override
  Future<AppSettings> load() async {
    final value = await database.readSetting('preferences.v1');
    if (value == null) {
      return AppSettings.defaults(navigationMode: defaultNavigationMode);
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

    return AppSettings(
      navigationMode:
          WorkspaceNavigationMode.values
              .where((item) => item.name == decoded['navigationMode'])
              .firstOrNull ??
          defaultNavigationMode,
      shortcuts: ShortcutSettings.fromJson(decoded['shortcuts']),
      allowConcurrentPlayback: boolean('allowConcurrentPlayback', true),
      cacheImages: boolean('cacheImages', true),
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
      danmakuEnabled: boolean('danmakuEnabled', true),
      danmakuOpacity: number('danmakuOpacity', 0.8),
      danmakuFontScale: number('danmakuFontScale', 1.0),
      autoPlay: boolean('autoPlay', true),
      resumePlayback: boolean('resumePlayback', true),
      showCollapsedProgress: boolean('showCollapsedProgress', true),
      preferredQuality: number('preferredQuality', 80.0).isFinite
          ? number('preferredQuality', 80.0).toInt()
          : 80,
      preferredVideoCodec:
          VideoCodecPreference.values
              .where((item) => item.name == decoded['preferredVideoCodec'])
              .firstOrNull ??
          VideoCodecPreference.h264,
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
      defaultPlaybackRate: number('defaultPlaybackRate', 1.0),
      defaultVolume: number('defaultVolume', 100.0),
      danmakuArea: number('danmakuArea', 0.75),
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
          SponsorBlockMode.disabled,
      sponsorBlockCategories: strings('sponsorBlockCategories', const [
        'sponsor',
      ]),
    ).normalized();
  }

  @override
  Future<void> save(AppSettings settings) {
    final value = settings.normalized();
    return database.writeSetting(
      'preferences.v1',
      jsonEncode({
        'schemaVersion': 15,
        'navigationMode': value.navigationMode.name,
        'allowConcurrentPlayback': value.allowConcurrentPlayback,
        'cacheImages': value.cacheImages,
        'shortcuts': value.shortcuts.toJson(),
        'theme': value.theme.name,
        'font': value.font.name,
        'systemFontFamily': value.systemFontFamily,
        'danmakuSystemFontFamily': value.danmakuSystemFontFamily,
        'danmakuEnabled': value.danmakuEnabled,
        'danmakuOpacity': value.danmakuOpacity,
        'danmakuFontScale': value.danmakuFontScale,
        'autoPlay': value.autoPlay,
        'resumePlayback': value.resumePlayback,
        'showCollapsedProgress': value.showCollapsedProgress,
        'preferredQuality': value.preferredQuality,
        'preferredVideoCodec': value.preferredVideoCodec.name,
        'mediaCdn': value.mediaCdn.name,
        'videoDecoding': value.videoDecoding.name,
        'defaultPlaybackRate': value.defaultPlaybackRate,
        'defaultVolume': value.defaultVolume,
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
}
