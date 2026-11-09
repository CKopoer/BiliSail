import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_failure.dart';
import '../../domain/local_image.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/dynamic/application/dynamic_composer_controller.dart';
import '../../features/dynamic/domain/dynamic_composer_repository.dart';
import 'app_dialog.dart';
import 'app_notice.dart';

class DynamicComposeToolbar extends StatelessWidget {
  const DynamicComposeToolbar({
    super.key,
    required this.child,
    this.topic,
    this.onPublished,
    this.onLogin,
    this.label = '发布动态',
    this.enabled = true,
    this.visible = true,
  });

  final Widget child;
  final DynamicComposeTopic? topic;
  final Future<void> Function()? onPublished;
  final VoidCallback? onLogin;
  final String label;
  final bool enabled;
  final bool visible;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final extraTextWidth =
          (MediaQuery.textScalerOf(context).scale(13) - 13) * 8;
      return Row(
        children: [
          Expanded(child: child),
          if (visible)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: DynamicComposeButton(
                compact: constraints.maxWidth < 480 + extraTextWidth,
                topic: topic,
                onPublished: onPublished,
                onLogin: onLogin,
                label: label,
                enabled: enabled,
              ),
            ),
        ],
      );
    },
  );
}

class DynamicComposeButton extends ConsumerWidget {
  const DynamicComposeButton({
    super.key,
    this.topic,
    this.onPublished,
    this.onLogin,
    this.label = '发布动态',
    this.enabled = true,
    this.compact = false,
  });
  final DynamicComposeTopic? topic;
  final Future<void> Function()? onPublished;
  final VoidCallback? onLogin;
  final String label;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: .07),
      disabledBackgroundColor: theme.colorScheme.surfaceContainerLow,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final icon = Icon(
      topic == null ? Icons.edit_outlined : Icons.tag,
      size: 20,
    );
    final VoidCallback? onPressed = !enabled
        ? null
        : () async {
            if (!ref.read(authControllerProvider).isSignedIn) {
              if (onLogin != null) {
                onLogin!();
              } else {
                showAppNotice(context, '请先登录后发布动态');
              }
              return;
            }
            final controller = ref.read(dynamicComposerProvider.notifier);
            if (topic != null) {
              controller.setTopic(topic);
            }
            final success = await showAppDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const DynamicComposeDialog(),
            );
            if (success == true && context.mounted) {
              showAppNotice(context, '动态发布成功');
              await onPublished?.call();
            }
          };
    if (compact) {
      return IconButton(
        key: const ValueKey('dynamic-compose'),
        tooltip: label,
        style: style,
        icon: icon,
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      key: const ValueKey('dynamic-compose'),
      style: style,
      icon: icon,
      label: Text(label, maxLines: 1),
      onPressed: onPressed,
    );
  }
}

class DynamicComposeDialog extends ConsumerStatefulWidget {
  const DynamicComposeDialog({super.key});
  @override
  ConsumerState<DynamicComposeDialog> createState() =>
      _DynamicComposeDialogState();
}

