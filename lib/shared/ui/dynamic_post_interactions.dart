import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_dialog.dart';
import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';
import 'app_notice.dart';
import 'dynamic_post_card.dart';
import 'comments_panel.dart';
import 'dynamic_detail_layout.dart';
import '../../features/dynamic/application/dynamic_actions_controller.dart';
import '../../features/dynamic/application/dynamic_content_state.dart';
import '../../features/dynamic/application/dynamic_management_controller.dart';
import '../../features/dynamic/domain/dynamic_link.dart';
import 'dynamic_post_menu.dart';
import 'dynamic_poll_dialog.dart';
import 'dynamic_content_card.dart';
import 'dynamic_reservation_card.dart';

class InteractiveDynamicPostCard extends ConsumerWidget {
  const InteractiveDynamicPostCard({
    super.key,
    required this.post,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
    this.expansionState,
    this.inDetail = false,
  });
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;
  final DynamicPostExpansionState? expansionState;
  final bool inDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = dynamicActionsProvider(post.id);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(dynamicContentProvider);
    final management = ref.watch(dynamicManagementProvider(post.id));
    final current = content.posts[post.id] ?? state.detail ?? post;
    if (content.hidden(current)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          content.removed.contains(current.id) ? '动态已删除' : '该UP主已临时屏蔽',
        ),
      );
    }
    void share() {
      final container = ProviderScope.containerOf(context);
      unawaited(
        showAppDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => UncontrolledProviderScope(
            container: container,
            child: _ShareDialog(post: current, onLogin: onLogin),
          ),
        ),
      );
    }

    void login() =>
        onLogin != null ? onLogin!() : showAppNotice(context, '请先登录后操作');
    void link(Uri url) {
      final poll = dynamicPollId(url);
      if (poll != null) {
        unawaited(
          showDynamicPollDialog(
            context,
            poll,
            dynamicId:
                url.queryParameters['dynamic_id'] ??
                _pollDynamicId(current, poll),
            onLogin: login,
            onOpenUser: onOpenUser,
          ),
        );
      } else {
        onOpenLink?.call(url);
      }
    }

    void message() {
      if (!context.mounted) return;
      final message = ref.read(provider).message;
      if (message != null) showAppNotice(context, message);
    }

    Future<void> details({bool focusComments = false}) async {
      var value = current;
      if (value.commentTarget == null &&
          !value.commentForbidden &&
          !value.unavailable) {
        final refreshed = await controller.refresh();
        if (!context.mounted) return;
        if (!refreshed) message();
        value = ref.read(provider).detail ?? current;
      }
      if (!context.mounted) return;
      final container = ProviderScope.containerOf(context);
      await showAppDialog<void>(
        context: context,
        builder: (context) => UncontrolledProviderScope(
          container: container,
          child: _DynamicDetailDialog(
            post: value,
            focusComments: focusComments,
            onOpenUser: onOpenUser,
            onOpenVideo: onOpenVideo,
            onOpenLink: onOpenLink,
            onLogin: onLogin,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DynamicPostCard(
          post: current,
          contentCardBuilder: (owner, card) => card.reservation == null
              ? DynamicContentCardView(card: card, onOpenLink: link)
              : DynamicReservationCard(
                  post: owner,
                  card: card,
                  onOpenLink: link,
                  onLogin: login,
                ),
          inDetail: inDetail,
          expansionState: expansionState,
          onOpenUser: onOpenUser,
          onOpenVideo: onOpenVideo,
          onOpenLink: link,
          liked: state.liked,
          likeCount: state.likeCount,
          repostCount: state.repostCount,
          busy: state.busy || management.busy,
          onMore: () => showDynamicPostMenu(
            context,
            current,
            onShare: share,
            onOpenLink: onOpenLink,
            onLogin: onLogin,
          ),
          onOpenDetail: inDetail ? null : () => unawaited(details()),
          onShare: share,
          onComment: inDetail || current.unavailable || current.commentForbidden
              ? null
              : () => unawaited(details(focusComments: true)),
          onLike:
              current.unavailable ||
                  current.likeForbidden ||
                  state.likeUncertain
              ? null
              : () async {
                  if (!state.signedIn) {
                    login();
                    return;
                  }
                  await controller.toggleLike(current);
                  message();
                },
        ),
        if (state.likeUncertain)
          TextButton.icon(
            onPressed: state.busy
                ? null
                : () async {
                    await controller.refresh();
                    message();
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('点赞结果未确认，刷新状态'),
          ),
      ],
    );
  }
}

String? _pollDynamicId(DynamicPost post, String pollId) {
  if (post.contentCards.any(
        (card) => card.url != null && dynamicPollId(card.url!) == pollId,
      ) ||
      post.spans.any(
        (span) =>
            span.linkUrl != null && dynamicPollId(span.linkUrl!) == pollId,
      )) {
    return post.id;
  }
  final original = post.original;
  return original == null ? null : _pollDynamicId(original, pollId);
}

class _DynamicDetailDialog extends ConsumerStatefulWidget {
  const _DynamicDetailDialog({
    required this.post,
    required this.focusComments,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
  });
  final DynamicPost post;
  final bool focusComments;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;

  @override
  ConsumerState<_DynamicDetailDialog> createState() =>
      _DynamicDetailDialogState();
}

class _DynamicDetailDialogState extends ConsumerState<_DynamicDetailDialog> {
  final _expansion = DynamicPostExpansionState();

  @override
  void initState() {
    super.initState();
    _expansion.setExpanded(widget.post.id, true);
  }

  @override
  Widget build(BuildContext context) {
    final post =
        ref.watch(dynamicActionsProvider(widget.post.id)).detail ?? widget.post;
    final target = post.commentTarget;
    final onUser = widget.onOpenUser == null
        ? null
        : (UserId id) {
            Navigator.pop(context);
            widget.onOpenUser!(id);
          };
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280, maxHeight: 1000),
        child: SizedBox(
          width: 1280,
          child: Column(
            children: [
              const _DialogHeader(title: '动态详情'),
              const Divider(height: 1),
              Expanded(
                child: DynamicDetailLayout(
                  focusComments: widget.focusComments,
                  content: InteractiveDynamicPostCard(
                    post: post,
                    inDetail: true,
                    expansionState: _expansion,
                    onOpenUser: onUser,
                    onOpenVideo: widget.onOpenVideo == null
                        ? null
                        : (video) {
                            Navigator.pop(context);
                            widget.onOpenVideo!(video);
                          },
                    onOpenLink: widget.onOpenLink == null
                        ? null
                        : (url) {
                            Navigator.pop(context);
                            widget.onOpenLink!(url);
                          },
                    onLogin: widget.onLogin,
                  ),
                  comments:
                      target == null ||
                          post.commentForbidden ||
                          post.unavailable
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              post.commentForbidden
                                  ? '该动态已关闭评论'
                                  : '该动态暂不支持评论，请在官方页面查看',
                            ),
                          ),
                        )
                      : CommentsPanel(
                          target: target,
                          replyCount: post.commentCount,
                          onOpenUser: onUser,
                          onLogin: widget.onLogin,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, this.busy = false});
  final String title;
  final bool busy;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _ShareDialog extends ConsumerStatefulWidget {
  const _ShareDialog({required this.post, this.onLogin});
  final DynamicPost post;
  final VoidCallback? onLogin;
  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = dynamicActionsProvider(widget.post.id);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    // Account changes invalidate both pending writes and the visible draft.
    ref.listen(
      provider.select((value) => (value.accountScope, value.sessionEpoch)),
      (_, _) => _text.clear(),
    );
    final url = Uri.https('t.bilibili.com', '/${widget.post.id}').toString();
    return PopScope(
      canPop: !state.busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DialogHeader(title: '分享动态', busy: state.busy),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (context.mounted) showAppNotice(context, '动态链接已复制');
                      } on PlatformException {
                        if (context.mounted) {
                          showAppNotice(context, '复制失败，请稍后重试');
                        }
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('复制动态链接'),
                  ),
                  const Divider(),
                  TextField(
                    controller: _text,
                    enabled:
                        !state.busy &&
                        state.signedIn &&
                        !widget.post.unavailable &&
                        !widget.post.repostForbidden,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '说说转发的理由（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (state.message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(state.message!),
                    ),
                  if (state.repostUncertain)
                    TextButton(
                      onPressed: controller.acknowledgeRepost,
                      child: const Text('我已核对结果，允许再次转发'),
                    ),
                  FilledButton(
                    onPressed:
                        state.busy ||
                            state.repostUncertain ||
                            widget.post.unavailable ||
                            widget.post.repostForbidden
                        ? null
                        : () async {
                            if (!state.signedIn) {
                              if (widget.onLogin != null) {
                                Navigator.pop(context);
                                widget.onLogin!();
                              } else {
                                showAppNotice(context, '请先登录后操作');
                              }
                              return;
                            }
                            if (await controller.repost(
                                  widget.post,
                                  _text.text,
                                ) &&
                                context.mounted) {
                              Navigator.pop(context);
                              showAppNotice(context, '动态已转发');
                            }
                          },
                    child: Text(
                      state.busy
                          ? '正在转发…'
                          : widget.post.repostForbidden
                          ? '该动态禁止转发'
                          : state.signedIn
                          ? '转发动态'
                          : '登录后转发',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
