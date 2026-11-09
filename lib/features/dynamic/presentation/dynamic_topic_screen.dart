import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/dynamic_compose_dialog.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/content_section_tabs.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_composer_repository.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/sliver_dynamic_post_list.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_card.dart';
import '../application/dynamic_topic_controller.dart';

class DynamicTopicScreen extends ConsumerWidget {
  const DynamicTopicScreen({
    super.key,
    required this.id,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
  });
  final String id;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (id.length > 128 || !RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
      return const StateView.empty(message: '话题地址无效');
    }
    final state = ref.watch(dynamicTopicProvider(id));
    final controller = ref.read(dynamicTopicProvider(id).notifier);
    final detail = state.detail;
    final theme = Theme.of(context);
    final active = WorkspaceActivity.isActive(context);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isSignedIn),
    );
    void login() {
      if (onLogin != null) {
        onLogin!();
      } else {
        showAppNotice(context, '请先登录后操作');
      }
    }

    Future<void> report() async {
      if (!signedIn) {
        login();
        return;
      }
      final submitted = await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TopicReportDialog(
          onSubmit: controller.report,
          message: () => ref.read(dynamicTopicProvider(id)).actionMessage,
          uncertain: () => ref.read(dynamicTopicProvider(id)).reportUncertain,
        ),
      );
      if (submitted == true && context.mounted) showAppNotice(context, '举报已提交');
    }

    return Column(
      children: [
        Material(
          key: const ValueKey('topic-page-navigation'),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('topic-back'),
                  tooltip: '返回',
                  onPressed:
                      PlaybackNavigation.maybeOf(context)?.onBack ??
                      () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: InkWell(
                    onTap: detail?.creatorId == null || onOpenUser == null
                        ? null
                        : () => onOpenUser!(detail!.creatorId!),
                    child: Row(
                      children: [
                        NetworkAvatar(
                          url: detail?.creatorAvatar,
                          name: detail?.creatorName ?? '',
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detail?.creatorName.isNotEmpty == true
                                ? '${detail!.creatorName} 发起'
                                : '话题发起人',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新话题',
                  onPressed: state.loading || state.actionBusy
                      ? null
                      : controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
                PopupMenuButton<String>(
                  tooltip: '话题操作',
                  onSelected: (value) async {
                    if (value == 'report') {
                      await report();
                    } else if (!signedIn) {
                      login();
                    } else {
                      await controller.toggleFavorite();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'favorite',
                      enabled:
                          detail != null &&
                          !state.loading &&
                          !state.actionBusy &&
                          !state.favoriteUncertain,
                      child: Text(detail?.isFavorite == true ? '取消收藏' : '收藏'),
                    ),
                    PopupMenuItem(
                      value: 'report',
                      enabled:
                          !state.actionBusy &&
                          !state.reportUncertain &&
                          !state.reported,
                      child: Text(state.reported ? '已举报' : '举报'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PagedScrollViewport(
            key: ValueKey((id, state.sort)),
            keepScrollOffset: false,
            active: active,
            contentVersion: state,
            canLoadMore:
                state.hasMore &&
                !state.loading &&
                !state.foldLoading &&
                state.error == null,
            onLoadMore: controller.loadMore,
            builder: (scrollController) => RefreshIndicator(
              onRefresh: controller.refresh,
              child: CustomScrollView(
                key: PageStorageKey('dynamic-topic-$id'),
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                detail?.name ?? '话题',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (detail != null) ...[
                                if (detail.description.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SelectableText(detail.description),
                                ],
                                const SizedBox(height: 12),
                                Text(
                                  '${compactCount(detail.viewCount)}浏览 · ${compactCount(detail.discussCount)}讨论',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                              if (state.actionMessage case final message?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  PinnedHeaderSliver(
                    key: const ValueKey('topic-pinned-toolbar'),
                    child: Material(
                      color: theme.colorScheme.surface,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 804),
                          child: DynamicComposeToolbar(
                            topic: detail == null
                                ? null
                                : DynamicComposeTopic(id, detail.name),
                            label: '参与话题',
                            enabled: detail != null,
                            onLogin: onLogin,
                            onPublished: controller.refresh,
                            child: ContentSectionTabs<int>(
                              entries: [
                                for (final sort in state.sorts)
                                  (sort.id, sort.name),
                              ],
                              value: state.sort,
                              scrollKey: ValueKey('topic-sort-strip-$id'),
                              itemKey: (sort) => ValueKey('topic-sort-$sort'),
                              onSelected: controller.selectSort,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (state.posts.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverDynamicPostList(
                        posts: state.posts,
                        onOpenUser: onOpenUser,
                        onOpenVideo: onOpenVideo,
                        onOpenLink: onOpenLink,
                        onLogin: onLogin,
                      ),
                    ),
                  if (state.loading)
                    const SliverToBoxAdapter(child: StateView.loading())
                  else if (state.error != null)
                    SliverToBoxAdapter(
                      child: StateView.error(
                        message: state.error is AppFailure
                            ? (state.error! as AppFailure).message
                            : '话题加载失败，请重试',
                        onAction: controller.retry,
                      ),
                    )
                  else if (state.posts.isEmpty && state.foldDescription.isEmpty)
                    const SliverToBoxAdapter(
                      child: StateView.empty(message: '话题下暂时没有动态'),
                    ),
                  if (state.foldDescription.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              if (state.foldError != null)
                                const Text('折叠内容加载失败，请重试'),
                              OutlinedButton.icon(
                                onPressed: state.foldLoading || state.loading
                                    ? null
                                    : controller.loadFolded,
                                icon: state.foldLoading
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more),
                                label: Text(state.foldDescription),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (state.hasMore && !state.loading && state.error == null)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: controller.loadMore,
                          child: const Text('加载更多动态'),
                        ),
                      ),
                    ),
                  if (!state.hasMore &&
                      !state.loading &&
                      state.error == null &&
                      state.posts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          state.posts.length >=
                                  DynamicTopicController.maximumPosts
                              ? '已显示500条动态，可刷新查看'
                              : '没有更多动态了',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopicReportDialog extends StatefulWidget {
  const _TopicReportDialog({
    required this.onSubmit,
    required this.message,
    required this.uncertain,
  });
  final Future<bool> Function(String) onSubmit;
  final String? Function() message;
  final bool Function() uncertain;
  @override
  State<_TopicReportDialog> createState() => _TopicReportDialogState();
}

class _TopicReportDialogState extends State<_TopicReportDialog> {
  final _text = TextEditingController();
  String _reason = '话题引战';
  bool _busy = false, _uncertain = false;
  String? _message;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('举报话题'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '举报理由'),
                items: [
                  for (final label in ['话题引战', '违规话题', '色情', '广告', '其他问题'])
                    DropdownMenuItem(value: label, child: Text(label)),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => _reason = value);
                      },
              ),
              TextField(
                controller: _text,
                enabled: !_busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '补充说明（可选）'),
              ),
              if (_message != null)
                Text(
                  _message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _uncertain
              ? null
              : () async {
                  setState(() => _busy = true);
                  final reason = _text.text.trim().isEmpty
                      ? _reason
                      : '$_reason：${_text.text.trim()}';
                  final success = await widget.onSubmit(reason);
                  if (!context.mounted) return;
                  if (success) {
                    Navigator.pop(context, true);
                    return;
                  }
                  final message = widget.message() ?? '提交失败，请检查登录状态后重试';
                  setState(() {
                    _busy = false;
                    _message = message;
                    _uncertain = widget.uncertain();
                  });
                },
          child: Text(_busy ? '提交中…' : '提交举报'),
        ),
      ],
    ),
  );
}
