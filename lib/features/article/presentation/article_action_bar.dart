import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/article_address.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/dynamic_post_interactions.dart';
import '../../../shared/ui/video_card.dart' show compactCount;
import '../../auth/application/auth_controller.dart';
import '../../dynamic/application/dynamic_actions_controller.dart';
import '../application/article_provider.dart';
import '../domain/article_document.dart';

class ArticleActionBar extends ConsumerWidget {
  const ArticleActionBar({
    super.key,
    required this.document,
    required this.onLogin,
    this.onComments,
  });
  final ArticleDocument document;
  final VoidCallback onLogin;
  final VoidCallback? onComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cvId = document.statsCvId;
    final stats = cvId == null
        ? document.stats
        : ref.watch(articleInfoProvider(cvId)).asData?.value;
    final post = document.actionPost(stats);
    final actions = post == null
        ? null
        : ref.watch(dynamicActionsProvider(post.id));
    final address = ArticleAddress.fromWebUri(document.url);
    final favorite = address == null
        ? null
        : ref.watch(articleFavoriteProvider(address));
    final signedIn = ref.watch(
      authControllerProvider.select((auth) => auth.isSignedIn),
    );
    final liked = actions?.liked ?? stats?.liked;
    final saved = favorite?.favorite ?? stats?.favorited;
    final savedCount = favorite?.count ?? stats?.favorites;
    final colors = Theme.of(context).colorScheme;

    Widget button(
      String label,
      IconData icon,
      int? count,
      VoidCallback? tap, {
      bool selected = false,
    }) => Expanded(
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: selected,
          label: count == null ? label : '$label $count',
          child: TextButton(
            onPressed: tap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              foregroundColor: selected
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      count == null || count == 0 ? label : compactCount(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Row(
                children: [
                  button(
                    '转发',
                    Icons.shortcut,
                    actions?.repostCount ?? stats?.forwards,
                    post == null ||
                            post.repostForbidden ||
                            actions?.busy == true
                        ? null
                        : () => showDynamicShareDialog(
                            context,
                            post,
                            articleUrl: document.url,
                            onLogin: onLogin,
                          ),
                  ),
                  button(
                    saved == true ? '取消收藏' : '收藏',
                    saved == true ? Icons.star : Icons.star_border,
                    savedCount,
                    saved == null ||
                            address == null ||
                            favorite?.busy == true ||
                            favorite?.uncertain == true
                        ? null
                        : () async {
                            if (!signedIn) return onLogin();
                            final message = await ref
                                .read(articleFavoriteProvider(address).notifier)
                                .toggle(saved, savedCount);
                            if (context.mounted && message != null) {
                              showAppNotice(context, message);
                            }
                          },
                    selected: saved == true,
                  ),
                  button(
                    '评论',
                    Icons.chat_bubble_outline,
                    document.commentCount ?? stats?.comments,
                    onComments,
                  ),
                  button(
                    actions?.likeUncertain == true
                        ? '刷新点赞状态'
                        : liked == true
                        ? '取消点赞'
                        : '点赞',
                    liked == true ? Icons.thumb_up : Icons.thumb_up_outlined,
                    actions?.likeCount ?? stats?.likes,
                    post == null ||
                            liked == null ||
                            post.likeForbidden ||
                            actions?.busy == true
                        ? null
                        : () async {
                            if (!signedIn) return onLogin();
                            final provider = dynamicActionsProvider(post.id);
                            final controller = ref.read(provider.notifier);
                            if (actions?.likeUncertain == true) {
                              await controller.refresh();
                            } else {
                              await controller.toggleLike(post);
                            }
                            if (!context.mounted) return;
                            final message = ref.read(provider).message;
                            if (message != null) {
                              showAppNotice(context, message);
                            }
                          },
                    selected: liked == true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
