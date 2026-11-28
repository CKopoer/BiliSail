import '../features/feed/domain/home_channel.dart';

/// Product navigation groups are independent of the retained feed pages.
enum WorkspaceSection {
  home('首页'),
  featured('精选'),
  dynamic('动态'),
  live('直播'),
  mine('我的'),
  messages('消息'),
  downloads('下载'),
  settings('设置');

  const WorkspaceSection(this.label);
  final String label;
}

WorkspaceSection sectionForLocation(Uri location, {required bool compact}) {
  if (location.path == '/featured') return WorkspaceSection.featured;
  if (location.path == '/settings') return WorkspaceSection.settings;
  if (location.path == '/messages') return WorkspaceSection.messages;
  if (location.path == '/downloads') return WorkspaceSection.downloads;
  if (const ['/me', '/history'].contains(location.path)) {
    return WorkspaceSection.mine;
  }
  return switch (location.queryParameters['channel']) {
    'dynamic' || 'videoDynamic' => WorkspaceSection.dynamic,
    'live' when !compact => WorkspaceSection.live,
    'watchLater' || 'favorites' => WorkspaceSection.mine,
    _ => WorkspaceSection.home,
  };
}

List<HomeChannel> channelsForSection(
  WorkspaceSection section, {
  required bool compact,
}) => switch (section) {
  WorkspaceSection.home => [
    HomeChannel.recommended,
    HomeChannel.popular,
    if (compact) HomeChannel.live,
    HomeChannel.bangumi,
    HomeChannel.guochuang,
    HomeChannel.cinema,
    HomeChannel.categories,
  ],
  WorkspaceSection.dynamic => [HomeChannel.dynamic, HomeChannel.videoDynamic],
  WorkspaceSection.live => [HomeChannel.live],
  WorkspaceSection.mine => [HomeChannel.watchLater, HomeChannel.favorites],
  WorkspaceSection.featured ||
  WorkspaceSection.messages ||
  WorkspaceSection.downloads ||
  WorkspaceSection.settings => [],
};

/// The header and retained pager share one order, with explicit swipe groups.
List<List<HomeChannel>> channelGroupsForNavigation({required bool compact}) => [
  for (final section in [
    WorkspaceSection.home,
    WorkspaceSection.dynamic,
    if (!compact) WorkspaceSection.live,
    WorkspaceSection.mine,
  ])
    channelsForSection(section, compact: compact),
];

/// Primary destinations switch immediately; their inner channels still page.
bool shouldAnimateChannelSelection(
  HomeChannel from,
  HomeChannel to, {
  required bool compact,
}) {
  WorkspaceSection section(HomeChannel channel) => sectionForLocation(
    Uri(path: '/', queryParameters: {'channel': channel.name}),
    compact: compact,
  );
  return section(from) == section(to);
}

String settingsFromLocation(Uri source) => Uri(
  path: '/settings',
  queryParameters: {'returnTo': source.toString()},
).toString();
