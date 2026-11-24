import 'package:material_ui/material_ui.dart';
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
    this.target,
    this.onOpenUser,
  });
  final VideoDetail detail;
  final CommentTarget? target;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aid = detail.aid;
    final resolved =
        target ??
        (aid == null || aid.isEmpty
            ? null
            : CommentTarget(aid, CommentTargetType.video));
    if (resolved == null) return const Center(child: Text('暂无评论信息'));
    return CommentsPanel(
      target: resolved,
      replyCount: detail.replyCount,
      onLogin: onLogin,
      onOpenUser: onOpenUser,
      playbackPosition: () {
        final session = ref.read(playbackSessionProvider);
        return session.media != null &&
                session.detail?.summary.id == detail.summary.id
            ? session.snapshots.value.position
            : null;
      },
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
