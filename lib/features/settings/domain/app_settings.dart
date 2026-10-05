import '../../../domain/playback_rates.dart';
import '../../../domain/video_codec.dart';
import 'shortcut_settings.dart';

export '../../../domain/video_codec.dart';

enum AppThemePreference { system, light, dark }

enum AppFontPreference { harmonyOsSans, system }

enum DanmakuFontPreference { system, harmonyOsSans }

enum DanmakuStylePreference { shadow, stroke, plain }

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
    this.danmakuTopMargin = 0,
    this.danmakuSpeed = 1.0,
    this.danmakuMaxPerSecond = 20,
    this.danmakuMaxOnScreen = 0,
    this.danmakuScrollEnabled = true,
    this.danmakuTopEnabled = true,
    this.danmakuBottomEnabled = true,
    this.danmakuFont = DanmakuFontPreference.system,
    this.danmakuBold = false,
    this.danmakuStyle = DanmakuStylePreference.shadow,
    this.danmakuMergeDuplicates = false,
    this.danmakuBlockColored = false,
    this.danmakuMinimumWeight = 0,
    this.danmakuOffset = Duration.zero,
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
      danmakuTopMargin = 0,
      danmakuSpeed = 1.0,
      danmakuMaxPerSecond = 20,
      danmakuMaxOnScreen = 0,
      danmakuScrollEnabled = true,
      danmakuTopEnabled = true,
      danmakuBottomEnabled = true,
      danmakuFont = DanmakuFontPreference.system,
      danmakuBold = false,
      danmakuStyle = DanmakuStylePreference.shadow,
      danmakuMergeDuplicates = false,
      danmakuBlockColored = false,
      danmakuMinimumWeight = 0,
      danmakuOffset = Duration.zero,
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

  /// Distance from the video surface top, in Flutter logical pixels.
  final double danmakuTopMargin;
  final double danmakuSpeed;
  final int danmakuMaxPerSecond;

  /// Zero keeps the renderer's fixed safety cap of 120 comments.
  final int danmakuMaxOnScreen;
  final bool danmakuScrollEnabled;
  final bool danmakuTopEnabled;
  final bool danmakuBottomEnabled;
  final DanmakuFontPreference danmakuFont;
  final bool danmakuBold;
  final DanmakuStylePreference danmakuStyle;
  final bool danmakuMergeDuplicates;
  final bool danmakuBlockColored;

  /// Zero disables the server weight filter; missing weights are zero.
  final int danmakuMinimumWeight;

  /// Positive values delay comments; negative values show them earlier.
  final Duration danmakuOffset;
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
    double? danmakuTopMargin,
    double? danmakuSpeed,
    int? danmakuMaxPerSecond,
    int? danmakuMaxOnScreen,
    bool? danmakuScrollEnabled,
    bool? danmakuTopEnabled,
    bool? danmakuBottomEnabled,
    DanmakuFontPreference? danmakuFont,
    bool? danmakuBold,
    DanmakuStylePreference? danmakuStyle,
    bool? danmakuMergeDuplicates,
    bool? danmakuBlockColored,
    int? danmakuMinimumWeight,
    Duration? danmakuOffset,
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
    danmakuTopMargin: danmakuTopMargin ?? this.danmakuTopMargin,
    danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
    danmakuMaxPerSecond: danmakuMaxPerSecond ?? this.danmakuMaxPerSecond,
    danmakuMaxOnScreen: danmakuMaxOnScreen ?? this.danmakuMaxOnScreen,
    danmakuScrollEnabled: danmakuScrollEnabled ?? this.danmakuScrollEnabled,
    danmakuTopEnabled: danmakuTopEnabled ?? this.danmakuTopEnabled,
    danmakuBottomEnabled: danmakuBottomEnabled ?? this.danmakuBottomEnabled,
    danmakuFont: danmakuFont ?? this.danmakuFont,
    danmakuBold: danmakuBold ?? this.danmakuBold,
    danmakuStyle: danmakuStyle ?? this.danmakuStyle,
    danmakuMergeDuplicates:
        danmakuMergeDuplicates ?? this.danmakuMergeDuplicates,
    danmakuBlockColored: danmakuBlockColored ?? this.danmakuBlockColored,
    danmakuMinimumWeight: danmakuMinimumWeight ?? this.danmakuMinimumWeight,
    danmakuOffset: danmakuOffset ?? this.danmakuOffset,
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
      danmakuTopMargin: bounded(danmakuTopMargin, 0, 200, 0),
      danmakuSpeed: bounded(danmakuSpeed, .5, 2, 1),
      danmakuMaxPerSecond: danmakuMaxPerSecond.clamp(0, 100),
      danmakuMaxOnScreen: danmakuMaxOnScreen.clamp(0, 120),
      danmakuMinimumWeight: danmakuMinimumWeight.clamp(0, 10),
      danmakuOffset: Duration(
        milliseconds: danmakuOffset.inMilliseconds.clamp(-60000, 60000),
      ),
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
