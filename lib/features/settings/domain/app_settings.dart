import '../../../domain/playback_rates.dart';
import '../../../domain/audio_normalization.dart';
export '../../../domain/audio_normalization.dart'
    show AudioNormalizationMode, AudioNormalizationLabel;
import '../../../domain/video_codec.dart';
import '../../../domain/audio_quality.dart';
import '../../../domain/live_stream_preference.dart';
import '../../../domain/media_cdn.dart';
import 'shortcut_settings.dart';
import '../../../domain/recommendation_settings.dart';

export '../../../domain/video_codec.dart';
export '../../../domain/audio_quality.dart';
export '../../../domain/live_stream_preference.dart';
export '../../../domain/media_cdn.dart' show MediaCdnPreference;

enum AppThemePreference { system, light, dark }

enum WorkspaceNavigationMode { singlePage, multipleTabs, dualTabs }

enum NavigationBarMode { automatic, bottom, sidebar }

enum SidebarStyle { automatic, expanded, compact }

enum PlayerControlsMode { click, dynamic }

enum AppFontPreference { harmonyOsSans, system, installed }

enum DanmakuFontPreference { system, harmonyOsSans, installed }

extension AppFontFamily on AppFontPreference {
  String? resolveFamily(String installedFamily) => switch (this) {
    AppFontPreference.harmonyOsSans => 'HarmonyOS Sans',
    AppFontPreference.system => null,
    AppFontPreference.installed =>
      installedFamily.isEmpty ? null : installedFamily,
  };
}

extension DanmakuFontFamily on DanmakuFontPreference {
  String? resolveFamily(String installedFamily) => switch (this) {
    DanmakuFontPreference.harmonyOsSans => 'HarmonyOS Sans',
    DanmakuFontPreference.system => null,
    DanmakuFontPreference.installed =>
      installedFamily.isEmpty ? null : installedFamily,
  };
}

enum DanmakuStylePreference { shadow, stroke, plain }

enum SponsorBlockMode { disabled, manual, automatic }

final class AppSettings {
  AppSettings({
    this.recommendations = const RecommendationSettings.defaults(),
    this.shortcuts = const ShortcutSettings.defaults(),
    this.theme = AppThemePreference.system,
    this.navigationMode = WorkspaceNavigationMode.dualTabs,
    this.navigationBarMode = NavigationBarMode.automatic,
    this.sidebarStyle = SidebarStyle.automatic,
    this.sidebarCollapsed = false,
    this.allowConcurrentPlayback = false,
    this.font = AppFontPreference.harmonyOsSans,
    this.systemFontFamily = '',
    this.cacheImages = true,
    this.checkPrereleaseUpdates = false,
    this.wheelDampingRatio = 1.3,
    this.danmakuEnabled = true,
    this.danmakuOpacity = 0.8,
    this.danmakuFontScale = 1.0,
    this.autoPlay = true,
    this.defaultShowComments = false,
    this.videoCardHoverPlayback = true,
    this.continuousPlayback = false,
    this.resumePlayback = true,
    this.showCollapsedProgress = true,
    this.highEnergyProgressEnabled = false,
    this.playerControlsMode = PlayerControlsMode.click,
    this.fullscreenSwipeControls = true,
    this.preferredQuality = 80,
    this.preferredLiveQuality = 10000,
    this.liveStreamPreference = LiveStreamPreference.automatic,
    this.preferredAudioQuality = AudioQualityPreference.aac192,
    this.preferredVideoCodec = VideoCodecPreference.h264,
    this.mediaCdn = MediaCdnPreference.automatic,
    this.videoDecoding = VideoDecodingPreference.automatic,
    this.defaultPlaybackRate = 1.0,
    this.defaultVolume = 100.0,
    this.rememberVolumeGlobally = false,
    this.audioNormalization = AudioNormalizationMode.off,
    this.danmakuArea = 0.75,
    this.danmakuTopMargin = 0,
    this.danmakuLineSpacing = 5,
    this.danmakuSpeed = 1.0,
    this.danmakuMaxPerSecond = 20,
    this.danmakuMaxOnScreen = 0,
    this.danmakuScrollEnabled = true,
    this.danmakuTopEnabled = true,
    this.danmakuBottomEnabled = true,
    this.danmakuFont = DanmakuFontPreference.system,
    this.danmakuSystemFontFamily = '',
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
    this.sponsorBlockMode = SponsorBlockMode.manual,
    List<String> sponsorBlockCategories = supportedSponsorCategories,
  }) : _danmakuBlockedWords = List.unmodifiable(danmakuBlockedWords),
       _sponsorBlockCategories = List.unmodifiable(sponsorBlockCategories);

