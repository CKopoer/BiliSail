import '../../../shared/ui/bili_icons.dart';
import '../../../shared/ui/bili_coin_icon.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/input_stroke.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/network/api_requests.dart';
import '../../../core/presentation/input_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/shortcut_command.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../core/platform/external_links.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/video_card.dart';
import '../application/video_actions_controller.dart';
import '../domain/video_actions_repository.dart';

class VideoActionsScope extends ConsumerStatefulWidget {
  const VideoActionsScope({
    super.key,
    required this.detail,
    required this.onLogin,
    required this.child,
    this.active = true,
  });
  final VideoDetail detail;
  final VoidCallback onLogin;
  final Widget child;
  final bool active;
  @override
  ConsumerState<VideoActionsScope> createState() => _VideoActionsScopeState();
}

class _VideoActionsScopeState extends ConsumerState<VideoActionsScope> {
  bool _active = false;
  Object? _interaction;
  int _revision = 0;

  VideoActionTarget? get _target {
    final aid = widget.detail.aid;
    return aid == null ? null : (id: widget.detail.summary.id, aid: aid);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateActivity();
  }

  @override
  void didUpdateWidget(VideoActionsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.summary.id != widget.detail.summary.id ||
        oldWidget.detail.aid != widget.detail.aid) {
      _invalidateInteraction();
    }
    _updateActivity();
  }

  void _updateActivity() {
    final active = WorkspaceActivity.isActive(context) && widget.active;
    if (!active && _active) _invalidateInteraction();
    _active = active;
  }

  void _invalidateInteraction() {
    _revision++;
    _interaction = null;
  }

  bool Function() _currentOperation() {
    final revision = _revision;
    final scope = ref.read(videoActionsRepositoryProvider).accountScope;
    final epoch = ref.read(sessionEpochProvider);
    final startedAt = epoch();
    return () =>
        mounted &&
        _active &&
        revision == _revision &&
        epoch() == startedAt &&
        ref.read(videoActionsRepositoryProvider).accountScope == scope;
  }

  void _notice(String message) {
    if (mounted) {
      showAppNotice(context, message);
    }
  }

  Future<void> _run(
    Future<bool> Function(VideoActionsController) action,
  ) async {
    if (!_active) return;
    final target = _target;
    if (target == null) return;
    final provider = videoActionsControllerProvider(target);
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    final controller = ref.read(provider.notifier);
    final current = _currentOperation();
    await action(controller);
    if (current()) {
      final message = ref.read(provider).message;
      if (message != null) _notice(message);
    }
  }

  Future<void> _coin() async {
    final target = _target;
    if (target == null) return;
    final state = ref.read(videoActionsControllerProvider(target));
    if (!state.signedIn) {
      widget.onLogin();
      return;
    }
    final current = _currentOperation();
    final available = (2 - state.interaction.coins).clamp(0, 2);
    if (available == 0) {
      _notice('已为这个视频投币');
      return;
    }
    final count = await showAppDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('为视频投币'),
        content: const Text('选择本次投入的硬币数量'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          for (var count = 1; count <= available; count++)
            FilledButton(
              onPressed: () => Navigator.pop(context, count),
              child: Text('$count 枚'),
            ),
        ],
      ),
    );
    if (count != null && current()) {
      await _run((c) => c.coin(count));
    }
  }

  Future<void> _favorite() async {
    final target = _target;
    if (target == null) return;
    final provider = videoActionsControllerProvider(target);
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    final current = _currentOperation();
    try {
      final folders = await ref.read(provider.notifier).folders();
      if (!mounted ||
          !current() ||
          InputScope.of<Object>(context)?.routes.modal == true) {
        return;
      }
      final selected = await showAppDialog<Set<String>>(
        context: context,
        builder: (_) => _FavoriteDialog(folders: folders),
      );
      if (selected != null && current()) {
        await _run((c) => c.favorite(folders, selected));
      }
    } catch (e) {
      if (current() &&
          (e is! AppFailure || e.kind != AppFailureKind.cancelled)) {
        _notice(e is AppFailure ? e.message : '收藏夹加载失败，请重试');
      }
    }
  }

  Future<CommandOutcome> _share() async {
    final revision = _revision;
    try {
      await Clipboard.setData(
        ClipboardData(
          text:
              'https://www.bilibili.com/video/${widget.detail.summary.id.value}',
        ),
      );
    } on PlatformException {
      if (revision == _revision) _notice('无法复制视频链接');
      return CommandOutcome.failed;
    }
    if (revision == _revision) _notice('视频链接已复制');
    return CommandOutcome.completed;
  }

  Future<CommandOutcome> _invoke(ShortcutAction action) async {
    if (!_active) return CommandOutcome.stale;
    if (action == ShortcutAction.shareVideo) return _share();
    final target = _target;
    if (target == null) return CommandOutcome.noOp;
    final state = ref.read(videoActionsControllerProvider(target));
    if (_interaction != null || state.busy) return CommandOutcome.busy;
    final allowed = switch (action) {
      ShortcutAction.likeVideo => _enabled(state, 'like', needsState: true),
      ShortcutAction.coinVideo => _enabled(state, 'coin', needsState: true),
      ShortcutAction.favoriteVideo => _enabled(state, 'favorite'),
      _ => false,
    };
    if (!allowed) return CommandOutcome.noOp;
    final interaction = Object();
    setState(() => _interaction = interaction);
    try {
      await switch (action) {
        ShortcutAction.likeVideo => _run((c) => c.toggleLike()),
        ShortcutAction.coinVideo => _coin(),
        _ => _favorite(),
      };
      return CommandOutcome.completed;
    } finally {
      if (mounted && identical(_interaction, interaction)) {
        setState(() => _interaction = null);
      }
    }
  }

  bool _enabled(
    VideoActionsState state,
    String action, {
    bool needsState = false,
  }) =>
      _target != null &&
      _interaction == null &&
      !state.busy &&
      !state.uncertain.contains(action) &&
      (!state.signedIn || !needsState || state.loaded && !state.loading);

  void _refresh() {
    if (_target case final target?) {
      ref.read(videoActionsControllerProvider(target).notifier).refresh();
    }
  }

  Future<void> _openOfficial() async {
    try {
      final opened = await ref.read(externalLinkOpenerProvider)(
        Uri.https(
          'www.bilibili.com',
          '/video/${widget.detail.summary.id.value}',
        ),
      );
      if (!opened) _notice('无法打开官方页面');
    } on PlatformException {
      _notice('无法打开官方页面');
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final state = target == null
        ? const VideoActionsState()
        : ref.watch(videoActionsControllerProvider(target));
    return CommandTargetScope<Object>(
      scope: CommandScope.page,
      active: _active,
      revision: () => _revision,
      commands: {
        for (final action in [
          if (target != null) ...[
            ShortcutAction.likeVideo,
            ShortcutAction.coinVideo,
            ShortcutAction.favoriteVideo,
          ],
          ShortcutAction.shareVideo,
        ])
          action: (stroke) => stroke.phase == InputPhase.down
              ? _invoke(action)
              : CommandOutcome.noOp,
      },
      child: _VideoActionsView(
        owner: this,
        detail: widget.detail,
        state: state,
        pending: _interaction != null,
        child: widget.child,
      ),
    );
  }
}