class _DynamicComposeDialogState extends ConsumerState<DynamicComposeDialog> {
  late final TextEditingController _text;
  bool _picking = false;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(dynamicComposerProvider).text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final controller = ref.read(dynamicComposerProvider.notifier);
    final draft = ref.read(dynamicComposerProvider);
    if (draft.busy || _picking) return;
    setState(() => _picking = true);
    try {
      final images = await ref.read(dynamicImagePickerProvider)(
        LocalImage.maxCount - draft.images.length,
      );
      if (mounted &&
          controller.isCurrent(draft.accountScope, draft.sessionEpoch)) {
        controller.addImages(images);
      }
    } catch (error) {
      if (mounted &&
          controller.isCurrent(draft.accountScope, draft.sessionEpoch)) {
        showAppNotice(
          context,
          error is AppFailure ? error.message : '无法读取图片，请重新选择',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _chooseTopic() async {
    final draft = ref.read(dynamicComposerProvider);
    final controller = ref.read(dynamicComposerProvider.notifier);
    final topic = await showAppDialog<DynamicComposeTopic>(
      context: context,
      builder: (_) => const _TopicPicker(),
    );
    if (topic != null &&
        mounted &&
        controller.isCurrent(draft.accountScope, draft.sessionEpoch)) {
      controller.setTopic(topic);
    }
  }

  Future<void> _emoji() async {
    final draft = ref.read(dynamicComposerProvider);
    final emoji = await showAppDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('插入表情'),
        children: [
          Wrap(
            children: [
              for (final emoji in [
                '😀',
                '😂',
                '🥰',
                '😎',
                '🤔',
                '😭',
                '👍',
                '👏',
                '🎉',
                '❤️',
                '✨',
                '🙏',
              ])
                TextButton(
                  onPressed: () => Navigator.pop(context, emoji),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
            ],
          ),
        ],
      ),
    );
    if (emoji == null ||
        !mounted ||
        !ref
            .read(dynamicComposerProvider.notifier)
            .isCurrent(draft.accountScope, draft.sessionEpoch)) {
      return;
    }
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    ref.read(dynamicComposerProvider.notifier).setText(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dynamicComposerProvider);
    final controller = ref.read(dynamicComposerProvider.notifier);
    ref.listen(
      dynamicComposerProvider.select(
        (s) => (s.accountScope, s.sessionEpoch, s.mid),
      ),
      (old, value) {
        _text.clear();
      },
    );
    final busy = state.busy || _picking;
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: 720,
          height: (MediaQuery.sizeOf(context).height * .85).clamp(240, 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '发布动态',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭并保留草稿',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.topic case final topic?)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InputChip(
                              label: Text('#${topic.name}#'),
                              onDeleted: busy
                                  ? null
                                  : () => controller.setTopic(null),
                            ),
                          ),
                        TextField(
                          key: const ValueKey('dynamic-compose-text'),
                          controller: _text,
                          enabled: !busy && state.mid != null,
                          minLines: 5,
                          maxLines: null,
                          decoration: const InputDecoration(
                            hintText: '分享新鲜事…',
                            border: InputBorder.none,
                          ),
                          onChanged: controller.setText,
                        ),
                        Text(
                          '${state.text.runes.length}/1000',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: state.text.runes.length > 1000
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                        if (state.images.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (index, image) in state.images.indexed)
                                SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          image.bytes,
                                          fit: BoxFit.cover,
                                          cacheWidth: 200,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.topRight,
                                        child: IconButton.filledTonal(
                                          tooltip: '移除图片${index + 1}',
                                          onPressed: busy
                                              ? null
                                              : () => controller.removeImage(
                                                  image,
                                                ),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        if (state.busy)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              state.images.isEmpty
                                  ? '正在发布…'
                                  : '已上传 ${state.uploaded}/${state.images.length} 张图片，正在发布…',
                            ),
                          ),
                        if (state.message case final message?)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              message,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (state.mid == null) const Text('账号已退出，草稿已清空，请重新登录。'),
                        if (state.uncertain)
                          TextButton(
                            onPressed: () async {
                              final confirmed = await showAppDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('确认发布结果'),
                                  content: const Text(
                                    '请先查看自己的动态，确认这条内容未发布后再继续，避免重复发布。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('返回核对'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('确认未发布'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                controller.confirmNotPublished();
                              }
                            },
                            child: const Text('核对发布结果'),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      children: [
                        IconButton(
                          tooltip: '添加图片',
                          onPressed:
                              busy ||
                                  state.images.length >= LocalImage.maxCount ||
                                  state.mid == null
                              ? null
                              : _pickImages,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                        IconButton(
                          tooltip: '选择话题',
                          onPressed: busy || state.mid == null
                              ? null
                              : _chooseTopic,
                          icon: const Icon(Icons.tag),
                        ),
                        IconButton(
                          tooltip: '插入表情',
                          onPressed: busy || state.mid == null ? null : _emoji,
                          icon: const Icon(Icons.emoji_emotions_outlined),
                        ),
                        TextButton(
                          onPressed: busy || state.uncertain
                              ? null
                              : () {
                                  controller.clear();
                                  _text.clear();
                                },
                          child: const Text('清空草稿'),
                        ),
                      ],
                    ),
                    FilledButton(
                      key: const ValueKey('dynamic-compose-submit'),
                      onPressed: state.canPublish && !_picking
                          ? () async {
                              if (await controller.publish() &&
                                  context.mounted) {
                                Navigator.pop(context, true);
                              }
                            }
                          : null,
                      child: Text(state.busy ? '发布中…' : '发布'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicPicker extends ConsumerStatefulWidget {
  const _TopicPicker();
  @override
  ConsumerState<_TopicPicker> createState() => _TopicPickerState();
}

class _TopicPickerState extends ConsumerState<_TopicPicker> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(dynamicComposeTopicsProvider);
    void search() => ref
        .read(dynamicComposeTopicsProvider.notifier)
        .search(_text.text.trim());
    return AlertDialog(
      title: const Text('选择话题'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('dynamic-topic-search'),
              controller: _text,
              maxLength: 512,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: '搜索话题',
                suffixIcon: IconButton(
                  tooltip: '搜索话题',
                  onPressed: search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: items.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error is AppFailure ? error.message : '话题加载失败'),
                      TextButton(onPressed: search, child: const Text('重试')),
                    ],
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('没有找到话题'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) => ListTile(
                          leading: const Icon(Icons.tag),
                          title: Text(items[index].name),
                          onTap: () => Navigator.pop(context, items[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