  /// Constant defaults have no caller-owned collection inputs.
  const AppSettings.defaults({
    this.recommendations = const RecommendationSettings.defaults(),
    this.shortcuts = const ShortcutSettings.defaults(),
    this.navigationMode = WorkspaceNavigationMode.dualTabs,
    this.navigationBarMode = NavigationBarMode.automatic,
    this.sidebarStyle = SidebarStyle.automatic,
    this.sidebarCollapsed = false,
    this.allowConcurrentPlayback = false,
    this.videoCardHoverPlayback = true,
    this.highEnergyProgressEnabled = false,
    this.danmakuArea = 0.75,
    this.danmakuFontScale = 1.0,
    this.playerControlsMode = PlayerControlsMode.click,
    this.fullscreenSwipeControls = true,
  }) : theme = AppThemePreference.system,
       font = AppFontPreference.harmonyOsSans,
       systemFontFamily = '',
       cacheImages = true,
       checkPrereleaseUpdates = false,
       wheelDampingRatio = 1.3,
       danmakuEnabled = true,
       danmakuOpacity = 0.8,
       autoPlay = true,
       defaultShowComments = false,
       continuousPlayback = false,
       resumePlayback = true,
       showCollapsedProgress = true,
       preferredQuality = 80,
       preferredLiveQuality = 10000,
       liveStreamPreference = LiveStreamPreference.automatic,
       preferredAudioQuality = AudioQualityPreference.aac192,
       preferredVideoCodec = VideoCodecPreference.h264,
       mediaCdn = MediaCdnPreference.automatic,
       videoDecoding = VideoDecodingPreference.automatic,
       defaultPlaybackRate = 1.0,
       defaultVolume = 100.0,
       rememberVolumeGlobally = false,
       audioNormalization = AudioNormalizationMode.off,
       danmakuTopMargin = 0,
       danmakuLineSpacing = 5,
       danmakuSpeed = 1.0,
       danmakuMaxPerSecond = 20,
       danmakuMaxOnScreen = 0,
       danmakuScrollEnabled = true,
       danmakuTopEnabled = true,
       danmakuBottomEnabled = true,
       danmakuFont = DanmakuFontPreference.system,
       danmakuSystemFontFamily = '',
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
       sponsorBlockMode = SponsorBlockMode.manual,
       _danmakuBlockedWords = const [],
       _sponsorBlockCategories = supportedSponsorCategories;

  final ShortcutSettings shortcuts;
  final RecommendationSettings recommendations;
  final AppThemePreference theme;
  final WorkspaceNavigationMode navigationMode;
  final NavigationBarMode navigationBarMode;
  final SidebarStyle sidebarStyle;
  final bool sidebarCollapsed;
  final bool allowConcurrentPlayback;
  bool get concurrentPlaybackEnabled =>
      navigationMode == WorkspaceNavigationMode.multipleTabs &&
      allowConcurrentPlayback;
  final AppFontPreference font;
  final String systemFontFamily;
  String? get fontFamily => font.resolveFamily(systemFontFamily);
  final bool cacheImages;
  final bool checkPrereleaseUpdates;

  /// Mouse-wheel spring damping ratio; 1 is critically damped.
  final double wheelDampingRatio;
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontScale;
  final bool autoPlay;
  final bool defaultShowComments;
  final bool videoCardHoverPlayback;
  final bool continuousPlayback;
  final bool resumePlayback;
  final bool showCollapsedProgress;
  final bool highEnergyProgressEnabled;
  final PlayerControlsMode playerControlsMode;
  final bool fullscreenSwipeControls;
  final int preferredQuality;
  final int preferredLiveQuality;
  final LiveStreamPreference liveStreamPreference;
  final AudioQualityPreference preferredAudioQuality;
  final VideoCodecPreference preferredVideoCodec;
  final MediaCdnPreference mediaCdn;
  final VideoDecodingPreference videoDecoding;
  final double defaultPlaybackRate;
  final double defaultVolume;
  final bool rememberVolumeGlobally;
  final AudioNormalizationMode audioNormalization;
  final double danmakuArea;