class _VideoActionsView extends InheritedWidget {
  const _VideoActionsView({
    required this.owner,
    required this.detail,
    required this.state,
    required this.pending,
    required super.child,
  });
  final _VideoActionsScopeState owner;
  final VideoDetail detail;
  final VideoActionsState state;
  final bool pending;

  @override
  bool updateShouldNotify(_VideoActionsView oldWidget) =>
      owner != oldWidget.owner ||
      detail != oldWidget.detail ||
      state != oldWidget.state ||
      pending != oldWidget.pending;
}

class VideoActionsBar extends StatelessWidget {
  const VideoActionsBar({
    super.key,
    this.menuOnly = false,
    this.onReload,
    this.onDownload,
  });
  final bool menuOnly;
  final VoidCallback? onReload;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final view = context
        .dependOnInheritedWidgetOfExactType<_VideoActionsView>();
    if (view == null) return const SizedBox.shrink();
    final owner = view.owner;
    final state = view.state;
    bool enabled(String action, {bool needsState = false}) =>
        owner._enabled(state, action, needsState: needsState);
    if (menuOnly) {
      return PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (value) {
          if (value == 'download') onDownload?.call();
          if (value == 'watchLater') {
            owner._run((c) => c.watchLater());
          }
          if (value == 'reload') {
            owner._refresh();
            onReload?.call();
          }
        },
        itemBuilder: (_) => [
          if (onDownload != null)
            const PopupMenuItem(value: 'download', child: Text('下载视频')),
          PopupMenuItem(
            value: 'watchLater',
            enabled: enabled('watchLater') && !state.watchLaterAdded,
            child: Text(state.watchLaterAdded ? '已加入稍后再看' : '稍后再看'),
          ),
          const PopupMenuItem(value: 'reload', child: Text('重新加载')),
        ],
      );
    }
    Widget action(
      Widget icon,
      String label,
      VoidCallback? onTap, {
      bool selected = false,
    }) => IconButton(
      tooltip: label,
      onPressed: onTap,
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      iconSize: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      icon: icon,
    );
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            action(
              Icon(
                state.interaction.liked
                    ? Icons.thumb_up_alt
                    : Icons.thumb_up_alt_outlined,
              ),
              state.interaction.liked
                  ? '已点赞'
                  : '点赞 ${compactCount(view.detail.likeCount)}',
              enabled('like', needsState: true)
                  ? () => owner._invoke(ShortcutAction.likeVideo)
                  : null,
              selected: state.interaction.liked,
            ),
            action(
              BiliCoinIcon(filled: state.interaction.coins > 0),
              state.interaction.coins > 0
                  ? '已投 ${state.interaction.coins} 枚'
                  : '投币 ${compactCount(view.detail.coinCount)}',
              enabled('coin', needsState: true)
                  ? () => owner._invoke(ShortcutAction.coinVideo)
                  : null,
              selected: state.interaction.coins > 0,
            ),
            action(
              Icon(
                state.interaction.favorited
                    ? BiliIcons.favoriteFilled
                    : BiliIcons.favorite,
              ),
              state.interaction.favorited
                  ? '已收藏'
                  : '收藏 ${compactCount(view.detail.favoriteCount)}',
              enabled('favorite')
                  ? () => owner._invoke(ShortcutAction.favoriteVideo)
                  : null,
              selected: state.interaction.favorited,
            ),
            action(
              const Icon(BiliIcons.share),
              '分享',
              () => owner._invoke(ShortcutAction.shareVideo),
            ),
            action(const Icon(Icons.open_in_new), '官方页面', owner._openOfficial),
            if (onDownload != null)
              action(const Icon(Icons.download_outlined), '下载视频', onDownload),
            if (state.message case final String message when !state.busy)
              Tooltip(
                message: message,
                child: Icon(
                  state.uncertain.isNotEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteDialog extends StatefulWidget {
  const _FavoriteDialog({required this.folders});
  final List<FavoriteFolder> folders;
  @override
  State<_FavoriteDialog> createState() => _FavoriteDialogState();
}

class _FavoriteDialogState extends State<_FavoriteDialog> {
  late final Set<String> _selected = widget.folders
      .where((f) => f.containsVideo)
      .map((f) => f.id)
      .toSet();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('收藏到'),
    content: SizedBox(
      width: 360,
      child: widget.folders.isEmpty
          ? const Text('还没有收藏夹，请先在哔哩哔哩创建收藏夹。')
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final folder in widget.folders)
                    CheckboxListTile(
                      title: Text(folder.title),
                      value: _selected.contains(folder.id),
                      onChanged: (value) => setState(
                        () => value == true
                            ? _selected.add(folder.id)
                            : _selected.remove(folder.id),
                      ),
                    ),
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: widget.folders.isEmpty
            ? null
            : () => Navigator.pop(context, _selected),
        child: const Text('保存'),
      ),
    ],
  );
}
