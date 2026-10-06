import '../../../domain/user.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../core/presentation/keyboard_shortcuts.dart';
import '../../../core/presentation/playback_page_commands.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/domain/shortcut_settings.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/playback_sidebar_toggle.dart';
import '../../../shared/ui/video_card.dart';
import 'video_author_header.dart';
import 'video_collection_panel.dart';
import '../application/video_controller.dart';
import '../application/video_extras_controller.dart';
import 'video_comments_panel.dart';
import 'video_tags_panel.dart';
import '../../../shared/ui/bili_icons.dart';

typedef VideoPlayerBuilder = Widget Function(
  BuildContext context,
  VideoDetail detail,
  VideoPart part,
);

final class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({
    super.key,
    required this.id,
    this.initialCid,
    this.onPartChanged,
    this.onOpenVideo,
    required this.playerBuilder,
    this.actionsBuilder,
    this.menuBuilder,
    this.onLogin,
    this.onOpenUser,
    this.onOpenVideoPart,
    this.onSearchTag,
  });
  final VideoId id;
  final String? initialCid;
  final ValueChanged<VideoPart>? onPartChanged;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final VideoPlayerBuilder playerBuilder;
  final VideoPlayerBuilder? actionsBuilder;
  final VideoPlayerBuilder? menuBuilder;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  final void Function(VideoId, String?)? onOpenVideoPart;
  final ValueChanged<String>? onSearchTag;
  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