  /// Distance from the video surface top, in Flutter logical pixels.
  final double danmakuTopMargin;

  /// Extra logical pixels between rows of text; zero lets them touch.
  final double danmakuLineSpacing;
  final double danmakuSpeed;
  final int danmakuMaxPerSecond;

  /// Zero keeps the renderer's fixed safety cap of 120 comments.
  final int danmakuMaxOnScreen;
  final bool danmakuScrollEnabled;
  final bool danmakuTopEnabled;
  final bool danmakuBottomEnabled;
  final DanmakuFontPreference danmakuFont;
  final String danmakuSystemFontFamily;
  String? get danmakuFontFamily =>
      danmakuFont.resolveFamily(danmakuSystemFontFamily);
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
    RecommendationSettings? recommendations,
    ShortcutSettings? shortcuts,
    AppThemePreference? theme,
    WorkspaceNavigationMode? navigationMode,
    NavigationBarMode? navigationBarMode,
    SidebarStyle? sidebarStyle,
    bool? sidebarCollapsed,
    bool? allowConcurrentPlayback,
    AppFontPreference? font,
    String? systemFontFamily,
    bool? cacheImages,
    bool? checkPrereleaseUpdates,
    double? wheelDampingRatio,
    bool? danmakuEnabled,
    double? danmakuOpacity,
    double? danmakuFontScale,
    bool? autoPlay,
    bool? defaultShowComments,
    bool? videoCardHoverPlayback,
    bool? continuousPlayback,
    bool? resumePlayback,
    bool? showCollapsedProgress,
    bool? highEnergyProgressEnabled,
    PlayerControlsMode? playerControlsMode,
    bool? fullscreenSwipeControls,
    int? preferredQuality,
    int? preferredLiveQuality,
    LiveStreamPreference? liveStreamPreference,
    AudioQualityPreference? preferredAudioQuality,
    VideoCodecPreference? preferredVideoCodec,
    MediaCdnPreference? mediaCdn,
    VideoDecodingPreference? videoDecoding,
    double? defaultPlaybackRate,
    double? defaultVolume,
    bool? rememberVolumeGlobally,
    AudioNormalizationMode? audioNormalization,
    double? danmakuArea,
    double? danmakuTopMargin,
    double? danmakuLineSpacing,
    double? danmakuSpeed,
    int? danmakuMaxPerSecond,
    int? danmakuMaxOnScreen,
    bool? danmakuScrollEnabled,
    bool? danmakuTopEnabled,
    bool? danmakuBottomEnabled,
    DanmakuFontPreference? danmakuFont,
    String? danmakuSystemFontFamily,
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
    recommendations: recommendations ?? this.recommendations,
    theme: theme ?? this.theme,
    navigationMode: navigationMode ?? this.navigationMode,
    navigationBarMode: navigationBarMode ?? this.navigationBarMode,
    sidebarStyle: sidebarStyle ?? this.sidebarStyle,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    allowConcurrentPlayback:
        allowConcurrentPlayback ?? this.allowConcurrentPlayback,
    font: font ?? this.font,
    systemFontFamily: systemFontFamily ?? this.systemFontFamily,
    cacheImages: cacheImages ?? this.cacheImages,
    checkPrereleaseUpdates:
        checkPrereleaseUpdates ?? this.checkPrereleaseUpdates,
    wheelDampingRatio: wheelDampingRatio ?? this.wheelDampingRatio,
    danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
    danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
    danmakuFontScale: danmakuFontScale ?? this.danmakuFontScale,
    autoPlay: autoPlay ?? this.autoPlay,
    defaultShowComments: defaultShowComments ?? this.defaultShowComments,
    videoCardHoverPlayback:
        videoCardHoverPlayback ?? this.videoCardHoverPlayback,
    continuousPlayback: continuousPlayback ?? this.continuousPlayback,
    resumePlayback: resumePlayback ?? this.resumePlayback,
    showCollapsedProgress: showCollapsedProgress ?? this.showCollapsedProgress,
    highEnergyProgressEnabled:
        highEnergyProgressEnabled ?? this.highEnergyProgressEnabled,
    playerControlsMode: playerControlsMode ?? this.playerControlsMode,
    fullscreenSwipeControls:
        fullscreenSwipeControls ?? this.fullscreenSwipeControls,
    preferredQuality: preferredQuality ?? this.preferredQuality,
    preferredLiveQuality: preferredLiveQuality ?? this.preferredLiveQuality,
    liveStreamPreference: liveStreamPreference ?? this.liveStreamPreference,
    preferredAudioQuality: preferredAudioQuality ?? this.preferredAudioQuality,
    preferredVideoCodec: preferredVideoCodec ?? this.preferredVideoCodec,
    mediaCdn: mediaCdn ?? this.mediaCdn,
    videoDecoding: videoDecoding ?? this.videoDecoding,
    defaultPlaybackRate: defaultPlaybackRate ?? this.defaultPlaybackRate,
    defaultVolume: defaultVolume ?? this.defaultVolume,
    rememberVolumeGlobally:
        rememberVolumeGlobally ?? this.rememberVolumeGlobally,
    audioNormalization: audioNormalization ?? this.audioNormalization,
    danmakuArea: danmakuArea ?? this.danmakuArea,
    danmakuTopMargin: danmakuTopMargin ?? this.danmakuTopMargin,
    danmakuLineSpacing: danmakuLineSpacing ?? this.danmakuLineSpacing,
    danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
    danmakuMaxPerSecond: danmakuMaxPerSecond ?? this.danmakuMaxPerSecond,
    danmakuMaxOnScreen: danmakuMaxOnScreen ?? this.danmakuMaxOnScreen,
    danmakuScrollEnabled: danmakuScrollEnabled ?? this.danmakuScrollEnabled,
    danmakuTopEnabled: danmakuTopEnabled ?? this.danmakuTopEnabled,
    danmakuBottomEnabled: danmakuBottomEnabled ?? this.danmakuBottomEnabled,
    danmakuFont: danmakuFont ?? this.danmakuFont,
    danmakuSystemFontFamily:
        danmakuSystemFontFamily ?? this.danmakuSystemFontFamily,
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
  // Live qn values are independent of VOD; zero asks the server to choose.
  static const liveQualityOptions = {
    0: '自动',
    80: '流畅',
    150: '高清',
    250: '超清',
    400: '蓝光',
    10000: '原画',
    15000: '2K',
    20000: '4K',
    30000: '杜比',
  };
  static const supportedSponsorCategories = [
    'sponsor',
    'intro',
    'outro',
    'selfpromo',
    'interaction',
    'preview',
  ];
  AppSettings normalized() {
    String family(String value) {
      final trimmed = value.trim();
      return trimmed.length <= 200 &&
              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(trimmed)
          ? trimmed
          : '';
    }

    double bounded(double value, double min, double max, double fallback) =>
        value.isFinite ? value.clamp(min, max) : fallback;
    return copyWith(
      wheelDampingRatio: bounded(wheelDampingRatio, .5, 2, 1.3),
      systemFontFamily: family(systemFontFamily),
      danmakuSystemFontFamily: family(danmakuSystemFontFamily),
      preferredQuality: supportedQualities.contains(preferredQuality)
          ? preferredQuality
          : 80,
      preferredLiveQuality: liveQualityOptions.containsKey(preferredLiveQuality)
          ? preferredLiveQuality
          : 10000,
      liveStreamPreference: LiveStreamPreference.fromJson(
        liveStreamPreference.toJson(),
      ),
      defaultPlaybackRate: PlaybackRates.nearest(defaultPlaybackRate),
      defaultVolume: bounded(defaultVolume, 0, 100, 100),
      danmakuOpacity: bounded(danmakuOpacity, .2, 1, .8),
      danmakuFontScale: bounded(danmakuFontScale, .2, 1.5, 1),
      danmakuArea: bounded(danmakuArea, .25, 1, .75),
      danmakuTopMargin: bounded(danmakuTopMargin, 0, 200, 0),
      danmakuLineSpacing: bounded(danmakuLineSpacing, 0, 100, 5),
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
      subtitleBottomPadding: bounded(subtitleBottomPadding, 0, 240, 24),
      sponsorBlockCategories: sponsorBlockCategories
          .where(supportedSponsorCategories.contains)
          .toSet()
          .toList(),
    );
  }
}
