import 'dart:convert';

import '../../../core/storage/app_database.dart';
import '../domain/app_settings.dart';
import '../domain/shortcut_settings.dart';
import '../domain/settings_repository.dart';

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this.database);
  final AppDatabase database;
  @override
  Future<AppSettings> load() async {
    final value = await database.readSetting('preferences.v1');
    if (value == null) return const AppSettings.defaults();
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
      shortcuts: ShortcutSettings.fromJson(decoded['shortcuts']),
      cacheImages: boolean('cacheImages', true),
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
      videoDecoding:
          VideoDecodingPreference.values
              .where((item) => item.name == decoded['videoDecoding'])
              .firstOrNull ??
          VideoDecodingPreference.automatic,
      defaultPlaybackRate: number('defaultPlaybackRate', 1.0),
      defaultVolume: number('defaultVolume', 100.0),
      danmakuArea: number('danmakuArea', 0.75),
      danmakuTopMargin: number('danmakuTopMargin', 0),
      danmakuSpeed: number('danmakuSpeed', 1.0),
      danmakuMaxPerSecond: number('danmakuMaxPerSecond', 20.0).isFinite
          ? number('danmakuMaxPerSecond', 20.0).toInt()
          : 20,
      danmakuScrollEnabled: boolean('danmakuScrollEnabled', true),
      danmakuTopEnabled: boolean('danmakuTopEnabled', true),
      danmakuBottomEnabled: boolean('danmakuBottomEnabled', true),
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
        'schemaVersion': 8,
        'cacheImages': value.cacheImages,
        'shortcuts': value.shortcuts.toJson(),
        'theme': value.theme.name,
        'font': value.font.name,
        'danmakuEnabled': value.danmakuEnabled,
        'danmakuOpacity': value.danmakuOpacity,
        'danmakuFontScale': value.danmakuFontScale,
        'autoPlay': value.autoPlay,
        'resumePlayback': value.resumePlayback,
        'showCollapsedProgress': value.showCollapsedProgress,
        'preferredQuality': value.preferredQuality,
        'preferredVideoCodec': value.preferredVideoCodec.name,
        'videoDecoding': value.videoDecoding.name,
        'defaultPlaybackRate': value.defaultPlaybackRate,
        'defaultVolume': value.defaultVolume,
        'danmakuArea': value.danmakuArea,
        'danmakuTopMargin': value.danmakuTopMargin,
        'danmakuSpeed': value.danmakuSpeed,
        'danmakuMaxPerSecond': value.danmakuMaxPerSecond,
        'danmakuScrollEnabled': value.danmakuScrollEnabled,
        'danmakuTopEnabled': value.danmakuTopEnabled,
        'danmakuBottomEnabled': value.danmakuBottomEnabled,
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
