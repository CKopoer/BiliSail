import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/featured_paging_scope.dart';
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
    required this.controlsGeometry,
    required this.onLogin,
    required this.onOpenUser,
    required this.onShowDescription,
    required this.onShowComments,
  });

  final VideoDetail detail;
  final FeaturedControlsGeometry controlsGeometry;
  final VoidCallback onLogin, onShowDescription, onShowComments;
  final ValueChanged<UserId> onOpenUser;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controlsGeometry.height,
    child: _FeaturedVideoIdentity(
      detail: detail,
      onLogin: onLogin,
      onOpenUser: onOpenUser,
      onShowDescription: onShowDescription,
    ),
    builder: (context, height, identity) => LayoutBuilder(
      builder: (context, bounds) {
        const margin = _FeaturedOverlayPlacement.margin;
        final raisedBottom = (height + 4).clamp(margin, double.infinity);
        final horizontal =
            bounds.maxHeight - raisedBottom <
                FeaturedVideoActions.verticalHeight(context) &&
            bounds.maxWidth >=
                FeaturedVideoActions.horizontalWidth + 2 * margin;
        final actionsWidth = horizontal
            ? FeaturedVideoActions.horizontalWidth
            : FeaturedVideoActions.width;
        final stackAboveActions =
            horizontal && bounds.maxWidth - actionsWidth - 3 * margin < 190;
        return Flow(
          delegate: _FeaturedOverlayPlacement(
            opacity: controlsGeometry.opacity,
            lift: raisedBottom - margin,
            cardWidth:
                (bounds.maxWidth -
                        2 * margin -
                        (stackAboveActions ? 0 : actionsWidth + margin))
                    .clamp(0, 480),
            stackAboveActions: stackAboveActions,
          ),
          children: [
            identity!,
            VideoActionsScope(
              detail: detail,
              onLogin: onLogin,
              child: FeaturedVideoActions(
                onShowComments: onShowComments,
                horizontal: horizontal,
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Both children keep their layout and repaint boundaries throughout the fade.
class _FeaturedOverlayPlacement extends FlowDelegate {
  _FeaturedOverlayPlacement({
    required this.opacity,
    required this.lift,
    required this.cardWidth,
    required this.stackAboveActions,
  }) : super(repaint: opacity);

  static const margin = 12.0;
  final ValueListenable<double> opacity;
  final double lift, cardWidth;
  final bool stackAboveActions;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints(maxWidth: i == 0 ? cardWidth : constraints.maxWidth);

  @override
  void paintChildren(FlowPaintingContext context) {
    final card = context.getChildSize(0)!;
    final rail = context.getChildSize(1)!;
    final bottom = context.size.height - margin - lift * opacity.value;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(
        margin,
        bottom - card.height - (stackAboveActions ? rail.height + 4 : 0),
        0,
      ),
    );
    context.paintChild(
      1,
      transform: Matrix4.translationValues(
        context.size.width - margin - rail.width,
        bottom - rail.height,
        0,
      ),
    );
  }

  @override
  bool shouldRelayout(_FeaturedOverlayPlacement oldDelegate) =>
      cardWidth != oldDelegate.cardWidth;

  @override
  bool shouldRepaint(_FeaturedOverlayPlacement oldDelegate) =>
      opacity != oldDelegate.opacity ||
      lift != oldDelegate.lift ||
      stackAboveActions != oldDelegate.stackAboveActions;
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
    final theme = Theme.of(context);
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: NetworkAvatar(
                          url: summary.authorAvatarUrl,
                          name: summary.author,
                          radius: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (canOpenAuthor)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Theme(
                                    data: theme.copyWith(
                                      visualDensity: VisualDensity.compact,
                                      textTheme: theme.textTheme.copyWith(
                                        labelLarge: theme.textTheme.labelLarge
                                            ?.copyWith(fontSize: 12),
                                      ),
                                    ),
                                    child: UserFollowButton(
                                      id: id,
                                      onLogin: onLogin,
                                      compact: true,
                                      showMessage: false,
                                      iconOnly: iconOnly,
                                    ),
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
                                fontSize: 11,
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
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        semanticLabel: '展开视频信息',
                        size: 16,
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
