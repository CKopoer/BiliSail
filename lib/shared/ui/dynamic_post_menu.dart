import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/dynamic/application/dynamic_actions_controller.dart';
import '../../features/dynamic/application/dynamic_composer_controller.dart';
import '../../features/dynamic/application/dynamic_content_state.dart';
import '../../features/dynamic/application/dynamic_management_controller.dart';
import '../../features/dynamic/domain/dynamic_draft.dart' show DynamicMention;
import '../../features/image_viewer/application/image_viewer_controller.dart';
import '../../features/profile/application/profile_actions_controller.dart';
import '../../features/video/domain/video_card_interactions.dart';
import 'app_dialog.dart';
import 'app_notice.dart';
import 'dynamic_compose_editor.dart';
import 'dynamic_post_card.dart';
import 'dynamic_publish_forms.dart';
import 'video_card_interaction_scope.dart';
import 'video_card_menu_sheet.dart';

Future<void> showDynamicPostMenu(
  BuildContext context,
  DynamicPost post, {
  VoidCallback? onShare,
  ValueChanged<Uri>? onOpenLink,
  VoidCallback? onLogin,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => DynamicPostMenu(
    post: post,
    onShare: onShare,
    onOpenLink: onOpenLink,
    onLogin: onLogin,
  ),
);

class DynamicPostMenu extends ConsumerWidget {
  const DynamicPostMenu({
    super.key,
    required this.post,
    this.onShare,
    this.onOpenLink,
    this.onLogin,
  });
  final DynamicPost post;
  final VoidCallback? onShare, onLogin;
  final ValueChanged<Uri>? onOpenLink;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(dynamicContentProvider),
        current = overlay.posts[post.id] ?? post;
    final provider = dynamicManagementProvider(post.id),
        state = ref.watch(provider),
        controller = ref.read(provider.notifier);
    final auth = ref.watch(authControllerProvider),
        repo = ref.watch(dynamicRepositoryProvider);
    final menuScope = repo?.accountScope, menuEpoch = repo?.sessionEpoch;
    bool sameAccount() =>
        context.mounted &&
        repo?.accountScope == menuScope &&
        repo?.sessionEpoch == menuEpoch;
    final own = controller.owns(current),
        locks = overlay.locked[post.id] ?? const <String>{};
    void notice() {
      final m = ref.read(provider).message;
      if (context.mounted && m != null) showAppNotice(context, m);
    }

    Future<bool> confirm(String title, String text) async =>
        await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(text)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
        ) ==
        true;
    Future<void> run(
      Future<bool> Function() work,
      String success, {
      bool needsLogin = true,
    }) async {
      if (!sameAccount()) return;
      if (needsLogin && !auth.isSignedIn) {
        onLogin?.call();
        if (onLogin == null) showAppNotice(context, '请先登录后操作');
        return;
      }
      if (await work()) {
        if (context.mounted) showAppNotice(context, success);
      } else {
        notice();
      }
    }

    Widget item(
      String text,
      IconData icon,
      VoidCallback? tap, {
      String? action,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(text),
      enabled: !state.busy && (action == null || !locks.contains(action)),
      onTap: tap,
    );
    Future<void> copy(String value) async {
      try {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) showAppNotice(context, '已复制');
      } on PlatformException {
        if (context.mounted) showAppNotice(context, '复制失败，请重试');
      }
    }

    final video = current.video ?? current.original?.video;
    final toggle = VideoCardInteractionScope.maybeOf(context)?.interactions;
    return PopScope(
      canPop: !state.busy,
      child: DynamicFormDialog(
        title: '动态操作',
        canClose: !state.busy,
        body: ListView(
          children: [
            Text(
              current.authorName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            item('分享动态', Icons.share_outlined, () {
              Navigator.pop(context);
              onShare?.call();
            }),
            item(
              '复制动态链接',
              Icons.link,
              () => copy(
                Uri.https('t.bilibili.com', '/${current.id}').toString(),
              ),
            ),
            item(
              '复制动态正文',
              Icons.copy,
              () => copy(
                [
                  current.title,
                  current.text,
                ].where((s) => s.isNotEmpty).join('\n'),
              ),
            ),
            item('保存动态', Icons.save_alt, () async {
              await showAppDialog<void>(
                context: context,
                builder: (_) => DynamicPostSaveDialog(post: current),
              );
            }),
            if (video != null && toggle is VideoCardWatchLaterToggle)
              item('稍后再看', Icons.watch_later_outlined, () async {
                final result = await (toggle as VideoCardWatchLaterToggle)
                    .addWatchLater(video.id);
                if (context.mounted) {
                  final message = watchLaterResultMessage(result);
                  if (message != null) showAppNotice(context, message);
                }
              }),
            if (!current.unavailable &&
                current.authorId != null &&
                const {11, 12, 17}.contains(current.commentTarget?.type.value))
              item('分享至消息', Icons.forward_to_inbox, () async {
                if (!auth.isSignedIn) {
                  onLogin?.call();
                  if (onLogin == null) showAppNotice(context, '请先登录后操作');
                  return;
                }
                final scope = repo?.accountScope, epoch = repo?.sessionEpoch;
                final user = await showAppDialog<DynamicMention>(
                  context: context,
                  builder: (_) => const DynamicMentionPicker(),
                );
                if (user == null ||
                    !context.mounted ||
                    repo?.accountScope != scope ||
                    repo?.sessionEpoch != epoch) {
                  return;
                }
                if (await confirm('分享至消息', '发送这条动态给 ${user.name}？') &&
                    context.mounted &&
                    repo?.accountScope == scope &&
                    repo?.sessionEpoch == epoch) {
                  await run(
                    () => controller.shareMessage(current, UserId(user.id)),
                    '已发送至消息',
                  );
                }
              }),
            if (current.authorId != null && !own)
              item('临时屏蔽该UP主', Icons.visibility_off_outlined, () {
                ref
                    .read(dynamicContentProvider.notifier)
                    .hideAuthor(current.authorId!.value, current.authorName);
                Navigator.pop(context);
              }),
            if (overlay.hiddenAuthors.isNotEmpty)
              item(
                '管理临时屏蔽',
                Icons.manage_accounts_outlined,
                () => showTemporaryDynamicBlocks(context),
              ),
            if (own) ...[
              const Divider(),
              item(
                current.pinned ? '取消置顶' : '置顶动态',
                Icons.vertical_align_top,
                () => run(() => controller.pin(current), '置顶设置已更新'),
                action: 'pin',
              ),
              item('可见范围', Icons.visibility_outlined, () async {
                final value = await showAppDialog<bool>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: const Text('可见范围'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('所有人可见'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('仅自己可见'),
                      ),
                    ],
                  ),
                );
                if (value != null && sameAccount()) {
                  await run(
                    () => controller.visibility(current, value),
                    '可见范围已更新',
                  );
                }
              }, action: 'visibility'),
              if (current.commentTarget != null)
                item('互动设置', Icons.mark_unread_chat_alt_outlined, () async {
                  if (!await controller.loadInteraction(current)) {
                    notice();
                    return;
                  }
                  if (context.mounted) {
                    await showAppDialog<void>(
                      context: context,
                      builder: (_) => _DynamicInteractionDialog(post: current),
                    );
                  }
                }),
              if (current.editable)
                item('编辑动态', Icons.edit_note, () async {
                  final draft = await controller.editDraft(current);
                  if (draft == null) {
                    notice();
                    return;
                  }
                  if (!context.mounted) return;
                  final success = await showAppDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ProviderScope(
                      overrides: [
                        dynamicComposerProvider.overrideWith(
                          () => DynamicComposerController(editDraft: draft),
                        ),
                      ],
                      child: Consumer(
                        builder: (context, ref, _) {
                          ref.listen(
                            dynamicComposerProvider.select((s) => s.uncertain),
                            (_, uncertain) {
                              if (uncertain) {
                                ref
                                    .read(dynamicContentProvider.notifier)
                                    .lock(current.id, 'edit');
                              }
                            },
                          );
                          return const DynamicComposeDialog();
                        },
                      ),
                    ),
                  );
                  if (success == true && context.mounted) {
                    await controller.refresh();
                    if (context.mounted) showAppNotice(context, '动态修改已保存');
                  }
                }, action: 'edit'),
              item('检查动态公开可见性', Icons.fact_check_outlined, () async {
                final ok = await controller.checkPublic(current);
                if (!context.mounted) return;
                if (!ok) {
                  notice();
                  return;
                }
                final visible = ref.read(provider).publicVisible;
                await showAppDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('动态公开可见性'),
                    content: SingleChildScrollView(
                      child: Text(
                        visible == true
                            ? '游客可以读取这条动态。'
                            : '游客暂时不能读取这条动态；仅自己可见或内容审核等情况也可能产生此结果。',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                );
              }),
              item('删除动态', Icons.delete_outline, () async {
                if (await confirm('删除动态', '确定删除这条动态？删除后无法恢复。') &&
                    sameAccount()) {
                  if (await controller.remove(current)) {
                    if (context.mounted) Navigator.pop(context);
                  } else {
                    notice();
                  }
                }
              }, action: 'remove'),
            ] else if (current.authorId != null) ...[
              const Divider(),
              item('举报动态', Icons.flag_outlined, () async {
                if (!auth.isSignedIn) {
                  onLogin?.call();
                  if (onLogin == null) showAppNotice(context, '请先登录后举报');
                  return;
                }
                await showAppDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _DynamicReportDialog(post: current),
                );
              }, action: 'report'),
              item('拉黑该UP主', Icons.block, () async {
                if (!auth.isSignedIn) {
                  onLogin?.call();
                  if (onLogin == null) showAppNotice(context, '请先登录后拉黑');
                  return;
                }
                final blocked = await showAppDialog<bool>(
                  context: context,
                  builder: (_) => _DynamicBlockDialog(
                    author: current.authorId!,
                    name: current.authorName,
                    scope: menuScope,
                    epoch: menuEpoch,
                  ),
                );
                if (blocked == true && context.mounted && sameAccount()) {
                  ref
                      .read(dynamicContentProvider.notifier)
                      .hideAuthor(current.authorId!.value, current.authorName);
                  Navigator.pop(context);
                }
              }),
            ],
            item(
              '刷新动态状态',
              Icons.refresh,
              () => run(controller.refresh, '动态状态已刷新', needsLogin: false),
            ),
            if (locks.isNotEmpty)
              const Text('部分操作结果待核对，已阻止重复提交。请先刷新动态并核对已发布内容。'),
            if (state.message case final message?)
              Padding(padding: const EdgeInsets.all(12), child: Text(message)),
          ],
        ),
      ),
    );
  }
}