final class _VideoScreenState extends ConsumerState<VideoScreen> {
  String? _selectedCid;
  int _tab = 0;
  bool? _infoVisible;
  bool _descriptionExpanded = false;
  final Set<int> _visitedTabs = {0};
  final ScrollController _introScroll = ScrollController();
  final GlobalKey _infoKey = GlobalKey();
  final GlobalKey _playerKey = GlobalKey();
  @override
  void dispose() {
    _introScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _selectedCid = widget.initialCid;
    }
    if (oldWidget.initialCid != widget.initialCid) {
      _selectedCid = widget.initialCid;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(relatedVideosProvider(widget.id));
    return ref
        .watch(videoDetailProvider(widget.id))
        .when(
          loading: () => const StateView.loading(message: '正在加载视频详情…'),
          error: (error, _) => StateView.error(
            message: _failure(error, '视频详情加载失败'),
            onAction: () => ref.invalidate(videoDetailProvider(widget.id)),
          ),
          data: (video) {
            if (video.parts.isEmpty) {
              return const StateView.empty(
                message: '这个视频没有可播放的分 P',
                icon: Icons.videocam_off_outlined,
              );
            }
            final selected =
                video.parts
                    .where(
                      (part) => part.cid == (_selectedCid ?? widget.initialCid),
                    )
                    .firstOrNull ??
                video.parts.first;
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1000;
                // Narrow windows open as a player-first mini view. An explicit
                // information toggle remains authoritative across later resizes.
                final showInfo = _infoVisible ?? constraints.maxWidth >= 700;
                void toggleInfo() => setState(
                  () => _infoVisible =
                      !(_infoVisible ?? constraints.maxWidth >= 700),
                );
                return PlaybackPageCommands(
                  previousPart: () => _changePart(video, selected, -1),
                  nextPart: () => _changePart(video, selected, 1),
                  toggleInfo: toggleInfo,
                  child: MouseShortcutListener(
                    onShortcut: (key) =>
                        _shortcut(key, video, selected, toggleInfo),
                    child: Focus(
                      onKeyEvent: (_, event) =>
                          _key(event, video, selected, toggleInfo),
                      child: Builder(
                        builder: (context) {
                          final player = Column(
                            key: _playerKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: wide || !showInfo
                                    ? constraints.maxHeight
                                    : constraints.maxWidth * 9 / 16,
                                width: double.infinity,
                                child: ColoredBox(
                                  color: Colors.black,
                                  child: widget.playerBuilder(
                                    context,
                                    video,
                                    selected,
                                  ),
                                ),
                              ),
                            ],
                          );
                          final content = Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                VideoAuthorHeader(
                                  video: video,
                                  onLogin: widget.onLogin,
                                  onOpenUser: widget.onOpenUser,
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        video.summary.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(height: 1.4),
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        minimumSize: const Size(0, 30),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => setState(
                                        () => _descriptionExpanded =
                                            !_descriptionExpanded,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _descriptionExpanded ? '收起' : '展开',
                                          ),
                                          Icon(
                                            _descriptionExpanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    _Meta(
                                      icon: BiliIcons.playCount,
                                      label: compactCount(
                                        video.summary.playCount,
                                      ),
                                    ),
                                    _Meta(
                                      icon: BiliIcons.comment,
                                      label: compactCount(
                                        video.summary.danmakuCount,
                                      ),
                                    ),
                                    if (video.summary.publishedAt
                                        case final DateTime date)
                                      _Meta(
                                        icon: Icons.schedule_outlined,
                                        label: _date(date),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (widget.actionsBuilder != null)
                                  widget.actionsBuilder!(
                                    context,
                                    video,
                                    selected,
                                  ),
                                if (_descriptionExpanded) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    video.description.isEmpty
                                        ? 'UP 主还没有填写简介'
                                        : video.description,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(height: 1.6),
                                  ),
                                ],
                                VideoTagsPanel(
                                  id: widget.id,
                                  onSearch: widget.onSearchTag,
                                ),
                                _separator('intro'),
                                if (video.parts.length > 1 ||
                                    video.collection != null) ...[
                                  VideoCollectionPanel(
                                    key: ValueKey(video.summary.id),
                                    video: video,
                                    selected: selected,
                                    onLogin: widget.onLogin,
                                    onSelectPart: (part) {
                                      setState(() => _selectedCid = part.cid);
                                      widget.onPartChanged?.call(part);
                                    },
                                    onOpenVideoPart: widget.onOpenVideoPart,
                                  ),
                                  _separator('collection'),
                                ],
                                _related(),
                              ],
                            ),
                          );
                          final info = Material(
                            key: _infoKey,
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    for (final (index, title) in [
                                      '简介',
                                      '评论',
                                    ].indexed)
                                      _Pivot(
                                        title: title,
                                        count: index == 1
                                            ? video.replyCount
                                            : null,
                                        selected: _tab == index,
                                        onTap: () => setState(() {
                                          _tab = index;
                                          _visitedTabs.add(index);
                                        }),
                                      ),
                                    const Spacer(),
                                    if (widget.menuBuilder != null)
                                      widget.menuBuilder!(
                                        context,
                                        video,
                                        selected,
                                      ),
                                  ],
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: IndexedStack(
                                    index: _tab,
                                    children: [
                                      ExcludeFocus(
                                        excluding: _tab != 0,
                                        child: SingleChildScrollView(
                                          controller: _introScroll,
                                          child: content,
                                        ),
                                      ),
                                      if (_visitedTabs.contains(1))
                                        ExcludeFocus(
                                          excluding: _tab != 1,
                                          child: VideoCommentsPanel(
                                            detail: video,
                                            onLogin: widget.onLogin,
                                            onOpenUser: widget.onOpenUser,
                                          ),
                                        )
                                      else
                                        const SizedBox(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                          final playerWithToggle = Stack(
                            children: [
                              player,
                              Positioned(
                                right: 0,
                                top:
                                    (wide || !showInfo
                                            ? constraints.maxHeight
                                            : constraints.maxWidth * 9 / 16) /
                                        2 -
                                    PlaybackSidebarToggle.size.height / 2,
                                child: PlaybackSidebarToggle(
                                  tooltip: showInfo ? '收起视频信息' : '展开视频信息',
                                  icon: wide
                                      ? (showInfo
                                            ? Icons.chevron_right
                                            : Icons.chevron_left)
                                      : (showInfo
                                            ? Icons.expand_less
                                            : Icons.expand_more),
                                  onPressed: toggleInfo,
                                ),
                              ),
                            ],
                          );
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: playerWithToggle),
                                ExcludeFocus(
                                  excluding: !showInfo,
                                  child: Offstage(
                                    offstage: !showInfo,
                                    child: SizedBox(
                                      width: 380,
                                      height: constraints.maxHeight,
                                      child: info,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                          return SingleChildScrollView(
                            padding: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                playerWithToggle,
                                ExcludeFocus(
                                  excluding: !showInfo,
                                  child: Offstage(
                                    offstage: !showInfo,
                                    child: SizedBox(
                                      height: constraints.maxHeight.isFinite
                                          ? (constraints.maxHeight -
                                                    constraints.maxWidth *
                                                        9 /
                                                        16)
                                                .clamp(480.0, double.infinity)
                                          : 600,
                                      child: info,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
  }

  void _changePart(VideoDetail video, VideoPart selected, int direction) {
    // The fullscreen route retains these callbacks across page rebuilds.
    final current =
        video.parts
            .where((part) => part.cid == (_selectedCid ?? widget.initialCid))
            .firstOrNull ??
        selected;
    final next = video.parts.indexOf(current) + direction;
    if (next < 0 || next >= video.parts.length) return;
    final part = video.parts[next];
    setState(() => _selectedCid = part.cid);
    widget.onPartChanged?.call(part);
  }

  KeyEventResult _key(
    KeyEvent event,
    VideoDetail video,
    VideoPart selected,
    VoidCallback toggleInfo,
  ) {
    if (event is! KeyDownEvent ||
        !WorkspaceActivity.isActive(context) ||
        shortcutsBlocked(context)) {
      return KeyEventResult.ignored;
    }
    final key = shortcutKey(event);
    return key != null && _shortcut(key, video, selected, toggleInfo)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _shortcut(
    String key,
    VideoDetail video,
    VideoPart selected,
    VoidCallback toggleInfo,
  ) {
    if (!WorkspaceActivity.isActive(context) || shortcutsBlocked(context)) {
      return false;
    }
    final settings =
        ref.read(settingsControllerProvider).value ??
        const AppSettings.defaults();
    final action = settings.shortcuts.actionFor(key);
    if (action == ShortcutAction.fullWindow) {
      toggleInfo();
    } else if (action == ShortcutAction.previousPart ||
        action == ShortcutAction.nextPart) {
      final current = video.parts.indexOf(selected);
      final next = current + (action == ShortcutAction.nextPart ? 1 : -1);
      if (next >= 0 && next < video.parts.length) {
        final part = video.parts[next];
        setState(() => _selectedCid = part.cid);
        widget.onPartChanged?.call(part);
      }
    } else {
      return false;
    }
    return true;
  }

  Widget _related() => ref
      .watch(relatedVideosProvider(widget.id))
      .when(
        loading: () => const StateView.loading(message: '正在加载相关推荐…'),
        error: (error, _) => StateView.error(
          message: _failure(error, '相关推荐加载失败'),
          onAction: () => ref.invalidate(relatedVideosProvider(widget.id)),
        ),
        data: (videos) => videos.isEmpty
            ? const StateView.empty(message: '暂无相关推荐')
            : Column(
                children: [
                  for (final video in videos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: widget.onOpenVideo == null
                            ? null
                            : () => widget.onOpenVideo?.call(video),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 140,
                              height: 79,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (video.coverUrl.isEmpty)
                                      const ColoredBox(
                                        color: Colors.black12,
                                        child: Icon(
                                          Icons.video_library_outlined,
                                        ),
                                      )
                                    else
                                      AppCoverImage(
                                        url: video.coverUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.video_library_outlined,
                                        ),
                                      ),
                                    Positioned(
                                      right: 4,
                                      bottom: 3,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          child: Text(
                                            durationLabel(video.duration),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        BiliIcons.up,
                                        size: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          video.author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 3,
                                    children: [
                                      _Meta(
                                        icon: BiliIcons.playCount,
                                        label: compactCount(video.playCount),
                                      ),
                                      _Meta(
                                        icon: BiliIcons.danmaku,
                                        label: compactCount(video.danmakuCount),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      );
  Widget _separator(String section) => Divider(
    key: ValueKey('video-info-separator-$section'),
    height: 36,
    thickness: 0.7,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
  );
}

final class _Pivot extends StatelessWidget {
  const _Pivot({
    required this.title,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final int? count;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(17, 15, 17, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 3,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                compactCount(count),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

final class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

String _failure(Object error, String fallback) =>
    error is AppFailure ? error.message : fallback;
String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
