import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/comment_target.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/comments_panel.dart';
import '../../auth/application/auth_controller.dart';
import '../../comments/application/comments_controller.dart';
import '../../comments/domain/comments_repository.dart';
import '../application/messages_controller.dart';
import '../domain/message_repository.dart';

Future<void> showMessageReply(
  BuildContext context,
  WidgetRef ref,
  InboxEntry entry, {
  ValueChanged<Uri>? onOpenTarget,
}) async {
  final reply = entry.replyContext;
  final type = CommentTargetType.values
      .where((type) => type.value == reply?.businessId)
      .firstOrNull;
  final idPattern = RegExp(r'^[1-9][0-9]{0,39}$');
  if (reply == null ||
      type == null ||
      !idPattern.hasMatch(reply.subjectId) ||
      !idPattern.hasMatch(reply.parentId) ||
      (reply.rootId != null && !idPattern.hasMatch(reply.rootId!))) {
    return;
  }
  final repository = ref.read(messageRepositoryProvider);
  final account = (repository.accountScope, repository.sessionEpoch);
  if (!account.$1.startsWith('user:')) return;
  final target = CommentTarget(reply.subjectId, type);
  final comment = CommentEntry(
    id: reply.parentId,
    rootId: reply.rootId ?? reply.parentId,
    author: reply.author,
    authorId: reply.userId,
    message: entry.text,
    avatarUrl: entry.avatarUrl,
    emotes: entry.emotes,
  );
  final parent = ProviderScope.containerOf(context, listen: false);
  await showAppDialog<void>(
    context: context,
    builder: (context) => UncontrolledProviderScope(
      container: parent,
      child: ProviderScope(
        overrides: [
          commentsProviderFor(target).overrideWith(
            () => CommentsController(
              target.oid,
              type: target.type,
              initialReply: comment,
              loadInitially: false,
            ),
          ),
        ],
        child: _MessageReplyDialog(
          entry: entry,
          target: target,
          account: account,
          onOpenTarget: onOpenTarget,
        ),
      ),
    ),
  );
}

class _MessageReplyDialog extends ConsumerWidget {
  const _MessageReplyDialog({
    required this.entry,
    required this.target,
    required this.account,
    this.onOpenTarget,
  });
  final InboxEntry entry;
  final CommentTarget target;
  final (String, int) account;
  final ValueChanged<Uri>? onOpenTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authControllerProvider, (_, _) {
      final repository = ref.read(messageRepositoryProvider);
      if ((repository.accountScope, repository.sessionEpoch) != account) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
      }
    });
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        64;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: availableHeight.clamp(180, 600),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '回复 @${entry.replyContext?.author ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭回复',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (entry.targetUrl case final targetUrl? when onOpenTarget != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenTarget?.call(targetUrl);
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('查看原视频或内容'),
                ),
              ),
            Flexible(
              child: CommentsPanel(
                target: target,
                composerOnly: true,
                onSent: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
