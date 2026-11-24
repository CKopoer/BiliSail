import 'dart:async';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/content_link.dart';
import '../../../shared/ui/content_link_scope.dart';

import '../../../core/input/input_stroke.dart';
import '../../../domain/video.dart';
import '../../../domain/playback_mode.dart';
import '../../../domain/responsive_layout_settings.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/presentation/input_scope.dart';
import '../../playback/application/playback_session.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/playback_layout_builder.dart';
import '../../../shared/ui/playback_split_layout.dart';
import '../../../shared/ui/width_layout_builder.dart';
import '../../../shared/ui/responsive_layout_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../settings/domain/shortcut_settings.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/workspace_link.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/playback_page_layout.dart';
import '../../../shared/ui/scroll_collapsing_header.dart';
import '../../../shared/ui/playback_info_tabs.dart';
import '../../../shared/ui/comment_detail_builder.dart';
import '../../../domain/course_address.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_card.dart';
import '../application/pgc_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../application/pgc_follow_controller.dart';
import '../domain/pgc_repository.dart';
import '../domain/pgc_playback_sequence.dart';
import 'pgc_episode_panel.dart';
import 'pgc_follow_button.dart';

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
    this.course = false,
    this.seasonId,
    this.episodeId,
    this.defaultShowComments = false,
    this.autoCollapseSidebar = false,
    required this.playerBuilder,
    this.onEpisodeChanged,
    this.onOpenSeason,
    this.commentsBuilder,
    this.onDownload,
    this.onLogin,
  });

  final bool course;
  final String? seasonId, episodeId;
  final bool? defaultShowComments;
  final bool autoCollapseSidebar;
  final PgcPlayerBuilder playerBuilder;
  final ValueChanged<PgcEpisode>? onEpisodeChanged;
  final ValueChanged<PgcSeasonSummary>? onOpenSeason;
  final PgcCommentsBuilder? commentsBuilder;
  final void Function(PgcSeason season, PgcEpisode? selected)? onDownload;
  final VoidCallback? onLogin;

  @override
  ConsumerState<PgcScreen> createState() => _PgcScreenState();
}

final class _PgcScreenState extends ConsumerState<PgcScreen> {
  late PgcLocator _locator;
  int? _tab;
  bool? _infoVisibilityOverride;
  bool _wide = false;
  ({PgcSeasonId season, bool expanded})? _descriptionOverride;
  ContentLink? _contentLink;

  String get _kind => widget.course ? '课程' : '影视';

