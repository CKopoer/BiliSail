import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../application/account_overview_controller.dart';
import '../application/auth_controller.dart';

class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key, this.onOpenUser, this.onNavigate});
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authControllerProvider.select((s) => (s.isSignedIn, s.mid)), (
      previous,
      next,
    ) {
      if (previous != next &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    });
    final auth = ref.watch(authControllerProvider);
    final overview = ref.watch(accountOverviewProvider);
    final data = overview.value;
    final unread = ref.watch(accountMessageIndicatorProvider);
    final count = unread.count;
    final id = UserId.tryParse(auth.mid);
    final theme = Theme.of(context);
    void go(String path, {bool profile = false}) {
      Navigator.pop(context);
      if (onNavigate != null) {
        onNavigate?.call(path);
      } else if (profile && id != null) {
        onOpenUser?.call(id);
      }
    }

    Widget item(
      String title,
      IconData icon,
      String path, {
      bool profile = false,
      Widget? trailing,
    }) => ListTile(
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: 20),
      title: Text(title),
      trailing: trailing,
      onTap: () => go(path, profile: profile),
    );
    Widget statistic(String label, int? value, String section) => Expanded(
      child: TextButton(
        onPressed: id == null
            ? null
            : () => go('/user/${id.value}?section=$section', profile: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: theme.colorScheme.onSurface)),
            Text(value?.toString() ?? '—', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
    return Drawer(
      width: math.min(360, math.max(0, MediaQuery.sizeOf(context).width - 32)),
      semanticLabel: '我的账号',
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('我的账号', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Column(
                          children: [
                            NetworkAvatar(
                              url: auth.avatarUrl,
                              name: auth.userName ?? '',
                              radius: 28,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              auth.userName ?? '我的账号',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (data?.vipLabel case final label?
                                when label.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text('等级 ${data?.level ?? '—'}'),
                                Text(
                                  data?.level != null && (data?.level ?? 0) >= 6
                                      ? '已满级 · ${data?.currentExperience ?? '—'}'
                                      : '${data?.currentExperience ?? '—'} / ${data?.nextExperience ?? '—'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value:
                                  data?.progress ??
                                  (overview.isLoading ? null : 0),
                              minHeight: 3,
                            ),
                            if (data?.coins case final coins?)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '硬币 $coins',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            if (overview.hasError)
                              TextButton(
                                onPressed: () =>
                                    ref.invalidate(accountOverviewProvider),
                                child: Text(
                                  overview.error is AppFailure
                                      ? (overview.error as AppFailure).message
                                      : '资料加载失败，点击重试',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          statistic('关注', data?.following, 'following'),
                          statistic('粉丝', data?.followers, 'followers'),
                          statistic('动态', data?.dynamics, 'dynamics'),
                        ],
                      ),
                      const Divider(height: 12),
                      if (id != null)
                        item(
                          '个人中心',
                          Icons.person_outline,
                          '/user/${id.value}',
                          profile: true,
                        ),
                      item(
                        '我的消息',
                        Icons.mail_outline,
                        '/messages',
                        trailing: count > 0
                            ? Badge(label: Text(count > 99 ? '99+' : '$count'))
                            : null,
                      ),
                      if (unread.failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextButton(
                            onPressed: unread.refresh,
                            child: const Text('未读数量获取失败，重试'),
                          ),
                        ),
                      item(
                        '稍后再看',
                        Icons.play_circle_outline,
                        '/?channel=watchLater',
                      ),
                      item('我的收藏', Icons.star_border, '/?channel=favorites'),
                      item('历史记录', Icons.history, '/history'),
                      item(
                        '直播中心',
                        Icons.flag_outlined,
                        '/?channel=live&section=我的关注',
                      ),
                      const Divider(height: 12),
                      ListTile(
                        minTileHeight: 48,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        leading: const Icon(Icons.logout, size: 20),
                        title: const Text('退出登录'),
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(authControllerProvider.notifier).signOut();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
