import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/comments/application/comment_image_saver.dart';
import '../../features/comments/application/comments_controller.dart';
import '../../features/comments/domain/comments_repository.dart';
import 'app_dialog.dart';
import 'app_notice.dart';
import 'comment_rich_content.dart';
import 'save_widget_image.dart';

enum _Action { copy, save, report, pin, delete }

Future<void> showCommentMoreMenu({
  required BuildContext context,
  required BuildContext anchor,
  required WidgetRef ref,
  required NotifierProvider<CommentsController, CommentsState> provider,
  required String id,
  required bool Function() isCurrent,
}) async {
  final state = ref.read(provider);
  final target = state.findComment(id);
  if (target == null) return;
  final comment = target.entry;
  final controller = ref.read(provider.notifier);
  final box = anchor.findRenderObject() as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  bool current() =>
      context.mounted &&
      isCurrent() &&
      controller.isCurrentAccount(state.accountScope, state.sessionEpoch);
  final writable = !state.busy && !state.loading && !state.replyLoading;
  bool enabled(String operation) =>
      writable && !state.uncertain.contains('$operation:$id');
  final pinLabel = comment.isUpPinned ? '取消置顶' : '置顶';
  PopupMenuItem<_Action> item(
    _Action value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => PopupMenuItem(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: value == _Action.delete && enabled
              ? Theme.of(context).colorScheme.error
              : null,
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );
  final selected = await showMenu<_Action>(
    context: anchor,
    position: RelativeRect.fromRect(
      origin & box.size,
      Offset.zero & overlay.size,
    ),
    items: [
      item(
        _Action.copy,
        Icons.copy_all_outlined,
        '复制全部',
        enabled: comment.message.isNotEmpty,
      ),
      item(
        _Action.save,
        Icons.save_alt,
        '保存评论',
        enabled: ref.read(commentImageSaverProvider) != null,
      ),
      if (state.signedIn)
        item(
          _Action.report,
          Icons.flag_outlined,
          '举报',
          enabled: enabled('report'),
        ),
      if (state.isUpper && target.rootId == null)
        item(
          _Action.pin,
          Icons.vertical_align_top,
          pinLabel,
          enabled: enabled('pin'),
        ),
      if (state.canDelete(comment))
        item(
          _Action.delete,
          Icons.delete_outline,
          '删除',
          enabled: enabled('delete'),
        ),
    ],
  );
  if (!context.mounted || selected == null || !current()) return;
  Future<bool> confirm(String title, String body) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ==
      true;
  var success = true;
  String notice;
  switch (selected) {
    case _Action.copy:
      try {
        await Clipboard.setData(ClipboardData(text: comment.message));
        notice = '已复制评论';
      } on PlatformException {
        notice = '复制失败，请重试';
      }
    case _Action.save:
      await showAppDialog<void>(
        context: context,
        builder: (_) => _SaveCommentDialog(comment: comment),
      );
      return;
    case _Action.report:
      final report = await showAppDialog<({int reason, String description})>(
        context: context,
        builder: (_) => const _ReportDialog(),
      );
      if (report == null || !current()) return;
      success = await controller.reportComment(
        id,
        report.reason,
        report.description,
      );
      notice = '举报已提交';
    case _Action.pin:
      if (!comment.isUpPinned &&
          !await confirm('置顶评论', '置顶这条评论？已有的 UP 主置顶将被替换。')) {
        return;
      }
      if (!current()) return;
      success = await controller.setPinned(id, !comment.isUpPinned);
      notice = '已$pinLabel';
    case _Action.delete:
      if (!await confirm(
        '删除评论',
        '确定删除 @${comment.author} 的这条评论？\n\n${comment.message}',
      )) {
        return;
      }
      if (!current()) return;
      success = await controller.deleteComment(id);
      notice = '评论已删除';
  }
  if (!context.mounted || !current()) return;
  if (success) {
    showAppNotice(context, notice);
  } else if (ref.read(provider).message case final message?) {
    showAppNotice(context, message);
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  static const reasons = {
    1: '垃圾广告',
    3: '刷屏',
    4: '引战',
    7: '人身攻击',
    15: '侵犯隐私',
    9: '违法违规',
    2: '色情',
    10: '低俗',
    12: '赌博诈骗',
    23: '违法信息外链',
    19: '涉政谣言',
    20: '涉社会事件谣言',
    22: '虚假不实信息',
    5: '剧透',
    8: '视频不相关',
    18: '违规抽奖',
    17: '青少年不良信息',
    0: '其他',
  };
  int? _reason;
  String _description = '';
  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    final required = reason == 0 || reason == 22;
    return AlertDialog(
      title: const Text('举报评论'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: '举报理由'),
              items: [
                for (final entry in reasons.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => setState(() => _reason = v),
            ),
            const SizedBox(height: 12),
            TextField(
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: required ? '补充说明（必填）' : '补充说明（选填）',
              ),
              onChanged: (text) => setState(() => _description = text.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: reason == null || required && _description.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  reason: reason,
                  description: _description,
                )),
          child: const Text('提交举报'),
        ),
      ],
    );
  }
}

class _SaveCommentDialog extends ConsumerStatefulWidget {
  const _SaveCommentDialog({required this.comment});
  final CommentEntry comment;
  @override
  ConsumerState<_SaveCommentDialog> createState() => _SaveCommentDialogState();
}

class _SaveCommentDialogState extends ConsumerState<_SaveCommentDialog> {
  final _preview = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    final saver = ref.read(commentImageSaverProvider);
    if (_saving || saver == null) return;
    setState(() => _saving = true);
    try {
      final png = await captureWidgetPng(_preview, pixelRatio: 2);
      if (!mounted) return;
      final path = await saver(png);
      if (mounted && path != null) {
        showAppNotice(context, '评论图片已保存至 $path');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) showAppNotice(context, '无法保存评论图片，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('保存评论'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: RepaintBoundary(
          key: _preview,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CommentAuthorHeader(comment: widget.comment),
                  const SizedBox(height: 8),
                  CommentRichContent(comment: widget.comment),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存图片'),
        ),
      ],
    ),
  );
}
