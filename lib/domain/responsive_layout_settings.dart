/// Width breakpoints in Flutter logical pixels, independent of the platform.
final class ResponsiveLayoutSettings {
  ResponsiveLayoutSettings({
    List<int>? videoGridMinWidths,
    int sidebarExpandedWidth = 1600,
    int playbackSideBySideWidth = 1000,
  }) : videoGridMinWidths =
           videoGridMinWidths != null &&
               validVideoGridWidths(videoGridMinWidths)
           ? List.unmodifiable(videoGridMinWidths)
           : null,
       sidebarExpandedWidth =
           sidebarExpandedWidth >= 600 && sidebarExpandedWidth <= 6000
           ? sidebarExpandedWidth
           : 1600,
       playbackSideBySideWidth =
           playbackSideBySideWidth >= 600 && playbackSideBySideWidth <= 6000
           ? playbackSideBySideWidth
           : 1000;

  const ResponsiveLayoutSettings.defaults()
    : videoGridMinWidths = null,
      sidebarExpandedWidth = 1600,
      playbackSideBySideWidth = 1000;

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
  final int sidebarExpandedWidth;
  final int playbackSideBySideWidth;

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
    int? sidebarExpandedWidth,
    int? playbackSideBySideWidth,
  }) => ResponsiveLayoutSettings(
    videoGridMinWidths: resetVideoGrid
        ? null
        : videoGridMinWidths ?? this.videoGridMinWidths,
    sidebarExpandedWidth: sidebarExpandedWidth ?? this.sidebarExpandedWidth,
    playbackSideBySideWidth:
        playbackSideBySideWidth ?? this.playbackSideBySideWidth,
  );
}
