import '../../../domain/playback_rates.dart';
import '../../../domain/video_codec.dart';
import 'shortcut_settings.dart';

export '../../../domain/video_codec.dart';

enum AppThemePreference { system, light, dark }

enum AppFontPreference { harmonyOsSans, system }

enum SponsorBlockMode { disabled, manual, automatic }

final class AppSettings {
  AppSettings({
    this.shortcuts = const ShortcutSettings.defaults(),
    this.theme = AppThemePreference.system,
    this.font = AppFontPreference.harmonyOsSans,
    this.cacheImages = true,
    this.danmakuEnabled = true,
    this.danmakuOpacity = 0.8,
    this.danmakuFontScale = 1.0,
    this.autoPlay = true,
    this.resumePlayback = true,
    this.showCollapsedProgress = true,
    this.preferredQuality = 80,
    this.preferredVideoCodec = VideoCodecPreference.h264,
    this.videoDecoding = VideoDecodingPreference.automatic,
    this.defaultPlaybackRate = 1.0,
    this.defaultVolume = 100.0,
    this.danmakuArea = 0.75,
    this.danmakuSpeed = 1.0,
    this.danmakuMaxPerSecond = 20,
    this.danmakuScrollEnabled = true,
    this.danmakuTopEnabled = true,
    this.danmakuBottomEnabled = true,
    List<String> danmakuBlockedWords = const [],
    this.subtitlesEnabled = false,
    this.subtitleFontScale = 1.0,
    this.subtitleBackgroundOpacity = 0.45,
    this.subtitleBottomPadding = 24.0,
    this.sponsorBlockMode = SponsorBlockMode.disabled,
    List<String> sponsorBlockCategories = const ['sponsor'],
  }) : _danmakuBlockedWords = List.unmodifiable(danmakuBlockedWords),
       _sponsorBlockCategories = List.unmodifiable(sponsorBlockCategories);

  /// Constant defaults have no caller-owned collection inputs.
  const AppSettings.defaults()
    : shortcuts = const ShortcutSettings.defaults(),
      theme = AppThemePreference.system,
      font = AppFontPreference.harmonyOsSans,
      cacheImages = true,
      danmakuEnabled = true,
      danmakuOpacity = 0.8,
      danmakuFontScale = 1.0,
      autoPlay = true,
      resumePlayback = true,
      showCollapsedProgress = true,
      preferredQuality = 80,
      preferredVideoCodec = VideoCodecPreference.h264,
      videoDecoding = VideoDecodingPreference.automatic,
      defaultPlaybackRate = 1.0,
      defaultVolume = 100.0,
      danmakuArea = 0.75,
      danmakuSpeed = 1.0,
      danmakuMaxPerSecond = 20,
      danmakuScrollEnabled = true,
      danmakuTopEnabled = true,
      danmakuBottomEnabled = true,
      subtitlesEnabled = false,
      subtitleFontScale = 1.0,
      subtitleBackgroundOpacity = 0.45,
      subtitleBottomPadding = 24.0,
      sponsorBlockMode = SponsorBlockMode.disabled,
      _danmakuBlockedWords = const [],
      _sponsorBlockCategories = const ['sponsor'];

  final ShortcutSettings shortcuts;
  final AppThemePreference theme;
  final AppFontPreference font;
  final bool cacheImages;
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontScale;
  final bool autoPlay;
  final bool resumePlayback;
  final bool showCollapsedProgress;
  final int preferredQuality;
  final VideoCodecPreference preferredVideoCodec;
  final VideoDecodingPreference videoDecoding;
  final double defaultPlaybackRate;
  final double defaultVolume;
  final double danmakuArea;
  final double danmakuSpeed;
  final int danmakuMaxPerSecond;
  final bool danmakuScrollEnabled;
  final bool danmakuTopEnabled;
  final bool danmakuBottomEnabled;
  final List<String> _danmakuBlockedWords;
  List<String> get danmakuBlockedWords => _danmakuBlockedWords;
  final bool subtitlesEnabled;
  final double subtitleFontScale;
  final double subtitleBackgroundOpacity;
  final double subtitleBottomPadding;
  final SponsorBlockMode sponsorBlockMode;
  final List<String> _sponsorBlockCategories;
  List<String> get sponsorBlockCategories => _sponsorBlockCategories;

