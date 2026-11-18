import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/content_link_scope.dart';
import '../../../shared/ui/dynamic_post_interactions.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/state_view.dart';
import '../application/dynamic_detail_provider.dart';

class DynamicDetailScreen extends ConsumerWidget {
  const DynamicDetailScreen({
    super.key,
    required this.id,
    required this.byResourceId,
    required this.onOpenUser,
    required this.onOpenVideo,
    required this.onOpenLink,
    required this.onLogin,
  });

  final String id;
  final bool byResourceId;
  final ValueChanged<UserId> onOpenUser;
  final ValueChanged<VideoSummary> onOpenVideo;
  final ValueChanged<Uri> onOpenLink;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = dynamicDetailProvider((
      id: id,
      byResourceId: byResourceId,
    ));
    final state = RegExp(r'^[1-9][0-9]{0,127}$').hasMatch(id)
        ? ref.watch(provider)
        : null;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('dynamic-detail-back'),
              tooltip: '返回',
              onPressed:
                  PlaybackNavigation.maybeOf(context)?.onBack ??
                  () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Text('动态详情', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: state == null
              ? const StateView.empty(message: '动态地址无效')
              : state.when(
                  skipLoadingOnRefresh: false,
                  data: (post) => DynamicDetailContent(
                    key: ValueKey(post.id),
                    post: post,
                    focusComments: ContentLinkScope.of(context).comment != null,
                    onOpenUser: onOpenUser,
                    onOpenVideo: onOpenVideo,
                    onOpenLink: onOpenLink,
                    onLogin: onLogin,
                  ),
                  loading: () => const StateView.loading(message: '正在加载动态…'),
                  error: (error, _) => StateView.error(
                    message: error is AppFailure
                        ? error.message
                        : '动态加载失败，请稍后再试',
                    onAction: () => ref.invalidate(provider),
                  ),
                ),
        ),
      ],
    );
  }
}
