import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';
import 'app_notice.dart';
import 'dynamic_post_card.dart';
import 'comments_panel.dart';
import '../../features/dynamic/application/dynamic_actions_controller.dart';

class InteractiveDynamicPostCard extends ConsumerWidget {
  const InteractiveDynamicPostCard({
    super.key,
    required this.post,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
    this.expansionState,
  });
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;
  final DynamicPostExpansionState? expansionState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = dynamicActionsProvider(post.id);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final current = state.detail ?? post;
    void login() =>
        onLogin != null ? onLogin!() : showAppNotice(context, '请先登录后操作');
    void message() {
      if (!context.mounted) return;
      final message = ref.read(provider).message;
      if (message != null) showAppNotice(context, message);
    }

    Future<void> comments() async {
      var value = current;
      if (value.commentTarget == null) {
        if (!await controller.refresh() || !context.mounted) {
          message();
          return;
        }
        value = ref.read(provider).detail ?? current;
      }
      final target = value.commentTarget;
      if (!context.mounted) return;
      if (target == null || value.commentForbidden || value.unavailable) {
        showAppNotice(
          context,
          value.commentForbidden ? '该动态已关闭评论' : '该动态暂不支持评论，请在官方页面查看',
        );
        return;
      }
      final container = ProviderScope.containerOf(context);
      await showDialog<void>(
        context: context,
        builder: (context) => UncontrolledProviderScope(
          container: container,
          child: Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 800),
              child: SizedBox(
                width: 680,
                child: Column(
                  children: [
                    _DialogHeader(title: '动态评论'),
                    Expanded(
                      child: CommentsPanel(
                        target: target,
                        replyCount: value.commentCount,
                        onOpenUser: onOpenUser == null
                            ? null
                            : (id) {
                                Navigator.pop(context);
                                onOpenUser!(id);
                              },
                        onLogin: onLogin,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DynamicPostCard(
          post: current,
          expansionState: expansionState,
          onOpenUser: onOpenUser,
          onOpenVideo: onOpenVideo,
          onOpenLink: onOpenLink,
          liked: state.liked,
          likeCount: state.likeCount,
          repostCount: state.repostCount,
          busy: state.busy,
          onShare: () {
            final container = ProviderScope.containerOf(context);
            unawaited(
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => UncontrolledProviderScope(
                  container: container,
                  child: _ShareDialog(post: current, onLogin: onLogin),
                ),
              ),
            );
          },
          onComment: current.unavailable || current.commentForbidden
              ? null
              : () => unawaited(comments()),
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
