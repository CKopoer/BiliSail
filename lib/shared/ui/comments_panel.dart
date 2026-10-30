import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_dialog.dart';
import '../../core/platform/external_links.dart';
import '../../core/presentation/workspace_activity.dart';
import '../../core/presentation/page_back_scope.dart';
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
      commentsProviderFor(widget.target);
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _composerFocus = FocusNode(skipTraversal: true);
  final _emotePickerOpen = ValueNotifier(false);
  final _topScroll = ScrollController();
  // Detail always opens at the top; do not retain a PageStorage entry per root.
  final _replyScroll = ScrollController(keepScrollOffset: false);
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
      final target = widget.target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.target == target && _topScroll.hasClients) {
          _topScroll.jumpTo(0);
        }
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
    _composerFocus.dispose();
    _emotePickerOpen.dispose();
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

  void _handleOpenLink(Uri uri) => unawaited(_openLink(uri));

  Future<void> _emotes() async {
    final target = widget.target;
    final provider = _provider;
    final controller = ref.read(provider.notifier);
    final snapshot = ref.read(provider);
    final scope = snapshot.accountScope, epoch = snapshot.sessionEpoch;
    final container = ProviderScope.containerOf(context);
    unawaited(controller.loadEmotes());
    _emotePickerOpen.value = true;
    CommentEmote? emote;
    try {
      emote = await showAppDialog<CommentEmote>(
        context: context,
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: _CommentEmoteDialog(target: target),
        ),
      );
    } finally {
      if (mounted) _emotePickerOpen.value = false;
    }
    if (!mounted ||
        widget.target != target ||
        !controller.isCurrentAccount(scope, epoch) ||
        !ref.read(provider).signedIn) {
      return;
    }
    if (emote != null) {
      _text.value = insertCommentEmote(_text.value, emote.text);
    }
    _focus.requestFocus();
  }

  List<CommentEntry>? _indexedComments;
  Map<String, int> _commentIndices = const {};

  bool _closeDetail() {
    if (ref.read(_provider).openRoot == null) return false;
    ref.read(_provider.notifier).closeReplies();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.target.oid.isEmpty) {
      return const Center(child: Text('暂无评论信息'));
    }
    final rootId = ref.watch(_provider.select((state) => state.openRoot?.id));
    ref.listen(
      _provider.select((value) => (value.accountScope, value.sessionEpoch)),
      (_, _) {
        _linkCancellation?.cancel();
        _text.clear();
        _topOffset = 0;
        _shownRoot = null;
      },
    );
    if (_shownRoot != rootId) {
      _shownRoot = rootId;
      final offset = rootId == null ? _topOffset : 0.0;
      final scroll = rootId == null ? _topScroll : _replyScroll;
      final target = widget.target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.target == target &&
            _shownRoot == rootId &&
            scroll.hasClients) {
          scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
        }
      });
    }
    return PageBackHandler(
      enabled: rootId != null,
      onBack: _closeDetail,
      child: CustomMultiChildLayout(
        delegate: _CommentsLayoutDelegate(),
        children: [
          LayoutId(id: _CommentsSlot.header, child: _header()),
          LayoutId(id: _CommentsSlot.list, child: _list()),
          LayoutId(id: _CommentsSlot.composer, child: _composer()),
        ],
      ),
    );
  }

  Widget _header() => Consumer(
    builder: (context, ref, _) {
      ref.watch(
        _provider.select(
          (state) => (
            state.sort,
            state.totalCount,
            state.busy,
            state.message,
            state.openRoot?.id,
          ),
        ),
      );
      final state = ref.read(_provider);
      final controller = ref.read(_provider.notifier);
      final theme = Theme.of(context);
      final styles = CommentTextStyles(theme);
      final root = state.openRoot;
      return Column(
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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回评论',
                      onPressed: _closeDetail,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text('评论详情', style: theme.textTheme.titleSmall),
                    ),
                    IconButton(
                      tooltip: '关闭评论详情',
                      onPressed: _closeDetail,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(state.message!, style: theme.textTheme.bodySmall),
            ),
        ],
      );
    },
  );

  Widget _composer() => Focus(
    focusNode: _composerFocus,
    child: TextFieldTapRegion(
      child: ListenableBuilder(
        listenable: Listenable.merge([_composerFocus, _emotePickerOpen]),
        builder: (context, _) => _composerContent(
          expanded: _composerFocus.hasFocus || _emotePickerOpen.value,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        ),
      ),
    ),
  );

  Widget _composerContent({
    required bool expanded,
    required Duration duration,
  }) => Consumer(
    builder: (context, ref, _) {
      ref.watch(
        _provider.select(
          (state) => (
            state.busy,
            state.loading,
            state.replyLoading,
            state.signedIn,
            state.uncertain.contains('send'),
            state.replyTarget,
            state.openRoot?.id,
          ),
        ),
      );
      final state = ref.read(_provider);
      final controller = ref.read(_provider.notifier);
      final theme = Theme.of(context);
      final root = state.openRoot;
      final inputStyle = theme.textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        height: 1.4,
      );
      final iconStyle = IconButton.styleFrom(
        minimumSize: const Size.square(32),
        padding: const EdgeInsets.all(6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
      return SingleChildScrollView(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          style: iconStyle,
                          onPressed: state.busy
                              ? null
                              : controller.cancelTarget,
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  AnimatedSize(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      // Keep native Enter behavior stable while collapsed.
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: inputStyle,
                      readOnly: !state.signedIn,
                      onTap: state.signedIn ? null : _login,
                      onTapOutside: (_) => _composerFocus.unfocus(),
                      minLines: 1,
                      maxLines: expanded ? 4 : 1,
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  ExcludeFocus(
                    excluding: !expanded,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => SizeTransition(
                          sizeFactor: animation,
                          alignment: Alignment.topCenter,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                        child: expanded
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: '选择表情',
                                      style: iconStyle,
                                      iconSize: 18,
                                      onPressed: state.busy ? null : _emotes,
                                      icon: const Icon(BiliIcons.emoji),
                                    ),
                                    const Spacer(),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(56, 32),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        textStyle: theme.textTheme.labelMedium,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
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
                                              final submittedTarget =
                                                  widget.target;
                                              final submittedRoot =
                                                  state.openRoot?.id;
                                              if (await controller.send(
                                                    submitted,
                                                  ) &&
                                                  mounted &&
                                                  widget.target ==
                                                      submittedTarget &&
                                                  _text.text == submitted) {
                                                final current = ref.read(
                                                  _provider,
                                                );
                                                if (current.openRoot?.id ==
                                                        submittedRoot &&
                                                    current.replyTarget ==
                                                        null) {
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
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _entry(
    CommentEntry comment, {
    required bool preview,
    bool root = false,
  }) => _CommentTile(
    key: ValueKey((root ? 'comment-root' : 'comment', comment.id)),
    provider: _provider,
    comment: comment,
    preview: preview,
    onOpenUser: widget.onOpenUser,
    onOpenLink: _handleOpenLink,
    onSeek: widget.onSeek,
    onLogin: _login,
    onReplyFocus: _focus.requestFocus,
  );

  Widget _list() => Consumer(
    builder: (context, ref, _) {
      ref.watch(
        _provider.select(
          (state) => (
            state.openRoot == null ? state.items : state.replyItems,
            state.openRoot,
            state.openRoot == null ? state.sort : null,
            state.openRoot == null ? state.loading : state.replyLoading,
            state.openRoot == null ? state.hasMore : state.replyHasMore,
            state.message,
            state.openRoot == null ? state.totalCount : null,
          ),
        ),
      );
      final state = ref.read(_provider);
      final root = state.openRoot;
      final comments = root == null ? state.items : state.replyItems;
      final loading = root == null ? state.loading : state.replyLoading;
      final more = root == null ? state.hasMore : state.replyHasMore;
      final prefix = root == null ? 0 : 2;
      if (!identical(_indexedComments, comments)) {
        _indexedComments = comments;
        _commentIndices = {
          for (var index = 0; index < comments.length; index++)
            comments[index].id: index,
        };
      }
      return ListView.builder(
        controller: root == null ? _topScroll : _replyScroll,
        key: PageStorageKey(
          'comments:${widget.target.type.name}:${widget.target.oid}:${root?.id ?? state.sort.name}',
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        itemCount: prefix + comments.length + 1,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<(String, String)>) return null;
          if (key.value.$1 == 'comment-root') {
            return root?.id == key.value.$2 ? 0 : null;
          }
          final index = _commentIndices[key.value.$2];
          return index == null ? null : prefix + index;
        },
        itemBuilder: (context, index) {
          if (root != null && index < prefix) {
            return index == 0
                ? _entry(root, preview: false, root: true)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '全部回复 ${root.replyCount}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  );
          }
          final commentIndex = index - prefix;
          if (commentIndex < comments.length) {
            return _entry(comments[commentIndex], preview: root == null);
          }
          if (loading) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (comments.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(
                    state.message != null
                        ? '暂时无法加载评论'
                        : (root?.replyCount ?? state.totalCount ?? 0) > 0 ||
                              (root == null && (widget.replyCount ?? 0) > 0)
                        ? '当前会话未返回可展示的评论'
                        : '还没有评论，来聊聊吧',
                  ),
                  if (more) _loadMore(root),
                ],
              ),
            );
          }
          if (more) return _loadMore(root);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                comments.length >= 500 ? '已显示 500 条评论' : '没有更多了',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        },
      );
    },
  );

  Widget _loadMore(CommentEntry? root) => Consumer(
    builder: (context, ref, _) {
      final busy = ref.watch(_provider.select((state) => state.busy));
      final state = ref.read(_provider);
      final controller = ref.read(_provider.notifier);
      return Center(
        child: TextButton(
          onPressed: busy
              ? null
              : () =>
                    root == null ? controller.load() : controller.loadReplies(),
          child: Text(state.message == null ? '加载更多' : '重试加载'),
        ),
      );
    },
  );
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

class _CommentTile extends ConsumerStatefulWidget {
  const _CommentTile({
    super.key,
    required this.provider,
    required this.comment,
    required this.onLogin,
    required this.onReplyFocus,
    this.preview = true,
    this.onOpenUser,
    required this.onOpenLink,
    this.onSeek,
  });
  final NotifierProvider<CommentsController, CommentsState> provider;
  final CommentEntry comment;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri> onOpenLink;
  final ValueChanged<Duration>? onSeek;
  final bool preview;
  final VoidCallback onLogin, onReplyFocus;

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile> {
  Widget? _content;

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider ||
        !identical(oldWidget.comment, widget.comment) ||
        oldWidget.preview != widget.preview ||
        oldWidget.onOpenUser != widget.onOpenUser ||
        oldWidget.onOpenLink != widget.onOpenLink ||
        oldWidget.onSeek != widget.onSeek) {
      _content = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content = null;
  }

  bool _busy(WidgetRef ref) => ref.watch(
    widget.provider.select(
      (state) =>
          state.busy ||
          state.loading ||
          state.replyLoading ||
          state.uncertain.contains('like:${widget.comment.id}'),
    ),
  );

  void _like() {
    if (ref.read(widget.provider).signedIn) {
      unawaited(ref.read(widget.provider.notifier).toggleLike(widget.comment));
    } else {
      widget.onLogin();
    }
  }

  void _reply() {
    if (!ref.read(widget.provider).signedIn) {
      widget.onLogin();
      return;
    }
    ref.read(widget.provider.notifier).target(widget.comment);
    widget.onReplyFocus();
  }

  void _open() =>
      unawaited(ref.read(widget.provider.notifier).openReplies(widget.comment));

  @override
  Widget build(BuildContext context) => _content ??= _buildContent(context);

  // Only mounted rows retain content. Busy/loading changes rebuild controls,
  // while pagination can reuse the rich text, images and author header.
  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context), c = widget.comment;
    final onOpenUser = widget.onOpenUser;
    final onOpenLink = widget.onOpenLink;
    final onSeek = widget.onSeek;
    final styles = CommentTextStyles(theme);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: c.authorId?.isValid == true && onOpenUser != null
                ? () => onOpenUser(c.authorId!)
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
                if (c.visibility == CommentVisibility.restricted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('暂未公开', style: styles.metadata),
                  ),
                Consumer(
                  builder: (context, ref, _) {
                    final busy = _busy(ref);
                    return Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : _like,
                          iconSize: 16,
                          color: c.liked
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          icon: Icon(
                            BiliIcons.like,
                            semanticLabel: c.liked ? '取消点赞评论' : '点赞评论',
                          ),
                        ),
                        Text('${c.likeCount}', style: styles.action),
                        const SizedBox(width: 12),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : _reply,
                          iconSize: 17,
                          color: theme.colorScheme.outline,
                          icon: const Icon(
                            BiliIcons.reply,
                            semanticLabel: '回复评论',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (widget.preview &&
                    (c.replyCount > 0 || c.replies.isNotEmpty))
                  Consumer(
                    builder: (context, ref, child) => InkWell(
                      onTap: _busy(ref) ? null : _open,
                      borderRadius: BorderRadius.circular(5),
                      child: child,
                    ),
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
                                            ? () => onOpenUser(r.authorId!)
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
                                      if (r.visibility ==
                                          CommentVisibility.restricted)
                                        Text('暂未公开', style: styles.metadata),
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
