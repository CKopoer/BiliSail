enum PlaybackSplitStyle { automatic, right, below }

enum PlaybackSplitPage { video, pgc, live, course }

/// Responsive layout preferences, with width breakpoints in logical pixels.
final class ResponsiveLayoutSettings {
  ResponsiveLayoutSettings({
    List<int>? videoGridMinWidths,
    int navigationBarBreakpoint = 600,
    int sidebarExpandedWidth = 1600,
    int playbackSideBySideWidth = 1000,
    Map<PlaybackSplitPage, PlaybackSplitStyle> playbackSplitStyles = const {},
    double? articleWidthFraction,
  }) : videoGridMinWidths =
           videoGridMinWidths != null &&
               validVideoGridWidths(videoGridMinWidths)
           ? List.unmodifiable(videoGridMinWidths)
           : null,
       navigationBarBreakpoint =
           navigationBarBreakpoint >= 320 && navigationBarBreakpoint <= 6000
           ? navigationBarBreakpoint
           : 600,
       sidebarExpandedWidth =
           sidebarExpandedWidth >= 600 && sidebarExpandedWidth <= 6000
           ? sidebarExpandedWidth
           : 1600,
       playbackSideBySideWidth =
           playbackSideBySideWidth >= 600 && playbackSideBySideWidth <= 6000
           ? playbackSideBySideWidth
           : 1000,
       playbackSplitStyles = Map.unmodifiable(playbackSplitStyles),
       articleWidthFraction =
           articleWidthFraction != null &&
               articleWidthFraction >= minArticleWidthFraction &&
               articleWidthFraction <= maxArticleWidthFraction
           ? articleWidthFraction
           : null;

  const ResponsiveLayoutSettings.defaults()
    : videoGridMinWidths = null,
      navigationBarBreakpoint = 600,
      sidebarExpandedWidth = 1600,
      playbackSideBySideWidth = 1000,
      playbackSplitStyles = const {},
      articleWidthFraction = null;

  static const defaultPlaybackSplitStyle = PlaybackSplitStyle.right;
  static const minArticleWidthFraction = .3;
  static const maxArticleWidthFraction = .7;

  static const defaultVideoGridMinWidths = [
    300,
    492,
    1100,
    1380,
    1660,
    1940,
    2220,
    2500,
    2780,
    3060,
    3340,
  ];

  /// Null retains the original card-width and nonlinear font-scaling rules.
  /// Custom entries are the minimum grid widths for 2 through 12 columns.
  final List<int>? videoGridMinWidths;
  final int navigationBarBreakpoint;
  final int sidebarExpandedWidth;
  final int playbackSideBySideWidth;
  final Map<PlaybackSplitPage, PlaybackSplitStyle> playbackSplitStyles;

  PlaybackSplitStyle playbackSplitStyleFor(PlaybackSplitPage page) =>
      playbackSplitStyles[page] ?? defaultPlaybackSplitStyle;

  /// Null uses the reader's automatic width based on the available space.
  final double? articleWidthFraction;

  static bool validVideoGridWidths(List<int>? values) {
    if (values == null || values.length != 11) return false;
    var previous = 199;
    for (final width in values) {
      if (width <= previous || width > 12000) return false;
      previous = width;
    }
    return true;
  }

  ResponsiveLayoutSettings copyWith({
    List<int>? videoGridMinWidths,
    bool resetVideoGrid = false,
    int? navigationBarBreakpoint,
    int? sidebarExpandedWidth,
    int? playbackSideBySideWidth,
    Map<PlaybackSplitPage, PlaybackSplitStyle>? playbackSplitStyles,
    double? articleWidthFraction,
  }) => ResponsiveLayoutSettings(
    videoGridMinWidths: resetVideoGrid
        ? null
        : videoGridMinWidths ?? this.videoGridMinWidths,
    navigationBarBreakpoint:
        navigationBarBreakpoint ?? this.navigationBarBreakpoint,
    sidebarExpandedWidth: sidebarExpandedWidth ?? this.sidebarExpandedWidth,
    playbackSplitStyles: playbackSplitStyles ?? this.playbackSplitStyles,
    playbackSideBySideWidth:
        playbackSideBySideWidth ?? this.playbackSideBySideWidth,
    articleWidthFraction: articleWidthFraction ?? this.articleWidthFraction,
  );
}