Future<void> showTemporaryDynamicBlocks(BuildContext context) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final authors = ref.watch(dynamicContentProvider).hiddenAuthors;
          return DynamicFormDialog(
            title: '临时屏蔽的UP主',
            body: ListView(
              children: [
                const Text('重新启动或切换账号后恢复。'),
                if (authors.isEmpty) const Text('没有临时屏蔽的UP主'),
                for (final e in authors.entries)
                  ListTile(
                    title: Text(e.value),
                    subtitle: Text('UID ${e.key}'),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(dynamicContentProvider.notifier)
                          .restoreAuthor(e.key),
                      child: const Text('恢复显示'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

class _DynamicInteractionDialog extends ConsumerWidget {
  const _DynamicInteractionDialog({required this.post});
  final DynamicPost post;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = dynamicManagementProvider(post.id),
        state = ref.watch(provider),
        s = state.interaction;
    final locked =
        ref
            .watch(dynamicContentProvider)
            .locked[post.id]
            ?.contains('interaction') ==
        true;
    return DynamicFormDialog(
      title: '互动设置',
      canClose: !state.busy,
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('评论精选'),
            value: s?.selected ?? false,
            onChanged: state.busy || locked || s?.canSelect != true
                ? null
                : (v) => ref
                      .read(provider.notifier)
                      .setInteraction(post, v ? 1 : 2),
          ),
          SwitchListTile(
            title: const Text('允许评论'),
            value: s?.comments ?? false,
            onChanged: state.busy || locked || s?.canComment != true
                ? null
                : (v) => ref
                      .read(provider.notifier)
                      .setInteraction(post, v ? 4 : 3),
          ),
          if (state.message case final message?) Text(message),
        ],
      ),
      actions: [
        TextButton(
          onPressed: state.busy
              ? null
              : () => ref.read(provider.notifier).loadInteraction(post),
          child: const Text('刷新设置'),
        ),
      ],
    );
  }
}

class _DynamicBlockDialog extends ConsumerWidget {
  const _DynamicBlockDialog({
    required this.author,
    required this.name,
    required this.scope,
    required this.epoch,
  });
  final UserId author;
  final String name;
  final String? scope;
  final int? epoch;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = profileActionsControllerProvider(author),
        state = ref.watch(provider),
        repo = ref.watch(dynamicRepositoryProvider);
    final current = repo?.accountScope == scope && repo?.sessionEpoch == epoch;
    return PopScope(
      canPop: !state.busy,
      child: AlertDialog(
        title: const Text('拉黑UP主'),
        content: SingleChildScrollView(
          child: Text(
            !current
                ? '账号已变化，请重新打开'
                : state.message ??
                      (state.blocked == null
                          ? '正在读取黑名单状态…'
                          : state.blocked == true
                          ? '该UP主已在黑名单'
                          : '确定拉黑 $name？'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: !current || state.busy || state.blocked == null
                ? null
                : () async {
                    if (state.blocked != true) {
                      await ref.read(provider.notifier).setBlocked(true);
                    }
                    if (context.mounted && ref.read(provider).blocked == true) {
                      Navigator.pop(context, true);
                    }
                  },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _DynamicReportDialog extends ConsumerStatefulWidget {
  const _DynamicReportDialog({required this.post});
  final DynamicPost post;
  @override
  ConsumerState<_DynamicReportDialog> createState() =>
      _DynamicReportDialogState();
}

class _DynamicReportDialogState extends ConsumerState<_DynamicReportDialog> {
  final _text = TextEditingController();
  int _reason = 4;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = dynamicManagementProvider(widget.post.id),
        state = ref.watch(provider);
    ref.listen(
      authControllerProvider.select(
        (a) => (
          a.status,
          a.mid,
          ref.read(dynamicRepositoryProvider)?.sessionEpoch,
        ),
      ),
      (_, _) => _text.clear(),
    );
    final locked =
        ref
            .watch(dynamicContentProvider)
            .locked[widget.post.id]
            ?.contains('report') ==
        true;
    return PopScope(
      canPop: !state.busy,
      child: DynamicFormDialog(
        title: '举报动态',
        canClose: !state.busy,
        body: ListView(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '举报理由'),
              items: [
                for (final e in const {
                  4: '垃圾广告',
                  8: '引战',
                  1: '色情',
                  5: '人身攻击',
                  3: '违法信息',
                  9: '涉政谣言',
                  10: '涉社会事件谣言',
                  12: '虚假不实信息',
                  13: '违法信息外链',
                  0: '其他（请填写说明）',
                }.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: state.busy || locked
                  ? null
                  : (v) => setState(() => _reason = v ?? 4),
            ),
            TextField(
              controller: _text,
              enabled: !state.busy && !locked,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '补充说明'),
            ),
            if (state.message case final message?) Text(message),
            if (locked) const Text('举报已提交或结果未确认，请勿重复举报。'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: state.busy || locked
                ? null
                : () async {
                    if (_reason == 0 && _text.text.trim().isEmpty) {
                      showAppNotice(context, '请填写举报说明');
                      return;
                    }
                    if (await ref
                            .read(provider.notifier)
                            .report(widget.post, _reason, _text.text) &&
                        context.mounted) {
                      Navigator.pop(context);
                      showAppNotice(context, '举报已提交');
                    }
                  },
            child: const Text('提交举报'),
          ),
        ],
      ),
    );
  }
}

class DynamicPostSaveDialog extends ConsumerStatefulWidget {
  const DynamicPostSaveDialog({super.key, required this.post});
  final DynamicPost post;
  @override
  ConsumerState<DynamicPostSaveDialog> createState() =>
      _DynamicPostSaveDialogState();
}

class _DynamicPostSaveDialogState extends ConsumerState<DynamicPostSaveDialog> {
  final _key = GlobalKey();
  bool _busy = false;
  Future<void> _save() async {
    setState(() => _busy = true);
    ui.Image? image;
    try {
      final boundary = _key.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Missing preview');
      }
      final size = boundary.size;
      if (size.height > 20000 || size.width * size.height > 40000000) {
        throw StateError('Preview too large');
      }
      image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > 32 * 1024 * 1024) {
        throw StateError('Snapshot too large');
      }
      final bytes = Uint8List.sublistView(data);
      await ref.read(imageExportServiceProvider).save(bytes);
      if (mounted) showAppNotice(context, '动态图片已保存');
    } catch (_) {
      if (mounted) showAppNotice(context, '无法保存动态图片，请稍后重试或复制动态链接');
    } finally {
      image?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: DynamicFormDialog(
      title: '保存动态',
      canClose: !_busy,
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: _key,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DynamicPostCard(post: widget.post, inDetail: true),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    Uri.https(
                      't.bilibili.com',
                      '/${widget.post.id}',
                    ).toString(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _busy || !ref.watch(imageExportServiceProvider).supported
              ? null
              : _save,
          child: Text(_busy ? '保存中…' : '保存图片'),
        ),
      ],
    ),
  );
}
