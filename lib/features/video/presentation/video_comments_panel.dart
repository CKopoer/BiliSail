import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/comment_target.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/comments_panel.dart';
import '../../playback/application/playback_session.dart';

class VideoCommentsPanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final aid = detail.aid;
    if (aid == null || aid.isEmpty) return const Center(child: Text('暂无评论信息'));
    return CommentsPanel(
      target: CommentTarget(aid, CommentTargetType.video),
      replyCount: detail.replyCount,
      onLogin: onLogin,
      onOpenUser: onOpenUser,
      onSeek: (position) async {
        final session = ref.read(playbackSessionProvider);
        final media = session.media;
        if (media == null || session.detail?.summary.id != detail.summary.id) {
          showAppNotice(context, '播放器尚未就绪');
          return;
        }
        await session.seek(
          media.duration > Duration.zero && position > media.duration
              ? media.duration
              : position,
        );
      },
    );
  }
}
