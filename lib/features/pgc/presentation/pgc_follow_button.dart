import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_notice.dart';
import '../application/pgc_follow_controller.dart';
import '../domain/pgc_repository.dart';

final class PgcFollowButton extends ConsumerWidget {
  const PgcFollowButton({
    super.key,
    required this.seasonId,
    this.seasonType,
    this.onLogin,
  });

  final PgcSeasonId seasonId;
  final int? seasonType;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pgcFollowControllerProvider(seasonId);
    final state = ref.watch(provider);
    final colors = Theme.of(context).colorScheme;
    final drama = const {2, 3, 5, 7}.contains(seasonType);
    final action = drama ? '追剧' : '追番';
    final followed = state.followed == true;
    final needsRefresh = state.signedIn && state.followed == null;
    final pending = state.loading || state.busy;
    final label = pending
        ? state.busy
              ? '处理中'
              : '加载中'
        : needsRefresh
        ? '刷新状态'
        : followed
        ? '已$action'
        : action;
    final muted = followed || needsRefresh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: !state.signedIn
              ? '登录后$action'
              : needsRefresh
              ? '刷新$action状态'
              : followed
              ? '取消$action'
              : action,
          child: TextButton.icon(
            key: const ValueKey('pgc-follow-button'),
            style: TextButton.styleFrom(
              foregroundColor: muted ? colors.onSurfaceVariant : colors.primary,
              backgroundColor: muted
                  ? colors.surfaceContainerHigh
                  : colors.primaryContainer,
              minimumSize: const Size(88, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: pending
                ? null
                : () {
                    if (!state.signedIn) {
                      if (onLogin case final login?) {
                        login();
                      } else {
                        showAppNotice(context, '请先登录后再$action');
                      }
                      return;
                    }
                    final controller = ref.read(provider.notifier);
                    if (needsRefresh) {
                      controller.refresh();
                    } else {
                      controller.toggle();
                    }
                  },
            icon: pending
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : Icon(
                    needsRefresh
                        ? Icons.refresh
                        : followed
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 18,
                  ),
            label: Text(label),
          ),
        ),
        if (state.message case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }
}