  AppSettings copyWith({
    ShortcutSettings? shortcuts,
    AppThemePreference? theme,
    AppFontPreference? font,
    bool? cacheImages,
    bool? danmakuEnabled,
    double? danmakuOpacity,
    double? danmakuFontScale,
    bool? autoPlay,
    bool? resumePlayback,
    bool? showCollapsedProgress,
    int? preferredQuality,
    VideoCodecPreference? preferredVideoCodec,
    VideoDecodingPreference? videoDecoding,
    double? defaultPlaybackRate,
    double? defaultVolume,
    double? danmakuArea,
    double? danmakuSpeed,
    int? danmakuMaxPerSecond,
    bool? danmakuScrollEnabled,
    bool? danmakuTopEnabled,
    bool? danmakuBottomEnabled,
    List<String>? danmakuBlockedWords,
    bool? subtitlesEnabled,
    double? subtitleFontScale,
    double? subtitleBackgroundOpacity,
    double? subtitleBottomPadding,
    SponsorBlockMode? sponsorBlockMode,
    List<String>? sponsorBlockCategories,
  }) => AppSettings(
    shortcuts: shortcuts ?? this.shortcuts,
    theme: theme ?? this.theme,
    font: font ?? this.font,
    cacheImages: cacheImages ?? this.cacheImages,
    danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
    danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
    danmakuFontScale: danmakuFontScale ?? this.danmakuFontScale,
    autoPlay: autoPlay ?? this.autoPlay,
    resumePlayback: resumePlayback ?? this.resumePlayback,
    showCollapsedProgress: showCollapsedProgress ?? this.showCollapsedProgress,
    preferredQuality: preferredQuality ?? this.preferredQuality,
    preferredVideoCodec: preferredVideoCodec ?? this.preferredVideoCodec,
    videoDecoding: videoDecoding ?? this.videoDecoding,
    defaultPlaybackRate: defaultPlaybackRate ?? this.defaultPlaybackRate,
    defaultVolume: defaultVolume ?? this.defaultVolume,
    danmakuArea: danmakuArea ?? this.danmakuArea,
    danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
    danmakuMaxPerSecond: danmakuMaxPerSecond ?? this.danmakuMaxPerSecond,
    danmakuScrollEnabled: danmakuScrollEnabled ?? this.danmakuScrollEnabled,
    danmakuTopEnabled: danmakuTopEnabled ?? this.danmakuTopEnabled,
    danmakuBottomEnabled: danmakuBottomEnabled ?? this.danmakuBottomEnabled,
    danmakuBlockedWords: List.unmodifiable(
      danmakuBlockedWords ?? this.danmakuBlockedWords,
    ),
    subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
    subtitleFontScale: subtitleFontScale ?? this.subtitleFontScale,
    subtitleBackgroundOpacity:
        subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
    subtitleBottomPadding: subtitleBottomPadding ?? this.subtitleBottomPadding,
    sponsorBlockMode: sponsorBlockMode ?? this.sponsorBlockMode,
    sponsorBlockCategories: List.unmodifiable(
      sponsorBlockCategories ?? this.sponsorBlockCategories,
    ),
  );

  static const supportedQualities = [
    16,
    32,
    64,
    80,
    112,
    116,
    120,
    125,
    126,
    127,
  ];
  static const supportedSponsorCategories = [
    'sponsor',
    'intro',
    'outro',
    'selfpromo',
    'interaction',
    'preview',
  ];
  AppSettings normalized() {
    double bounded(double value, double min, double max, double fallback) =>
        value.isFinite ? value.clamp(min, max) : fallback;
    return copyWith(
      preferredQuality: supportedQualities.contains(preferredQuality)
          ? preferredQuality
          : 80,
      defaultPlaybackRate: PlaybackRates.nearest(defaultPlaybackRate),
      defaultVolume: bounded(defaultVolume, 0, 100, 100),
      danmakuOpacity: bounded(danmakuOpacity, .2, 1, .8),
      danmakuFontScale: bounded(danmakuFontScale, .7, 1.5, 1),
      danmakuArea: bounded(danmakuArea, .25, 1, .75),
      danmakuSpeed: bounded(danmakuSpeed, .5, 2, 1),
      danmakuMaxPerSecond: danmakuMaxPerSecond.clamp(1, 100),
      danmakuBlockedWords: danmakuBlockedWords
          .map((word) => word.trim())
          .where((word) => word.isNotEmpty)
          .map((word) => word.length > 100 ? word.substring(0, 100) : word)
          .toSet()
          .take(200)
          .toList(),
      subtitleFontScale: bounded(subtitleFontScale, .5, 2, 1),
      subtitleBackgroundOpacity: bounded(subtitleBackgroundOpacity, 0, 1, .45),
      subtitleBottomPadding: bounded(subtitleBottomPadding, 0, 120, 24),
      sponsorBlockCategories: sponsorBlockCategories
          .where(supportedSponsorCategories.contains)
          .toSet()
          .toList(),
    );
  }
}
