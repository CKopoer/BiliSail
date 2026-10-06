import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/emoticon_picker_dialog.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/bili_icons.dart';
import 'comment_rich_content.dart';
import 'comment_text_styles.dart';
import '../application/video_comments_controller.dart';
import '../domain/video_comments_repository.dart';

class VideoCommentsPanel extends ConsumerStatefulWidget {
  const VideoCommentsPanel({
    super.key,
    required this.detail,
    this.onLogin,
    this.onOpenUser,
  });
  final VideoDetail detail;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  @override
  ConsumerState<VideoCommentsPanel> createState() => _VideoCommentsPanelState();
}

class _VideoCommentsPanelState extends ConsumerState<VideoCommentsPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _topScroll = ScrollController();
  final _replyScroll = ScrollController();
  double _topOffset = 0;
  String? _shownRoot;
  @override
  void initState() {
    super.initState();
    _topScroll.addListener(() => _topOffset = _topScroll.offset);
  }

  @override
  void didUpdateWidget(covariant VideoCommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.aid != widget.detail.aid) {
      _text.clear();
      _topOffset = 0;
      _shownRoot = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _topScroll.hasClients) _topScroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _topScroll.dispose();
    _replyScroll.dispose();
    super.dispose();
  }

  void _login() {
    final action = widget.onLogin;
    if (action != null) {
      action();
    } else {
      showAppNotice(context, '请先登录后操作');
    }
  }

  Future<void> _emotes(String aid) async {
    final provider = videoCommentsControllerProvider(aid);
    final repository = ref.read(videoCommentsRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final container = ProviderScope.containerOf(context);
    unawaited(ref.read(provider.notifier).loadEmotes());
    final emote = await showDialog<CommentEmote>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _CommentEmoteDialog(aid: aid),
      ),
    );
    if (emote == null ||
        !mounted ||
        widget.detail.aid != aid ||
        repository.accountScope != scope ||
        repository.sessionEpoch != epoch ||
        !ref.read(provider).signedIn) {
      return;
    }
    _text.value = insertCommentEmote(_text.value, emote.text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final aid = widget.detail.aid;
    if (aid == null || aid.isEmpty) return const Center(child: Text('暂无评论信息'));
    final state = ref.watch(videoCommentsControllerProvider(aid));
    final controller = ref.read(videoCommentsControllerProvider(aid).notifier);
    final theme = Theme.of(context);
    final styles = CommentTextStyles(theme);
    final root = state.openRoot;
    if (_shownRoot != root?.id) {
      _shownRoot = root?.id;
      final offset = root == null ? _topOffset : 0.0;
      final scroll = root == null ? _topScroll : _replyScroll;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
        }
      });
    }
    void reply(CommentEntry c) {
      if (!state.signedIn) {
        _login();
        return;
      }
      controller.target(c);
      _focus.requestFocus();
    }

    Widget entry(CommentEntry c, {bool preview = true}) => _CommentTile(
      onOpenUser: widget.onOpenUser,
      comment: c,
      busy:
          state.busy ||
          state.loading ||
          state.replyLoading ||
          state.uncertain.contains('like:${c.id}'),
      onLike: () => state.signedIn ? controller.toggleLike(c) : _login(),
      onReply: () => reply(c),
      onOpen: () => controller.openReplies(c),
      preview: preview,
    );
    final comments = root == null ? state.items : state.replyItems;
    final loading = root == null ? state.loading : state.replyLoading;
    final more = root == null ? state.hasMore : state.replyHasMore;
    return Column(
      children: [
        if (root == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 2),
            child: Row(
              children: [
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => controller.load(sort: CommentSort.hot),
                  child: Text(
                    '最热',
                    style: styles.sort.copyWith(
                      color: state.sort == CommentSort.hot
                          ? styles.sort.color
                          : styles.metadata.color,
                    ),
                  ),
                ),
                Text('|', style: theme.textTheme.bodySmall),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => controller.load(sort: CommentSort.latest),
                  child: Text(
                    '最新',
                    style: styles.sort.copyWith(
                      color: state.sort == CommentSort.latest
                          ? styles.sort.color
                          : styles.metadata.color,
                    ),
                  ),
                ),
                const Spacer(),
                if (state.totalCount != null)
                  Text('${state.totalCount} 条', style: styles.metadata),
                IconButton(
                  tooltip: '刷新评论',
                  onPressed: state.busy
                      ? null
                      : () => controller.load(refresh: true),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              IconButton(
                tooltip: '返回评论',
                onPressed: state.busy ? null : controller.closeReplies,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('详情', style: theme.textTheme.titleSmall),
            ],
          ),
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(state.message!, style: theme.textTheme.bodySmall),
          ),
        Expanded(
          child: ListView(
            controller: root == null ? _topScroll : _replyScroll,
            key: PageStorageKey('comments:$aid:${root?.id ?? state.sort.name}'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            children: [
              if (root != null) ...[
                entry(root, preview: false),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '全部回复 ${root.replyCount}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
              if (comments.isEmpty && !loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      state.message != null
                          ? '暂时无法加载评论'
                          : (root?.replyCount ?? state.totalCount ?? 0) > 0 ||
                                (root == null &&
                                    (widget.detail.replyCount ?? 0) > 0)
                          ? '当前会话未返回可展示的评论'
                          : '还没有评论，来聊聊吧',
                    ),
                  ),
                ),
              ...comments.map((c) => entry(c, preview: root == null)),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (more)
                Center(
                  child: TextButton(
                    onPressed: state.busy
                        ? null
                        : () => root == null
                              ? controller.load()
                              : controller.loadReplies(),
                    child: Text(state.message == null ? '加载更多' : '重试加载'),
                  ),
                )
              else if (comments.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      comments.length >= 500 ? '已显示 500 条评论' : '没有更多了',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (state.uncertain.contains('send'))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton(
              onPressed: controller.acknowledgeSend,
              child: const Text('我已核对结果，允许再次发送'),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: .3)),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.replyTarget != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '回复 @${state.replyTarget!.author}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '取消回复',
                      onPressed: state.busy ? null : controller.cancelTarget,
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              TextField(
                controller: _text,
                focusNode: _focus,
                readOnly: !state.signedIn,
                onTap: state.signedIn ? null : _login,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: state.signedIn
                      ? root == null
                            ? '发一条友善的评论'
                            : '发一条友善的回复'
                      : '登录后参与评论',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '选择表情',
                    onPressed: state.busy ? null : () => _emotes(aid),
                    icon: const Icon(BiliIcons.emoji),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        state.busy ||
                            state.loading ||
                            state.replyLoading ||
                            state.uncertain.contains('send')
                        ? null
                        : () async {
                            if (!state.signedIn) {
                              _login();
                              return;
                            }
                            final submitted = _text.text;
                            final submittedRoot = state.openRoot?.id;
                            if (await controller.send(submitted) &&
                                mounted &&
                                widget.detail.aid == aid &&
                                _text.text == submitted) {
                              final current = ref.read(
                                videoCommentsControllerProvider(aid),
                              );
                              if (current.openRoot?.id == submittedRoot &&
                                  current.replyTarget == null) {
                                _text.clear();
                              }
                            }
                          },
                    child: state.busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('发布'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _CommentEmoteDialog extends ConsumerWidget {
  const _CommentEmoteDialog({required this.aid});
  final String aid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = videoCommentsControllerProvider(aid);
    final state = ref.watch(provider);
    return EmoticonPickerDialog(
      title: '评论表情包',
      loading: state.emotesLoading,
      message: state.emotesMessage,
      emptyMessage: '暂无可用表情',
      onRetry: ref.read(provider.notifier).loadEmotes,
      packageNames: [for (final package in state.emotePackages) package.name],
      packageBuilder: (context, packageIndex) {
        final package = state.emotePackages[packageIndex];
        return GridView.builder(
          key: PageStorageKey('comment-emoticon-package-$packageIndex'),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 72,
            mainAxisExtent: 56,
          ),
          itemCount: package.items.length,
          itemBuilder: (context, index) {
            final emote = package.items[index];
            return Tooltip(
              message: emote.text,
              child: TextButton(
                onPressed: !state.signedIn || state.busy
                    ? null
                    : () => Navigator.pop(context, emote),
                child: emote.imageUrl == null
                    ? Text(
                        emote.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : AppNetworkImage(
                        url: emote.imageUrl.toString(),
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                        cacheWidth: 96,
                        cacheHeight: 96,
                        errorBuilder: (_, _, _) => Text(
                          emote.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.busy,
    required this.onLike,
    required this.onReply,
    required this.onOpen,
    this.preview = true,
    this.onOpenUser,
  });
  final CommentEntry comment;
  final ValueChanged<UserId>? onOpenUser;
  final bool busy, preview;
  final VoidCallback onLike, onReply, onOpen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), c = comment;
    final styles = CommentTextStyles(theme);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: c.authorId?.isValid == true && onOpenUser != null
                ? () => onOpenUser!(c.authorId!)
                : null,
            child: NetworkAvatar(url: c.avatarUrl, name: c.author, radius: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommentAuthorHeader(comment: c, onOpenUser: onOpenUser),
                const SizedBox(height: 8),
                CommentRichContent(comment: c),
                Row(
                  children: [
                    IconButton(
                      tooltip: c.liked ? '取消点赞评论' : '点赞评论',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy ? null : onLike,
                      iconSize: 16,
                      color: c.liked
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      icon: const Icon(BiliIcons.like),
                    ),
                    Text('${c.likeCount}', style: styles.action),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: '回复评论',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy ? null : onReply,
                      iconSize: 17,
                      color: theme.colorScheme.outline,
                      icon: const Icon(BiliIcons.reply),
                    ),
                  ],
                ),
                if (preview && (c.replyCount > 0 || c.replies.isNotEmpty))
                  InkWell(
                    onTap: busy ? null : onOpen,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...c.replies
                              .take(2)
                              .map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap:
                                            r.authorId?.isValid == true &&
                                                onOpenUser != null
                                            ? () => onOpenUser!(r.authorId!)
                                            : null,
                                        child: Text(
                                          '${r.author}：',
                                          style: styles.previewAuthor,
                                        ),
                                      ),
                                      CommentRichContent(
                                        comment: r,
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          Text(
                            '共 ${c.replyCount} 条回复 ›',
                            style: styles.metadata.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: .35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
