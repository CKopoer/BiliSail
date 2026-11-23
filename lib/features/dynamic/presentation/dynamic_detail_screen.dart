import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/content_detail_page.dart';
import '../../../shared/ui/content_link_scope.dart';
import '../../../shared/ui/dynamic_post_interactions.dart';
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
    Widget frame(Widget body) => ContentDetailPage(
      title: '动态详情',
      backButtonKey: const ValueKey('dynamic-detail-back'),
      body: body,
    );
    if (state == null) return frame(const StateView.empty(message: '动态地址无效'));
    return state.when(
      skipLoadingOnRefresh: false,
      data: (post) => DynamicDetailPage(
        key: ValueKey(post.id),
        post: post,
        focusComments: ContentLinkScope.of(context).comment != null,
        onOpenUser: onOpenUser,
        onOpenVideo: onOpenVideo,
        onOpenLink: onOpenLink,
        onLogin: onLogin,
      ),
      loading: () => frame(const StateView.loading(message: '正在加载动态…')),
      error: (error, _) => frame(
        StateView.error(
          message: error is AppFailure ? error.message : '动态加载失败，请稍后再试',
          onAction: () => ref.invalidate(provider),
        ),
      ),
    );
  }
}
