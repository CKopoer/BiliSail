import '../../../shared/ui/bili_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/video_card.dart';
import '../application/video_actions_controller.dart';
import '../domain/video_actions_repository.dart';

class VideoActionsBar extends ConsumerStatefulWidget {
  const VideoActionsBar({
    super.key,
    required this.detail,
    required this.onLogin,
    this.menuOnly = false,
    this.onReload,
  });
  final VideoDetail detail;
  final VoidCallback onLogin;
  final bool menuOnly;
  final VoidCallback? onReload;
  @override
  ConsumerState<VideoActionsBar> createState() => _VideoActionsBarState();
}

class _VideoActionsBarState extends ConsumerState<VideoActionsBar> {
  bool _foldersLoading = false;
  VideoActionTarget? get _target {
    final aid = widget.detail.aid;
    return aid == null ? null : (id: widget.detail.summary.id, aid: aid);
  }

  void _notice(String message) {
    if (mounted) {
      showAppNotice(context, message);
    }
  }

  Future<void> _run(
    Future<bool> Function(VideoActionsController) action,
  ) async {
    final target = _target;
    if (target == null) return;
    final provider = videoActionsControllerProvider(target);
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    final controller = ref.read(provider.notifier);
    await action(controller);
    if (mounted && _target == target) {
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
    final scope = ref.read(videoActionsRepositoryProvider).accountScope;
    final available = (2 - state.interaction.coins).clamp(0, 2);
    if (available == 0) {
      _notice('已为这个视频投币');
      return;
    }
    final count = await showDialog<int>(
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
    if (count != null &&
        mounted &&
        _target == target &&
        ref.read(videoActionsRepositoryProvider).accountScope == scope) {
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
    final scope = ref.read(videoActionsRepositoryProvider).accountScope;
    setState(() => _foldersLoading = true);
    try {
      final folders = await ref.read(provider.notifier).folders();
      if (!mounted ||
          _target != target ||
          ref.read(videoActionsRepositoryProvider).accountScope != scope) {
        return;
      }
      final selected = await showDialog<Set<String>>(
        context: context,
        builder: (_) => _FavoriteDialog(folders: folders),
      );
      if (selected != null &&
          mounted &&
          _target == target &&
          ref.read(videoActionsRepositoryProvider).accountScope == scope) {
        await _run((c) => c.favorite(folders, selected));
      }
    } catch (e) {
      if (e is! AppFailure || e.kind != AppFailureKind.cancelled) {
        _notice(e is AppFailure ? e.message : '收藏夹加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _foldersLoading = false);
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
    final busy = state.busy || _foldersLoading;
    bool enabled(String action, {bool needsState = false}) =>
        target != null &&
        !busy &&
        !state.uncertain.contains(action) &&
        (!state.signedIn || !needsState || state.loaded && !state.loading);
    if (widget.menuOnly) {
      return PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (value) {
          if (value == 'watchLater') {
            _run((c) => c.watchLater());
          }
          if (value == 'reload') {
            if (target != null) {
              ref
                  .read(videoActionsControllerProvider(target).notifier)
                  .refresh();
            }
            widget.onReload?.call();
          }
        },
        itemBuilder: (_) => [
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
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool selected = false,
    }) => IconButton(
      tooltip: label,
      onPressed: onTap,
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      icon: Icon(icon, size: 22),
    );
    return SizedBox(
      height: 42 + MediaQuery.textScalerOf(context).scale(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            action(
              state.interaction.liked ? BiliIcons.like : BiliIcons.like,
              state.interaction.liked
                  ? '已点赞'
                  : '点赞 ${compactCount(widget.detail.likeCount)}',
              enabled('like', needsState: true)
                  ? () => _run((c) => c.toggleLike())
                  : null,
              selected: state.interaction.liked,
            ),
            action(
              BiliIcons.coin,
              state.interaction.coins > 0
                  ? '已投 ${state.interaction.coins} 枚'
                  : '投币 ${compactCount(widget.detail.coinCount)}',
              enabled('coin', needsState: true) ? _coin : null,
              selected: state.interaction.coins > 0,
            ),
            action(
              state.interaction.favorited
                  ? BiliIcons.favoriteFilled
                  : BiliIcons.favorite,
              state.interaction.favorited
                  ? '已收藏'
                  : '收藏 ${compactCount(widget.detail.favoriteCount)}',
              enabled('favorite') ? _favorite : null,
              selected: state.interaction.favorited,
            ),
            action(BiliIcons.share, '分享', () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      'https://www.bilibili.com/video/${widget.detail.summary.id.value}',
                ),
              );
              _notice('视频链接已复制');
            }),
            action(Icons.open_in_new, '官方页面', _openOfficial),
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
