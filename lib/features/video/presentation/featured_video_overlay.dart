import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/user_follow_button.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/workspace_link.dart';
import '../application/video_author_controller.dart';
import '../domain/video_author_repository.dart';
import 'video_actions_bar.dart';

class FeaturedVideoOverlay extends StatelessWidget {
  const FeaturedVideoOverlay({
    super.key,
    required this.detail,
    required this.controlsInset,
    required this.onLogin,
    required this.onOpenUser,
    required this.onShowDescription,
    required this.onShowComments,
  });

  final VideoDetail detail;
  final ValueListenable<double> controlsInset;
  final VoidCallback onLogin, onShowDescription, onShowComments;
  final ValueChanged<UserId> onOpenUser;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controlsInset,
    builder: (context, inset, _) => LayoutBuilder(
      builder: (context, bounds) {
        const margin = 12.0;
        final bottom = (inset + 8).clamp(margin, double.infinity);
        final actionHeight = FeaturedVideoActions.actionHeight(context);
        final horizontal =
            bounds.maxHeight - bottom <
                FeaturedVideoActions.verticalHeight(context) &&
            bounds.maxWidth >=
                FeaturedVideoActions.horizontalWidth + 2 * margin;
        return Stack(
          children: [
            Positioned(
              left: margin,
              right: horizontal
                  ? margin
                  : FeaturedVideoActions.width + 2 * margin,
              bottom: horizontal ? bottom + actionHeight + 8 : bottom,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _FeaturedVideoIdentity(
                    detail: detail,
                    onLogin: onLogin,
                    onOpenUser: onOpenUser,
                    onShowDescription: onShowDescription,
                  ),
                ),
              ),
            ),
            Positioned(
              right: margin,
              bottom: bottom,
              child: VideoActionsScope(
                detail: detail,
                onLogin: onLogin,
                child: FeaturedVideoActions(
                  onShowComments: onShowComments,
                  horizontal: horizontal,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _FeaturedVideoIdentity extends ConsumerWidget {
  const _FeaturedVideoIdentity({
    required this.detail,
    required this.onLogin,
    required this.onOpenUser,
    required this.onShowDescription,
  });

  final VideoDetail detail;
  final VoidCallback onLogin, onShowDescription;
  final ValueChanged<UserId> onOpenUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = detail.summary;
    final id = UserId.tryParse(detail.authorMid) ?? summary.authorId;
    final canOpenAuthor = id != null && id.isValid;
    final author = canOpenAuthor
        ? ref.watch(
            videoAuthorControllerProvider(VideoAuthorId(id.value))
                .select((state) => state.author),
          )
        : null;
    final stats = [
      if (author?.followerCount case final count?) '${compactCount(count)}粉丝',
      if (author?.likeCount case final count?) '${compactCount(count)}获赞',
    ];
    final openUser = canOpenAuthor ? () => onOpenUser(id) : null;
    final middleClick = WorkspaceLinkScope.middleClick(context, openUser);
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final iconOnly =
                bounds.maxWidth < 190 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: openUser,
                      onTertiaryTapUp: middleClick,
                      customBorder: const CircleBorder(),
                      child: NetworkAvatar(
                        url: summary.authorAvatarUrl,
                        name: summary.author,
                        radius: 19,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: InkWell(
                                  onTap: openUser,
                                  onTertiaryTapUp: middleClick,
                                  child: Text(
                                    summary.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (canOpenAuthor)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: UserFollowButton(
                                    id: id,
                                    onLogin: onLogin,
                                    compact: true,
                                    showMessage: false,
                                    iconOnly: iconOnly,
                                  ),
                                ),
                            ],
                          ),
                          if (stats.isNotEmpty)
                            Text(
                              stats.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: onShowDescription,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          summary.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        semanticLabel: '展开视频信息',
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