  bool get _infoVisible =>
      _infoVisibilityOverride ?? !(_wide && widget.autoCollapseSidebar);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final link = ContentLinkScope.of(context);
    if (link != _contentLink) {
      _contentLink = link;
      if (link.comment != null) {
        _tab = 1;
        _infoVisibilityOverride = true;
      }
    }
  }

  final _sidebarKey = GlobalKey();
  final _introScroll = HeaderScrollController();
  PgcSeason? _playerSeason;
  PgcEpisode? _playerEpisode;
  PgcPlayerBuilder? _playerBuilder;
  Widget? _playerContent;

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
      course: widget.course,
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
    if (oldWidget.course != widget.course ||
        oldWidget.seasonId != widget.seasonId) {
      _locator = next;
      _tab = null;
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
        _tab = null;
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
    await _reload();
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

  void _toggleInfo() => setState(() => _infoVisibilityOverride = !_infoVisible);

  bool _descriptionExpanded(PgcSeasonId season, {required bool below}) {
    final choice = _descriptionOverride;
    return choice != null && choice.season == season ? choice.expanded : below;
  }

  void _toggleDescription(PgcSeasonId season, {required bool below}) {
    final expanded = _descriptionExpanded(season, below: below);
    setState(
      () => _descriptionOverride = (season: season, expanded: !expanded),
    );
  }

  Widget _buildPage(BuildContext context) {
    final defaultShowComments = widget.defaultShowComments;
    if (_tab == null && defaultShowComments != null) {
      _tab = defaultShowComments ? 1 : 0;
    }
    final tab = _tab ?? 0;
    if (_locator.seasonId == null && _locator.episodeId == null) {
      return StateView.empty(
        message: widget.course ? '缺少课程或课时编号' : '缺少剧集或作品编号',
      );
    }
    final state = ref.watch(pgcControllerProvider(_locator));
    final season = state.season;
    if (season == null) {
      if (state.loading) {
        return StateView.loading(message: '正在加载$_kind详情…');
      }
      return StateView.error(
        message: state.message ?? '$_kind详情暂时无法加载',
        onAction: () =>
            ref.read(pgcControllerProvider(_locator).notifier).load(),
      );
    }
    final selected = state.selectedEpisode;
    final player = _player(season, selected);
    return PlaybackPageCommands(
      previousPart: () => _stepEpisode(season, selected, -1),
      nextPart: () => _stepEpisode(season, selected, 1),
      hasNext:
          selected != null && adjacentPgcEpisode(season, selected, 1) != null,
      onCompleted: () => _stepEpisode(season, selected, 1, completed: true),
      onLoopCompleted: () =>
          _stepEpisode(season, selected, 1, completed: true, loop: true),
      toggleInfo: _toggleInfo,
      toggleDescription: () {
        if (_infoVisible &&
            PlaybackSplitLayout.readInfoBelow(_sidebarKey.currentContext)) {
          _toggleDescription(season.id, below: true);
          return;
        }
        setState(() {
          _infoVisibilityOverride = !_infoVisible || tab != 0;
          _tab = 0;
        });
      },
      toggleComments: () => setState(() {
        _tab = _infoVisible && tab == 1 ? 0 : 1;
        _infoVisibilityOverride = true;
      }),
      child: WidthLayoutBuilder(
        builder: (context, width) {
          final wide =
              width >=
              ResponsiveLayoutScope.of(context).playbackSideBySideWidth;
          _wide = wide;
          final showInfo = _infoVisible;
          final info = Material(
            key: _sidebarKey,
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
                    previewing:
                        showInfo &&
                        WorkspaceActivity.isVisible(context) &&
                        !WorkspaceActivity.isActive(context),
                    child: CommentDetailBuilder(
                      target: season.commentTarget(selected),
                      enabled: tab == 1 && widget.commentsBuilder != null,
                      builder: (context, detailOpen) => PlaybackInfoTabs(
                        showNavigation: !detailOpen,
                        key: ValueKey(season.id),
                        value: tab.clamp(
                          0,
                          widget.commentsBuilder != null && selected != null
                              ? 1
                              : 0,
                        ),
                        onChanged: (tab) => setState(() => _tab = tab),
                        viewKey: const ValueKey('pgc-info-swipe'),
                        labels: [
                          Text(
                            PlaybackSplitLayout.infoBelowOf(context)
                                ? (widget.course ? '课时' : '选集')
                                : '简介',
                          ),
                          if (widget.commentsBuilder != null &&
                              selected != null)
                            const Text('评论'),
                        ],
                        itemKey: (tab) =>
                            ValueKey('pgc-tab-${tab == 0 ? '简介' : '评论'}'),
                        trailing: _menu(context, season, selected, _toggleInfo),
                        pageBuilder: (context, tab, active) {
                          if (tab == 0) {
                            _introScroll.configure(
                              context,
                              active:
                                  showInfo &&
                                  active &&
                                  WorkspaceActivity.isActive(context),
                            );
                          }
                          return TickerMode(
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
                              _ => CustomScrollView(
                                key: const ValueKey('pgc-intro'),
                                controller: _introScroll,
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      0,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (!PlaybackSplitLayout.infoBelowOf(
                                            context,
                                          )) ...[
                                            _summary(
                                              context,
                                              season,
                                              selected,
                                              below: false,
                                            ),
                                            const SizedBox(height: 12),
                                            const Divider(height: 1),
                                            const SizedBox(height: 18),
                                          ],
                                          _episodePanel(season, selected),
                                        ],
                                      ),
                                    ),
                                  ),
                                  _PgcRelatedSeasons(
                                    season: season,
                                    onOpen: widget.onOpenSeason,
                                  ),
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 24),
                                  ),
                                ],
                              ),
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          return PlaybackLayoutBuilder(
            builder: (context, constraints, listening) =>
                PlaybackVideoDimensions(
                  builder: (context, dimensions) => PlaybackPageLayout(
                    splitPage: widget.course
                        ? PlaybackSplitPage.course
                        : PlaybackSplitPage.pgc,
                    wide: wide,
                    showInfo: showInfo,
                    listening: listening,
                    dimensions: dimensions,
                    collapsedHeight: listening && constraints.maxHeight.isFinite
                        ? PlaybackLayoutBuilder.listeningHeight(
                            constraints.maxHeight,
                          )
                        : math.min(
                            constraints.maxWidth * 9 / 16,
                            constraints.maxHeight.isFinite
                                ? constraints.maxHeight * 0.55
                                : constraints.maxWidth * 9 / 16,
                          ),
                    contentKey: season.id,
                    summaryIdentity: (season, selected),
                    summaryBuilder: (context, {required measuring}) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: _summary(
                        context,
                        season,
                        selected,
                        below: true,
                        measuring: measuring,
                      ),
                    ),
                    player: player,
                    info: info,
                    toggleInfo: _toggleInfo,
                    toggleTooltip: showInfo ? '收起$_kind信息' : '展开$_kind信息',
                  ),
                ),
          );
        },
      ),
    );
  }

  Widget _player(PgcSeason season, PgcEpisode? episode) {
    final cached = _playerContent;
    if (cached == null ||
        !identical(_playerSeason, season) ||
        !identical(_playerEpisode, episode) ||
        _playerBuilder != widget.playerBuilder) {
      _playerSeason = season;
      _playerEpisode = episode;
      final builder = _playerBuilder = widget.playerBuilder;
      final content = Builder(
        builder: (context) => ColoredBox(
          key: const ValueKey('pgc-player'),
          color: widget.course && episode?.playable != true
              ? Theme.of(context).colorScheme.surfaceContainer
              : Colors.black,
          child: episode == null
              ? StateView.empty(
                  message: widget.course ? '这门课程暂无课时' : '这个作品暂无可选择的剧集',
                  icon: widget.course
                      ? Icons.school_outlined
                      : Icons.movie_outlined,
                )
              : episode.playable
              // Keep inherited dependencies on this element, so settings/theme
              // updates still reach the injected player without sidebar rebuilds.
              ? builder(context, season, episode)
              : StateView.empty(
                  message: episode.unavailableReason,
                  icon: Icons.lock_outline,
                  actionLabel: '登录已购账号',
                  onAction:
                      widget.course &&
                          !episode.available &&
                          !ref.read(authControllerProvider).isSignedIn
                      ? widget.onLogin
                      : null,
                ),
        ),
      );
      _playerContent = content;
      return content;
    }
    return cached;
  }

  void _stepEpisode(
    PgcSeason season,
    PgcEpisode? selected,
    int direction, {
    bool completed = false,
    bool loop = false,
  }) {
    if (selected == null) return;
    final current = ref.read(pgcControllerProvider(_locator)).selectedEpisode;
    if (current == null) return;
    final episode = adjacentPgcEpisode(season, current, direction, loop: loop);
    if (episode == null) return;
    final session = ref.exists(playbackSessionProvider)
        ? ref.read(playbackSessionProvider)
        : null;
    if (session != null) {
      if (loop && session.playbackMode != PlaybackMode.listLoop) return;
      if (episode.id == current.id) {
        if (completed) {
          unawaited(session.repeatCompleted(session.sourceGeneration));
        }
        return;
      }
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
      tooltip: '更多$_kind操作',
      onSelected: (action) {
        if (action == 'download') {
          widget.onDownload?.call(season, episode);
        } else if (action == 'refresh') {
          unawaited(_reload());
        } else if (action == 'copy') {
          final url = widget.course
              ? CourseAddress(
                  episode?.episodeId ?? season.seasonId,
                  season: episode == null,
                ).webUrl
              : episode == null
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
        PopupMenuItem(value: 'refresh', child: Text('刷新$_kind详情')),
        if (episode != null || _locator.seasonId != null)
          const PopupMenuItem(value: 'copy', child: Text('复制播放链接')),
        PopupMenuItem(value: 'collapse', child: Text('收起$_kind信息')),
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

  Future<void> _reload() async {
    final season = ref.read(pgcControllerProvider(_locator)).season;
    await Future.wait([
      ref.read(pgcControllerProvider(_locator).notifier).load(),
      if (season != null && !widget.course)
        ref.read(pgcFollowControllerProvider(season.id).notifier).refresh(),
    ]);
  }

  Widget _summary(
    BuildContext context,
    PgcSeason season,
    PgcEpisode? selected, {
    required bool below,
    bool measuring = false,
  }) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectionArea(
                  child: Text(
                    season.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 32 / 16,
                    ),
                  ),
                ),
              ),
              if (!widget.course) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth / 2,
                  ),
                  child: PgcFollowButton(
                    seasonId: season.id,
                    seasonType: season.type,
                    onLogin: widget.onLogin,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (season.instructor case final instructor?) ...[
          const SizedBox(height: 5),
          _stat(context, Icons.school_outlined, '讲师 · $instructor'),
        ],
        if ((below || widget.course) && selected != null) ...[
          const SizedBox(height: 4),
          Text(selected.displayTitle, style: text.bodyMedium),
        ],
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
        _PgcDescription(
          text: season.description,
          expanded: !measuring && _descriptionExpanded(season.id, below: below),
          onToggle: () => _toggleDescription(season.id, below: below),
        ),
        if (selected != null && !selected.playable) ...[
          const SizedBox(height: 4),
          Text(
            selected.unavailableReason,
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }

  Widget _episodePanel(PgcSeason season, PgcEpisode? selected) =>
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
      );

  Widget _stat(BuildContext context, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 3),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

final class _PgcDescription extends StatelessWidget {
  const _PgcDescription({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('暂无简介'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SelectionArea(
          child: Text(
            text,
            maxLines: expanded ? null : 2,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onToggle,
            icon: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
            ),
            label: Text(expanded ? '收起' : '展开'),
          ),
        ),
      ],
    );
  }
}

final class _PgcRelatedSeasons extends StatefulWidget {
  const _PgcRelatedSeasons({required this.season, required this.onOpen});
  final PgcSeason season;
  final ValueChanged<PgcSeasonSummary>? onOpen;

  @override
  State<_PgcRelatedSeasons> createState() => _PgcRelatedSeasonsState();
}

final class _PgcRelatedSeasonsState extends State<_PgcRelatedSeasons> {
  late List<PgcSeasonSummary> _items;
  late SliverChildBuilderDelegate _delegate;

  @override
  void initState() {
    super.initState();
    _updateItems();
  }

  @override
  void didUpdateWidget(covariant _PgcRelatedSeasons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season.id != widget.season.id ||
        !identical(
          oldWidget.season.relatedSeasons,
          widget.season.relatedSeasons,
        ) ||
        oldWidget.onOpen != widget.onOpen) {
      _updateItems();
    }
  }

  void _updateItems() {
    final items = _items = widget.season.relatedSeasons
        .where(
          (item) => item.id != widget.season.id && item.title.trim().isNotEmpty,
        )
        .toList(growable: false);
    final onOpen = widget.onOpen;
    final indices = {for (var i = 0; i < items.length; i++) items[i].id: i};
    _delegate = SliverChildBuilderDelegate(
      (context, index) => _PgcRelatedSeasonTile(
        key: ValueKey(items[index].id),
        related: items[index],
        onOpen: onOpen,
      ),
      childCount: items.length,
      findChildIndexCallback: (key) =>
          key is ValueKey<PgcSeasonId> ? indices[key.value] : null,
    );
  }

  @override
  Widget build(BuildContext context) => _items.isEmpty
      ? const SliverToBoxAdapter(child: SizedBox.shrink())
      : SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 18),
                    Text(
                      '${widget.season.title}系列',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverList(
                key: const ValueKey('pgc-related-list'),
                delegate: _delegate,
              ),
            ],
          ),
        );
}

final class _PgcRelatedSeasonTile extends StatelessWidget {
  const _PgcRelatedSeasonTile({
    super.key,
    required this.related,
    required this.onOpen,
  });
  final PgcSeasonSummary related;
  final ValueChanged<PgcSeasonSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen == null ? null : () => onOpen?.call(related);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: ValueKey('pgc-related-${related.seasonId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: open,
        onTertiaryTapUp: WorkspaceLinkScope.middleClick(context, open),
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
}
