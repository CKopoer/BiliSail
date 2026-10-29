import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/scroll_collapsing_header.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../application/account_overview_controller.dart';
import '../application/auth_controller.dart';
import '../domain/account_overview.dart';
import '../domain/auth_repository.dart';

enum AccountContentTab {
  history,
  watchLater,
  favorites,
  downloads;

  String get label => switch (this) {
    history => '历史记录',
    watchLater => '稍后再看',
    favorites => '我的收藏',
    downloads => '下载',
  };
}

typedef AccountContentBuilder = Widget Function(
  BuildContext context,
  AccountContentTab tab,
);

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({
    super.key,
    required this.onLogin,
    required this.contentBuilder,
    this.onNavigate,
    this.initialTab,
    this.onTabChanged,
  });

  final VoidCallback onLogin;
  final AccountContentBuilder contentBuilder;
  final ValueChanged<String>? onNavigate;
  final AccountContentTab? initialTab;
  final ValueChanged<AccountContentTab>? onTabChanged;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late AccountContentTab _selected =
      widget.initialTab ?? AccountContentTab.history;
  late final _progress = TabPagingProgress(_selected.index.toDouble());

  @override
  void didUpdateWidget(AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab case final tab? when tab != oldWidget.initialTab) {
      _selected = tab;
    }
  }

  void _select(AccountContentTab tab) {
    if (_selected == tab) return;
    setState(() => _selected = tab);
    widget.onTabChanged?.call(tab);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final overview = ref.watch(accountOverviewProvider);
    final id = auth.isSignedIn ? UserId.tryParse(auth.mid) : null;
    final theme = Theme.of(context);
    return SafeArea(
      child: ScrollHeaderRegion(
        enabled: ScrollHeaderRegion.isEnabled(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScrollCollapsingHeader(
              key: const ValueKey('account-collapsing-profile'),
              child: Material(
                color: theme.colorScheme.surface,
                child: _AccountProfileBar(
                  auth: auth,
                  overview: overview,
                  onLogin: widget.onLogin,
                  onLogout: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  onRetry: () => ref.invalidate(accountOverviewProvider),
                  onOpenProfile: id == null || widget.onNavigate == null
                      ? null
                      : () => widget.onNavigate?.call('/user/${id.value}'),
                  onOpenSection: id == null || widget.onNavigate == null
                      ? null
                      : (section) => widget.onNavigate?.call(
                          '/user/${id.value}?section=$section',
                        ),
                ),
              ),
            ),
            Material(
              color: theme.colorScheme.surface,
              child: ScrollConfiguration(
                behavior: const SmoothScrollBehavior(
                  horizontalMouseWheel: true,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('account-tab-strip'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: PagingTabStrip<AccountContentTab>(
                    tabs: AccountContentTab.values,
                    value: _selected,
                    onSelected: _select,
                    progress: _progress,
                    itemKey: (tab) => ValueKey('account-tab-${tab.name}'),
                    labelBuilder: (context, tab) => Text(tab.label),
                    spacing: 0,
                    fullWidthIndicator: true,
                    unselectedColor: theme.colorScheme.onSurfaceVariant,
                    buttonStyle: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: RetainedTabView<AccountContentTab>(
                tabs: AccountContentTab.values,
                value: _selected,
                onChanged: _select,
                progress: _progress,
                viewKey: const ValueKey('account-content-pages'),
                pageBuilder: (context, tab, active) => _AccountTabContent(
                  key: ValueKey('account-content-${tab.name}'),
                  tab: tab,
                  active: active,
                  builder: widget.contentBuilder,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}

class _AccountProfileBar extends StatelessWidget {
  const _AccountProfileBar({
    required this.auth,
    required this.overview,
    required this.onLogin,
    required this.onLogout,
    required this.onRetry,
    required this.onOpenProfile,
    required this.onOpenSection,
  });

  final AuthState auth;
  final AsyncValue<AccountOverview?> overview;
  final VoidCallback onLogin, onLogout, onRetry;
  final VoidCallback? onOpenProfile;
  final ValueChanged<String>? onOpenSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = auth.isSignedIn;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    // AsyncLoading/AsyncError may carry a previous account's value.
    final data = overview.asData?.value;
    final retry = signedIn && overview.hasError
        ? IconButton(
            onPressed: onRetry,
            tooltip: overview.error is AppFailure
                ? '${(overview.error as AppFailure).message}，重试账号资料'
                : '账号资料加载失败，重试账号资料',
            icon: const Icon(Icons.refresh, size: 18),
          )
        : null;
    final statistics = [
      _AccountStatistic(
        label: '关注',
        value: data?.following,
        inline: largeText,
        onTap: onOpenSection == null
            ? null
            : () => onOpenSection?.call('following'),
      ),
      _AccountStatistic(
        label: '粉丝',
        value: data?.followers,
        inline: largeText,
        onTap: onOpenSection == null
            ? null
            : () => onOpenSection?.call('followers'),
      ),
      _AccountStatistic(
        label: '动态',
        value: data?.dynamics,
        inline: largeText,
        onTap: onOpenSection == null
            ? null
            : () => onOpenSection?.call('dynamics'),
      ),
    ];
    TableRow balanceRow(String prefix, num? value, {double topPadding = 0}) =>
        TableRow(
          children: [
            Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: Text(
                prefix,
                semanticsLabel: '$prefix币',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: ExcludeSemantics(
                child: Text('币', style: theme.textTheme.bodySmall),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(start: 4, top: topPadding),
              child: Text('${value ?? '—'}', style: theme.textTheme.bodySmall),
            ),
          ],
        );
    final balances = ConstrainedBox(
      key: const ValueKey('account-balances'),
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              balanceRow('硬', data?.coins),
              balanceRow('B', data?.bCoins, topPadding: 2),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880 && !largeText;
        final compact = constraints.maxWidth < 360 && !largeText;
        final actionInFooter = signedIn && largeText;
        final accountAction = TextButton(
          onPressed: signedIn
              ? onLogout
              : auth.isBusy
              ? null
              : onLogin,
          style: compact
              ? TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  textStyle: theme.textTheme.bodySmall,
                )
              : null,
          child: Text(signedIn ? '退出登录' : '登录账号'),
        );
        final identity = _AccountIdentity(
          auth: auth,
          data: data,
          onOpenProfile: onOpenProfile,
          compact: compact,
        );
        return Padding(
          key: const ValueKey('account-profile-summary'),
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            12,
            compact ? 8 : 12,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: identity),
                  if (wide && signedIn) ...[
                    const SizedBox(width: 20),
                    balances,
                    const SizedBox(width: 12),
                    ...statistics,
                  ],
                  if (!actionInFooter) ...[
                    ?retry,
                    const SizedBox(width: 8),
                    accountAction,
                  ],
                ],
              ),
              if (signedIn && !wide) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    balances,
                    ...statistics,
                    if (actionInFooter) ...[?retry, accountAction],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({
    required this.auth,
    required this.data,
    required this.onOpenProfile,
    required this.compact,
  });

  final AuthState auth;
  final AccountOverview? data;
  final VoidCallback? onOpenProfile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = auth.isSignedIn;
    final level = data?.level;
    final progress = data?.progress;
    return Semantics(
      button: onOpenProfile != null,
      child: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              NetworkAvatar(
                url: signedIn ? auth.avatarUrl : null,
                name: signedIn ? auth.userName ?? '' : '',
                radius: compact ? 16 : 20,
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: signedIn ? auth.userName ?? '我的账号' : '未登录',
                      child: Text(
                        signedIn ? auth.userName ?? '我的账号' : '未登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (signedIn) ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          Text(
                            '等级 ${level ?? '—'}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            level != null && level >= 6
                                ? '已满级 · ${data?.currentExperience ?? '—'}'
                                : '经验 ${data?.currentExperience ?? '—'} / ${data?.nextExperience ?? '—'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: progress != null
                              ? LinearProgressIndicator(
                                  key: const ValueKey(
                                    'account-experience-progress',
                                  ),
                                  value: progress,
                                  minHeight: 2,
                                  borderRadius: BorderRadius.circular(2),
                                  semanticsLabel: '经验进度',
                                )
                              : Semantics(
                                  label: '经验进度未知',
                                  child: SizedBox(
                                    key: const ValueKey(
                                      'account-experience-progress-unknown',
                                    ),
                                    height: 2,
                                    width: double.infinity,
                                    child: ColoredBox(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ] else
                      Text('登录后同步观看内容', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountStatistic extends StatelessWidget {
  const _AccountStatistic({
    required this.label,
    required this.value,
    required this.onTap,
    this.inline = false,
  });

  final String label;
  final int? value;
  final VoidCallback? onTap;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      key: ValueKey('account-statistic-$label'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: inline ? 6 : 8, vertical: 4),
      ),
      child: inline
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text('${value ?? '—'}', style: theme.textTheme.bodyMedium),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${value ?? '—'}', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
    );
  }
}

/// Keep each visited list's primary controller and PageStorage independent.
class _AccountTabContent extends StatefulWidget {
  const _AccountTabContent({
    super.key,
    required this.tab,
    required this.active,
    required this.builder,
  });

  final AccountContentTab tab;
  final bool active;
  final AccountContentBuilder builder;

  @override
  State<_AccountTabContent> createState() => _AccountTabContentState();
}

class _AccountTabContentState extends State<_AccountTabContent> {
  final _scrollController = ScrollController();
  final _storage = PageStorageBucket();
  late Widget _content = _buildContent();

  Widget _buildContent() =>
      Builder(builder: (context) => widget.builder(context, widget.tab));

  @override
  void didUpdateWidget(_AccountTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.builder != widget.builder || oldWidget.tab != widget.tab) {
      _content = _buildContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active && WorkspaceActivity.isActive(context);
    return TickerMode(
      enabled: active,
      child: ExcludeFocus(
        excluding: !active,
        child: IgnorePointer(
          ignoring: !active,
          child: PrimaryScrollController(
            controller: _scrollController,
            automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
            child: PageStorage(bucket: _storage, child: _content),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
