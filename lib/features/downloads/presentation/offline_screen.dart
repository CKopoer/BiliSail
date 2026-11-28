import 'dart:async';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart' show PlaybackPhase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/responsive_layout_settings.dart';
import '../../../shared/ui/playback_layout_builder.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/playback_page_layout.dart';
import '../../../shared/ui/responsive_layout_scope.dart';
import '../../../shared/ui/state_view.dart';
import '../../playback/application/playback_session.dart';
import '../../playback/domain/content_playback.dart';
import '../application/download_controller.dart';
import '../domain/download_models.dart';
import '../domain/offline_library.dart';
import 'offline_playlist.dart';

final class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({
    super.key,
    required this.taskId,
    required this.playerBuilder,
    this.onBackToDownloads,
    this.onTaskChanged,
    this.coverProvider,
    this.autoCollapseSidebar = false,
  });
  final String taskId;
  final Widget Function(BuildContext, DownloadTask) playerBuilder;
  final VoidCallback? onBackToDownloads;
  final ValueChanged<String>? onTaskChanged;
  final ImageProvider<Object>? Function(DownloadTask)? coverProvider;
  final bool autoCollapseSidebar;

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

final class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  String? _selected;
  (String, int)? _account;
  String? _checking;
  DownloadTask? _verified;
  String? _error;
  int _generation = 0;
  bool? _showInfo;
  bool _descriptionExpanded = false;

  @override
  void didUpdateWidget(OfflineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.taskId != oldWidget.taskId && widget.taskId != _selected) {
      _reset();
    }
  }

  void _reset() {
    _generation++;
    _selected = null;
    _checking = null;
    _verified = null;
    _error = null;
    _descriptionExpanded = false;
  }

  void _back() {
    if (widget.onBackToDownloads case final callback?) {
      callback();
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _verify(
    DownloadTask target, {
    bool switchTask = false,
    bool completed = false,
  }) async {
    final generation = ++_generation;
    final source = ref.read(downloadSourceRepositoryProvider);
    final epoch = source.sessionEpoch;
    final current = _verified;
    final session = switchTask && ref.exists(playbackSessionProvider)
        ? ref.read(playbackSessionProvider)
        : null;
    final playbackGeneration = session?.sourceGeneration;
    final modeRevision = session?.playbackModeRevision;
    _checking = target.id;
    bool valid() =>
        mounted &&
        generation == _generation &&
        source.accountScope == target.scope &&
        source.sessionEpoch == epoch;
    try {
      final next = await ref
          .read(downloadControllerProvider.notifier)
          .openOffline(target.id);
      if (!mounted ||
          !valid() ||
          next.scope != target.scope ||
          next.id != target.id ||
          next.status != DownloadStatus.completed) {
        return;
      }
      if (switchTask && !WorkspaceActivity.isActive(context)) return;
      if (switchTask && current != null && session != null) {
        if (session.sourceGeneration != playbackGeneration ||
            completed && session.playbackModeRevision != modeRevision) {
          return;
        }
        if (session.contentTarget == OfflinePlaybackTarget(current.id) &&
            !session.prepareNextVideo(
              current.item.video.id,
              current.item.part.cid,
              nextId: next.item.video.id,
              nextCid: next.item.part.cid,
              completed:
                  completed ||
                  session.snapshots.value.phase == PlaybackPhase.ended,
            )) {
          return;
        }
        if (completed &&
            session.contentTarget != OfflinePlaybackTarget(current.id)) {
          return;
        }
      }
      setState(() {
        _verified = next;
        _error = null;
        if (switchTask) {
          _selected = next.id;
          if (current?.item.workKey != next.item.workKey) {
            _descriptionExpanded = false;
          }
        }
      });
      if (switchTask) widget.onTaskChanged?.call(next.id);
    } catch (error) {
      if (!mounted || !valid()) return;
      final message = error is AppFailure ? error.message : '本地文件不可用';
      if (switchTask && current != null) {
        if (error is! AppFailure || error.kind != AppFailureKind.cancelled) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text(message)));
        }
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (valid()) _checking = null;
    }
  }

  Future<void> _select(DownloadTask next, {bool completed = false}) async {
    if (_checking == next.id || !WorkspaceActivity.isActive(context)) return;
    if (_verified?.id == next.id) {
      _generation++;
      _checking = null;
      if (completed && ref.exists(playbackSessionProvider)) {
        final session = ref.read(playbackSessionProvider);
        await session.repeatCompleted(session.sourceGeneration);
      }
      return;
    }
    await _verify(next, switchTask: true, completed: completed);
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(downloadSourceRepositoryProvider);
    final account = ref.watch(
      downloadControllerProvider.select(
        (_) => (source.accountScope, source.sessionEpoch),
      ),
    );
    if (_account != account) {
      _reset();
      _account = account;
    }
    final library = ref.watch(offlineLibraryProvider(account.$1));
    final id = _selected ?? widget.taskId;
    final location = library.find(id);
    final indexed = ref.watch(
      downloadQueueIndexProvider.select((index) => index.tasksById[id]),
    );
    final task = indexed?.scope == account.$1 ? indexed : null;
    final available =
        task != null &&
        location != null &&
        task.status == DownloadStatus.completed;
    if (!available && (_verified != null || _checking == id)) {
      _verified = null;
      _generation++;
      _checking = null;
    }
    if (available && _verified == null && _checking != id && _error == null) {
      unawaited(_verify(task));
    }
    final selected = _verified;
    if (selected == null || !available) {
      if (available && _error == null) {
        return const StateView.loading(message: '正在打开本地文件…');
      }
      final reason =
          _error ?? task?.failure?.message ?? '这项离线下载已不可用，可能已删除或切换了账号';
      return Column(
        children: [
          Flexible(
            child: StateView.empty(
              icon: Icons.video_file_outlined,
              message: reason,
              onAction: available
                  ? () => setState(() {
                      _error = null;
                    })
                  : _back,
              actionLabel: available ? '重试' : '返回下载',
            ),
          ),
          if (library.groups.isNotEmpty)
            Expanded(
              child: OfflinePlaylist(
                library: library,
                onSelect: _select,
                coverProvider: widget.coverProvider,
              ),
            ),
        ],
      );
    }
    final group = location.group, entry = location.entry;
    Future<void> step(
      int direction, {
      bool completed = false,
      bool loop = false,
    }) async {
      final next = group.adjacent(entry, direction, loop: loop);
      if (next != null) {
        await _select(next.preferred(selected), completed: completed);
      }
    }

    return PlaybackLayoutBuilder(
      builder: (context, bounds, listening) {
        final wide =
            bounds.maxWidth >=
            ResponsiveLayoutScope.of(context).playbackSideBySideWidth;
        final showInfo = _showInfo ?? !widget.autoCollapseSidebar;
        void toggle() => setState(() => _showInfo = !showInfo);
        Widget summary(bool measuring) => OfflineSummary(
          task: selected,
          work: library.workFor(selected.item),
          expanded: !measuring && _descriptionExpanded,
          onToggle: () =>
              setState(() => _descriptionExpanded = !_descriptionExpanded),
        );
        return PlaybackPageCommands(
          previousPart: () => step(-1),
          nextPart: () => step(1),
          hasNext: group.adjacent(entry, 1) != null,
          onCompleted: () => step(1, completed: true),
          onLoopCompleted: () => step(1, completed: true, loop: true),
          toggleInfo: toggle,
          toggleDescription: () => setState(() {
            _showInfo = true;
            _descriptionExpanded = !_descriptionExpanded;
          }),
          child: PlaybackLayoutSnapshot(
            builder: (context, dimensions, _) => PlaybackPageLayout(
              splitPage: group.kind == OfflineGroupKind.season
                  ? PlaybackSplitPage.pgc
                  : PlaybackSplitPage.video,
              wide: wide,
              showInfo: showInfo,
              listening: listening,
              dimensions: dimensions,
              collapsedHeight: listening
                  ? PlaybackLayoutBuilder.listeningHeight(bounds.maxHeight)
                  : math.min(bounds.maxWidth * 9 / 16, bounds.maxHeight * .55),
              contentKey: group.id,
              summaryIdentity: (selected.id, library.workFor(selected.item)),
              summaryBuilder: (context, {required measuring}) =>
                  summary(measuring),
              player: Builder(
                builder: (context) => widget.playerBuilder(context, selected),
              ),
              info: OfflinePlaylist(
                library: library,
                current: selected,
                onSelect: _select,
                onBack: _back,
                summary: summary(false),
                coverProvider: widget.coverProvider,
              ),
              toggleInfo: toggle,
              toggleTooltip: showInfo ? '收起离线信息' : '展开离线信息',
            ),
          ),
        );
      },
    );
  }
}
