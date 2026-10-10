import 'dart:async';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/input_stroke.dart';
import '../../../domain/video.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/presentation/input_scope.dart';
import '../../playback/application/playback_session.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/width_layout_builder.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../settings/domain/shortcut_settings.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/playback_sidebar_toggle.dart';
import '../../../shared/ui/playback_info_tabs.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_card.dart';
import '../application/pgc_controller.dart';
import '../domain/pgc_repository.dart';
import '../domain/pgc_playback_sequence.dart';
import 'pgc_episode_panel.dart';

typedef PgcPlayerBuilder = Widget Function(
  BuildContext context,
  PgcSeason season,
  PgcEpisode episode,
);
typedef PgcCommentsBuilder = Widget Function(
  BuildContext context,
  PgcSeason season,
  PgcEpisode episode,
);

final class PgcScreen extends ConsumerStatefulWidget {
  const PgcScreen({
    super.key,
    this.seasonId,
    this.episodeId,
    required this.playerBuilder,
    this.onEpisodeChanged,
    this.onOpenSeason,
    this.commentsBuilder,
    this.onDownload,
  });

  final String? seasonId, episodeId;
  final PgcPlayerBuilder playerBuilder;
  final ValueChanged<PgcEpisode>? onEpisodeChanged;
  final ValueChanged<PgcSeasonSummary>? onOpenSeason;
  final PgcCommentsBuilder? commentsBuilder;
  final void Function(PgcSeason season, PgcEpisode? selected)? onDownload;

  @override
  ConsumerState<PgcScreen> createState() => _PgcScreenState();
}

final class _PgcScreenState extends ConsumerState<PgcScreen> {
  late PgcLocator _locator;
  int _tab = 0;
  bool _descriptionExpanded = false;
  bool? _infoVisible;
  final ScrollController _introScroll = ScrollController();

  @override
  void dispose() {
    _introScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _locator = _fromWidget();
  }

  PgcLocator _fromWidget() {
    final seasonId = widget.seasonId?.trim();
    final episodeId = widget.episodeId?.trim();
    return PgcLocator(
      seasonId: seasonId == null || seasonId.isEmpty
          ? null
          : PgcSeasonId(seasonId),
      episodeId: episodeId == null || episodeId.isEmpty
          ? null
          : PgcEpisodeId(episodeId),
    );
  }

