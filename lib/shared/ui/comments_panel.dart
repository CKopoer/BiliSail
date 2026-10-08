import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/external_links.dart';
import '../../core/presentation/workspace_activity.dart';
import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../domain/user.dart';
import '../../domain/comment_target.dart';
import 'app_network_image.dart';
import 'app_notice.dart';
import 'emoticon_picker_dialog.dart';
import 'network_avatar.dart';
import 'bili_icons.dart';
import 'comment_rich_content.dart';
import 'comment_text_styles.dart';
import '../../features/comments/application/comments_controller.dart';
import '../../features/comments/application/comment_link_resolver.dart';
import '../../features/comments/domain/comments_repository.dart';

class CommentsPanel extends ConsumerStatefulWidget {
  const CommentsPanel({
    super.key,
    required this.target,
    this.replyCount,
    this.onSeek,
    this.onLogin,
    this.onOpenUser,
  });
  final CommentTarget target;
  final int? replyCount;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  @override
  ConsumerState<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<CommentsPanel> {
  NotifierProvider<CommentsController, CommentsState> get _provider =>
      widget.target.type == CommentTargetType.video
      ? videoCommentsControllerProvider(widget.target.oid)
      : commentsControllerProvider(widget.target);
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _topScroll = ScrollController();
  final _replyScroll = ScrollController();
  double _topOffset = 0;
  String? _shownRoot;
  RequestCancellation? _linkCancellation;
  @override
  void initState() {
    super.initState();
    _topScroll.addListener(() => _topOffset = _topScroll.offset);
  }

  @override
  void didUpdateWidget(covariant CommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _linkCancellation?.cancel();
      _text.clear();
      _topOffset = 0;
      _shownRoot = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _topScroll.hasClients) _topScroll.jumpTo(0);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!WorkspaceActivity.isActive(context)) _linkCancellation?.cancel();
  }

  @override
  void dispose() {
    _linkCancellation?.cancel();
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

  Future<void> _openLink(Uri uri) async {
    _linkCancellation?.cancel();
    final cancellation = RequestCancellation();
    _linkCancellation = cancellation;
    final target = widget.target;
    final controller = ref.read(_provider.notifier);
    final state = ref.read(_provider);
    bool isCurrent() =>
        mounted &&
        !cancellation.isCancelled &&
        widget.target == target &&
        WorkspaceActivity.isActive(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        controller.isCurrentAccount(state.accountScope, state.sessionEpoch);
    var opened = false;
    try {
      final navigate = ref.read(commentVideoNavigatorProvider);
      if (navigate != null) {
        final video = await ref
            .read(commentLinkResolverProvider)
            .resolve(uri, cancellation);
        if (!mounted || !isCurrent()) return;
        if (video != null) {
          if (ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
          navigate(video);
          return;
        }
      }
      if (!isCurrent()) return;
      opened = await ref.read(webLinkOpenerProvider)(uri);
    } on AppFailure catch (error) {
      if (mounted && isCurrent() && error.kind != AppFailureKind.cancelled) {
        showAppNotice(context, error.message);
      }
      return;
    } on PlatformException {
      opened = false;
    } finally {
      if (identical(_linkCancellation, cancellation)) _linkCancellation = null;
    }
    if (mounted && isCurrent() && !opened) {
      showAppNotice(context, '无法打开浏览器，请稍后重试');
    }
  }

  Future<void> _emotes(String oid) async {
    final target = widget.target;
    final provider = _provider;
    final controller = ref.read(provider.notifier);
    final snapshot = ref.read(provider);
    final scope = snapshot.accountScope, epoch = snapshot.sessionEpoch;
    final container = ProviderScope.containerOf(context);
    unawaited(controller.loadEmotes());
    final emote = await showDialog<CommentEmote>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _CommentEmoteDialog(target: target),
      ),
    );
    if (emote == null ||
        !mounted ||
        widget.target != target ||
        !controller.isCurrentAccount(scope, epoch) ||
        !ref.read(provider).signedIn) {
      return;
    }
    _text.value = insertCommentEmote(_text.value, emote.text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final oid = widget.target.oid;
    if (oid.isEmpty) return const Center(child: Text('暂无评论信息'));
    final state = ref.watch(_provider);
    final controller = ref.read(_provider.notifier);
    ref.listen(
      _provider.select((value) => (value.accountScope, value.sessionEpoch)),
      (_, _) {
        _text.clear();
        _topOffset = 0;
        _shownRoot = null;
      },
    );
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
      onOpenLink: (uri) => unawaited(_openLink(uri)),
      onSeek: widget.onSeek,
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
    return CustomMultiChildLayout(
      delegate: _CommentsLayoutDelegate(),
      children: [
        LayoutId(
          id: _CommentsSlot.header,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
            ],
          ),
        ),
        LayoutId(
          id: _CommentsSlot.list,
          child: ListView(
            controller: root == null ? _topScroll : _replyScroll,
            key: PageStorageKey(
              'comments:${widget.target.type.name}:$oid:${root?.id ?? state.sort.name}',
            ),
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
                                (root == null && (widget.replyCount ?? 0) > 0)
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
        LayoutId(
          id: _CommentsSlot.composer,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      top: BorderSide(
                        color: theme.dividerColor.withValues(alpha: .3),
                      ),
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
                              onPressed: state.busy
                                  ? null
                                  : controller.cancelTarget,
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
                            onPressed: state.busy ? null : () => _emotes(oid),
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
                                    final submittedTarget = widget.target;
                                    final submittedRoot = state.openRoot?.id;
                                    if (await controller.send(submitted) &&
                                        mounted &&
                                        widget.target == submittedTarget &&
                                        _text.text == submitted) {
                                      final current = ref.read(_provider);
                                      if (current.openRoot?.id ==
                                              submittedRoot &&
                                          current.replyTarget == null) {
                                        _text.clear();
                                      }
                                    }
                                  },
                            child: state.busy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('发布'),
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
    );
  }
}

final class _CommentEmoteDialog extends ConsumerWidget {
  const _CommentEmoteDialog({required this.target});
  final CommentTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = target.type == CommentTargetType.video
        ? videoCommentsControllerProvider(target.oid)
        : commentsControllerProvider(target);
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
    required this.onOpenLink,
    this.onSeek,
  });
  final CommentEntry comment;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri> onOpenLink;
  final ValueChanged<Duration>? onSeek;
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
                CommentRichContent(
                  comment: c,
                  onOpenUser: onOpenUser,
                  onOpenLink: onOpenLink,
                  onSeek: onSeek,
                ),
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
                                        onOpenUser: onOpenUser,
                                        compact: true,
                                        onOpenLink: onOpenLink,
                                        onSeek: onSeek,
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

enum _CommentsSlot { header, list, composer }

/// Measure controls and the draft first. When a keyboard leaves too little
/// height, the composer scrolls within the real remaining space.
class _CommentsLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final header = layoutChild(
      _CommentsSlot.header,
      BoxConstraints.tightFor(width: size.width)
          .copyWith(maxHeight: size.height),
    );
    positionChild(_CommentsSlot.header, Offset.zero);
    final available = (size.height - header.height).clamp(0.0, size.height);
    final composer = layoutChild(
      _CommentsSlot.composer,
      BoxConstraints.tightFor(width: size.width).copyWith(maxHeight: available),
    );
    final listHeight = (available - composer.height).clamp(0.0, available);
    layoutChild(
      _CommentsSlot.list,
      BoxConstraints.tight(Size(size.width, listHeight)),
    );
    positionChild(_CommentsSlot.list, Offset(0, header.height));
    positionChild(
      _CommentsSlot.composer,
      Offset(0, size.height - composer.height),
    );
  }

  @override
  bool shouldRelayout(_CommentsLayoutDelegate oldDelegate) => false;
}