  @override
  void didUpdateWidget(covariant PgcScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _fromWidget();
    if (oldWidget.seasonId != widget.seasonId) {
      _locator = next;
      _tab = 0;
      _descriptionExpanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _introScroll.hasClients) _introScroll.jumpTo(0);
      });
    } else if (oldWidget.episodeId != widget.episodeId &&
        next.episodeId != null) {
      final episodeId = next.episodeId;
      if (_locator.seasonId == null &&
          ref
                  .read(pgcControllerProvider(_locator))
                  .season
                  ?.episode(episodeId) ==
              null) {
        _locator = next;
        _tab = 0;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _locator.seasonId == next.seasonId &&
            episodeId != null) {
          ref
              .read(pgcControllerProvider(_locator).notifier)
              .selectDeepLinkEpisode(episodeId);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => CommandTargetScope<Object>(
    scope: CommandScope.page,
    active: WorkspaceActivity.isActive(context),
    merge: const {ShortcutAction.refresh},
    commands: {ShortcutAction.refresh: _refresh},
    child: _buildPage(context),
  );

  Future<CommandOutcome> _refresh(InputStroke stroke) async {
    if (stroke.phase != InputPhase.down) return CommandOutcome.noOp;
    final locator = _locator;
    final provider = pgcControllerProvider(locator);
    final before = ref.read(provider).selectedEpisode;
    final session = ref.exists(playbackSessionProvider)
        ? ref.read(playbackSessionProvider)
        : null;
    final generation = session?.sourceGeneration;
    await ref.read(provider.notifier).load();
    if (!mounted ||
        locator != _locator ||
        !WorkspaceActivity.isActive(context)) {
      return CommandOutcome.stale;
    }
    final state = ref.read(provider);
    final after = state.selectedEpisode;
    if (state.loading || state.message != null) return CommandOutcome.failed;
    // A changed selection activates itself through PlaybackPanel. Only an
    // unchanged source needs an explicit retry; never open both paths.
    if (before != null &&
        after != null &&
        before.episodeId == after.episodeId &&
        before.cid == after.cid &&
        generation == session?.sourceGeneration &&
        session != null) {
      await session.retry();
      if (session.error != null) return CommandOutcome.failed;
    }
    return CommandOutcome.completed;
  }

  Widget _buildPage(BuildContext context) {
    if (_locator.seasonId == null && _locator.episodeId == null) {
      return const StateView.empty(message: '缺少剧集或作品编号');
    }
    final state = ref.watch(pgcControllerProvider(_locator));
    final season = state.season;
    if (season == null) {
      if (state.loading) {
        return const StateView.loading(message: '正在加载影视详情…');
      }
      return StateView.error(
        message: state.message ?? '影视详情暂时无法加载',
        onAction: () =>
            ref.read(pgcControllerProvider(_locator).notifier).load(),
      );
    }
    final selected = state.selectedEpisode;
    return PlaybackPageCommands(
      previousPart: () => _stepEpisode(season, selected, -1),
      nextPart: () => _stepEpisode(season, selected, 1),
      hasNext:
          selected != null && adjacentPgcEpisode(season, selected, 1) != null,
      onCompleted: () => _stepEpisode(season, selected, 1, completed: true),
      toggleInfo: () => setState(
        () => _infoVisible =
            !(_infoVisible ?? MediaQuery.sizeOf(context).width >= 700),
      ),
      child: WidthLayoutBuilder(
        builder: (context, width) {
          final wide = width >= 1000;
          final showInfo = _infoVisible ?? width >= 700;
          void toggleInfo() =>
              setState(() => _infoVisible = !(_infoVisible ?? width >= 700));
          final player = ColoredBox(
            key: const ValueKey('pgc-player'),
            color: Colors.black,
            child: selected == null
                ? const StateView.empty(
                    message: '这个作品暂无可选择的剧集',
                    icon: Icons.movie_outlined,
                  )
                : selected.playable
                ? widget.playerBuilder(context, season, selected)
                : StateView.empty(
                    message: selected.unavailableReason,
                    icon: Icons.lock_outline,
                  ),
          );
          final info = Material(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                if (state.loading) const LinearProgressIndicator(minHeight: 2),
                if (state.message case final String message)
                  MaterialBanner(
                    content: Text(message),
                    actions: [
                      TextButton(
                        onPressed: () => ref
                            .read(pgcControllerProvider(_locator).notifier)
                            .load(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: WorkspaceActivity(
                    active: showInfo && WorkspaceActivity.isActive(context),
                    child: PlaybackInfoTabs(
                      key: ValueKey(season.id),
                      value: _tab.clamp(
                        0,
                        widget.commentsBuilder != null && selected != null
                            ? 1
                            : 0,
                      ),
                      onChanged: (tab) => setState(() => _tab = tab),
                      viewKey: const ValueKey('pgc-info-swipe'),
                      labels: [
                        const Text('简介'),
                        if (widget.commentsBuilder != null && selected != null)
                          const Text('评论'),
                      ],
                      itemKey: (tab) =>
                          ValueKey('pgc-tab-${tab == 0 ? '简介' : '评论'}'),
                      trailing: _menu(context, season, selected, toggleInfo),
                      pageBuilder: (context, tab, active) => TickerMode(
                        enabled: showInfo && active,
                        child: switch ((
                          tab,
                          widget.commentsBuilder,
                          selected,
                        )) {
                          (1, final builder?, final episode?) => builder(
                            context,
                            season,
                            episode,
                          ),
                          _ => SingleChildScrollView(
                            key: const ValueKey('pgc-intro'),
                            controller: _introScroll,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            child: _details(context, season, selected),
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final playerHeight = math.min(
                constraints.maxWidth * 9 / 16,
                constraints.maxHeight.isFinite
                    ? constraints.maxHeight * 0.55
                    : constraints.maxWidth * 9 / 16,
              );
              final infoWidth = wide ? 380.0 : constraints.maxWidth;
              final visiblePlayerWidth = wide
                  ? math.max(
                      0.0,
                      constraints.maxWidth - (showInfo ? infoWidth : 0),
                    )
                  : constraints.maxWidth;
              final visiblePlayerHeight = wide || !showInfo
                  ? constraints.maxHeight
                  : playerHeight;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: visiblePlayerWidth,
                    height: visiblePlayerHeight,
                    child: player,
                  ),
                  Positioned(
                    left: wide ? constraints.maxWidth - infoWidth : 0,
                    top: wide ? 0 : playerHeight,
                    width: infoWidth,
                    height: wide
                        ? constraints.maxHeight
                        : math.max(1.0, constraints.maxHeight - playerHeight),
                    child: ExcludeFocus(
                      excluding: !showInfo,
                      child: Offstage(offstage: !showInfo, child: info),
                    ),
                  ),
                  Positioned(
                    right: showInfo && wide ? infoWidth : 8,
                    top: wide || !showInfo
                        ? math.max(
                            0,
                            visiblePlayerHeight / 2 -
                                PlaybackSidebarToggle.size.height / 2,
                          )
                        : math.max(
                            0,
                            playerHeight / 2 -
                                PlaybackSidebarToggle.size.height / 2,
                          ),
                    child: PlaybackSidebarToggle(
                      tooltip: showInfo ? '收起影视信息' : '展开影视信息',
                      onPressed: toggleInfo,
                      icon: wide
                          ? (showInfo
                                ? Icons.chevron_right
                                : Icons.chevron_left)
                          : (showInfo ? Icons.expand_less : Icons.expand_more),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _stepEpisode(
    PgcSeason season,
    PgcEpisode? selected,
    int direction, {
    bool completed = false,
  }) {
    if (selected == null) return;
    final current = ref.read(pgcControllerProvider(_locator)).selectedEpisode;
    if (current == null) return;
    final episode = adjacentPgcEpisode(season, current, direction);
    if (episode == null) return;
    final session = ref.exists(playbackSessionProvider)
        ? ref.read(playbackSessionProvider)
        : null;
    if (session != null) {
      final video = session.detail;
      final part = session.part;
      if (video == null ||
          part == null ||
          session.danmakuCid != current.cid ||
          !session.prepareNextVideo(
            video.summary.id,
            part.cid,
            nextId: VideoId(episode.bvid ?? ''),
            nextCid: episode.cid,
            completed:
                completed ||
                session.snapshots.value.phase == PlaybackPhase.ended,
          )) {
        return;
      }
    }
    final changed = ref
        .read(pgcControllerProvider(_locator).notifier)
        .selectEpisode(episode.id);
    if (changed) widget.onEpisodeChanged?.call(episode);
  }

  Widget _menu(
    BuildContext context,
    PgcSeason season,
    PgcEpisode? episode,
    VoidCallback toggleInfo,
  ) {
    return PopupMenuButton<String>(
      tooltip: '更多影视操作',
      onSelected: (action) {
        if (action == 'download') {
          widget.onDownload?.call(season, episode);
        } else if (action == 'refresh') {
          unawaited(ref.read(pgcControllerProvider(_locator).notifier).load());
        } else if (action == 'copy') {
          final url = episode == null
              ? 'https://www.bilibili.com/bangumi/play/ss${_locator.seasonId?.value ?? ''}'
              : 'https://www.bilibili.com/bangumi/play/ep${episode.episodeId}';
          unawaited(_copyLink(context, url));
        } else if (action == 'collapse') {
          toggleInfo();
        }
      },
      itemBuilder: (context) => [
        if (widget.onDownload != null)
          const PopupMenuItem(value: 'download', child: Text('下载剧集')),
        const PopupMenuItem(value: 'refresh', child: Text('刷新影视详情')),
        if (episode != null || _locator.seasonId != null)
          const PopupMenuItem(value: 'copy', child: Text('复制播放链接')),
        const PopupMenuItem(value: 'collapse', child: Text('收起影视信息')),
      ],
    );
  }

  Future<void> _copyLink(BuildContext context, String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) showAppNotice(context, '链接已复制');
    } on PlatformException {
      if (context.mounted) showAppNotice(context, '复制失败，请重试');
    }
  }

  Widget _details(
    BuildContext context,
    PgcSeason season,
    PgcEpisode? selected,
  ) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final relatedSeasons = season.relatedSeasons
        .where(
          (related) =>
              related.id != season.id && related.title.trim().isNotEmpty,
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionArea(
          child: Text(
            season.title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (season.publishText?.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(
            season.publishText ?? '',
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (season.playCount case final int count)
              _stat(
                context,
                Icons.play_circle_outline,
                '${compactCount(count)}播放',
              ),
            if (season.danmakuCount case final int count)
              _stat(
                context,
                Icons.chat_bubble_outline,
                '${compactCount(count)}弹幕',
              ),
            if (season.followCount case final int count)
              _stat(context, Icons.favorite_border, '${compactCount(count)}追番'),
            if (season.rating case final double rating)
              Text(
                '${rating.toStringAsFixed(1)}分',
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        if (season.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectionArea(
            child: Text(
              season.description,
              maxLines: _descriptionExpanded ? null : 2,
              overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(height: 1.4, color: muted),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              icon: Icon(
                _descriptionExpanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
              ),
              label: Text(_descriptionExpanded ? '收起' : '展开'),
            ),
          ),
        ] else
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('暂无简介')),
        if (selected != null && !selected.playable) ...[
          const SizedBox(height: 4),
          Text(
            selected.unavailableReason,
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 18),
        PgcEpisodePanel(
          key: ValueKey('pgc-season-episodes-${season.seasonId}'),
          season: season,
          selected: selected,
          onSelect: (episode) {
            final changed = ref
                .read(pgcControllerProvider(_locator).notifier)
                .selectEpisode(episode.id);
            if (changed) widget.onEpisodeChanged?.call(episode);
          },
        ),
        if (relatedSeasons.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 18),
          Text('${season.title}系列', style: text.titleSmall),
          const SizedBox(height: 12),
          for (final related in relatedSeasons)
            _relatedSeason(context, related),
        ],
      ],
    );
  }

  Widget _stat(BuildContext context, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 3),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _relatedSeason(BuildContext context, PgcSeasonSummary related) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          key: ValueKey('pgc-related-${related.seasonId}'),
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onOpenSeason == null
              ? null
              : () => widget.onOpenSeason?.call(related),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: related.coverUrl == null
                    ? const SizedBox(
                        width: 96,
                        height: 54,
                        child: ColoredBox(
                          color: Colors.black12,
                          child: Icon(Icons.movie_outlined),
                        ),
                      )
                    : AppCoverImage(
                        url: related.coverUrl.toString(),
                        width: 96,
                        height: 54,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    related.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
