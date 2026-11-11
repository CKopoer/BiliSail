import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_failure.dart';
import '../../domain/local_image.dart';
import '../../features/dynamic/application/dynamic_composer_controller.dart';
import '../../features/dynamic/domain/dynamic_composer_repository.dart';
import '../../features/dynamic/domain/dynamic_draft.dart';
import 'app_dialog.dart';
import 'app_notice.dart';
import 'dynamic_publish_forms.dart';
import 'dynamic_image_editor.dart';
import 'app_network_image.dart';
import 'image_viewer.dart';

class DynamicComposeDialog extends ConsumerStatefulWidget {
  const DynamicComposeDialog({super.key});
  @override
  ConsumerState<DynamicComposeDialog> createState() =>
      _DynamicComposeDialogState();
}

class _DynamicComposeDialogState extends ConsumerState<DynamicComposeDialog> {
  late final _text = _DynamicTextController(
    ref.read(dynamicComposerProvider).text,
  );
  late final _title = TextEditingController(
    text: ref.read(dynamicComposerProvider).title,
  );
  bool _picking = false;
  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<T?> _choose<T>(WidgetBuilder builder) async {
    final draft = ref.read(dynamicComposerProvider);
    final controller = ref.read(dynamicComposerProvider.notifier);
    final result = await showAppDialog<T>(context: context, builder: builder);
    return mounted &&
            controller.isCurrent(draft.accountScope, draft.sessionEpoch)
        ? result
        : null;
  }

  Future<void> _pickImages() async {
    final controller = ref.read(dynamicComposerProvider.notifier);
    final draft = ref.read(dynamicComposerProvider);
    if (draft.busy || _picking) return;
    setState(() => _picking = true);
    try {
      final images = await ref.read(dynamicImagePickerProvider)(
        DynamicComposerState.maxImages -
            draft.images.length -
            draft.existingPictures.length,
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

  Future<void> _topic() async {
    final topic = await _choose<DynamicComposeTopic>(
      (_) => const DynamicTopicPicker(),
    );
    if (topic != null) {
      ref.read(dynamicComposerProvider.notifier).setTopic(topic);
    }
  }

  void _insert(String token, DynamicTextKind kind, {String id = ''}) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    final controller = ref.read(dynamicComposerProvider.notifier);
    controller.insertToken(start, end, token, kind, id: id);
    _text.value = TextEditingValue(
      text: ref.read(dynamicComposerProvider).text,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  Future<void> _emoji() async {
    final e = await _choose<DynamicEmote>((_) => const DynamicEmotePicker());
    if (e != null) _insert(e.text, DynamicTextKind.emote);
  }

  Future<void> _mention() async {
    final u = await _choose<DynamicMention>(
      (_) => const DynamicMentionPicker(),
    );
    if (u != null) _insert('@${u.name}', DynamicTextKind.mention, id: u.id);
  }

  Future<void> _poll() async {
    final draft = ref.read(dynamicComposerProvider).poll;
    final result = await _choose<DynamicPollDraft>(
      (_) => DynamicPollEditor(draft: draft),
    );
    if (result != null) {
      ref.read(dynamicComposerProvider.notifier).setPoll(result);
    }
  }

  Future<void> _reserve() async {
    final draft = ref.read(dynamicComposerProvider).reserve;
    final result = await _choose<DynamicReserveDraft>(
      (_) => DynamicReserveEditor(draft: draft),
    );
    if (result != null) {
      ref.read(dynamicComposerProvider.notifier).setReserve(result);
    }
  }

  Future<void> _time() async {
    final state = ref.read(dynamicComposerProvider);
    final controller = ref.read(dynamicComposerProvider.notifier);
    final now = ref.read(dynamicComposerClockProvider)();
    final date = await chooseDynamicTime(
      context,
      now: now,
      initial: state.options.publishAt ?? now.add(const Duration(minutes: 7)),
      maxDays: 7,
    );
    if (!mounted ||
        date == null ||
        !controller.isCurrent(state.accountScope, state.sessionEpoch)) {
      return;
    }
    final options = DynamicPublishOptions(
      replyPolicy: state.options.replyPolicy,
      publishAt: date,
    );
    if (!options.validAt(ref.read(dynamicComposerClockProvider)())) {
      showAppNotice(context, '请选择6分钟后至7天内的时间');
      return;
    }
    controller.setOptions(options);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dynamicComposerProvider);
    final controller = ref.read(dynamicComposerProvider.notifier);
    ref.listen(dynamicComposerProvider.select((s) => (s.text, s.title)), (
      _,
      value,
    ) {
      if (_text.text != value.$1) _text.text = value.$1;
      if (_title.text != value.$2) _title.text = value.$2;
    });
    ref.listen(
      dynamicComposerProvider.select(
        (s) => (s.accountScope, s.sessionEpoch, s.mid),
      ),
      (_, _) {
        _text.clear();
        _title.clear();
      },
    );
    _text.spans = state.spans;
    final busy = state.busy || _picking;
    final enabled = !busy && state.mid != null;
    final theme = Theme.of(context);
    final options = state.options;
    final length =
        state.text.runes.length + (state.poll?.title.runes.length ?? 0);
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 760,
          height: 800,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.editId == null ? '发布动态' : '编辑动态',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '清空草稿',
                      onPressed: !enabled || state.uncertain
                          ? null
                          : () {
                              controller.clear();
                              _text.clear();
                              _title.clear();
                            },
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    IconButton(
                      tooltip: state.editId == null ? '关闭并保留草稿' : '关闭编辑',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    key: const ValueKey('dynamic-compose-scroll'),
                    children: [
                      if (state.existingPictures.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, picture)
                                in state.existingPictures.indexed)
                              SizedBox(
                                width: 100,
                                height: 100,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    InkWell(
                                      onTap: () => showImageViewer(
                                        context,
                                        state.existingPictures
                                            .map((p) => p.url)
                                            .toList(),
                                        i,
                                      ),
                                      child: AppNetworkImage(
                                        url: picture.url.toString(),
                                        fit: BoxFit.cover,
                                        cacheWidth: 240,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: IconButton.filledTonal(
                                        tooltip: '移除已有图片${i + 1}',
                                        onPressed: enabled
                                            ? () => controller
                                                  .removeExistingPicture(
                                                    picture,
                                                  )
                                            : null,
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      if (state.reserveId != null) const Text('已保留原直播预约'),
                      if (state.topic case final topic?)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            label: Text(
                              '#${topic.name}#',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: enabled
                                ? () => controller.setTopic(null)
                                : null,
                          ),
                        ),
                      TextField(
                        key: const ValueKey('dynamic-compose-title'),
                        controller: _title,
                        enabled: enabled,
                        maxLength: 20,
                        decoration: const InputDecoration(
                          hintText: '标题（选填，最多20字）',
                          border: InputBorder.none,
                        ),
                        style: theme.textTheme.titleMedium,
                        onChanged: controller.setTitle,
                      ),
                      TextField(
                        key: const ValueKey('dynamic-compose-text'),
                        controller: _text,
                        enabled: enabled,
                        minLines: 4,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: '分享新鲜事…',
                          border: InputBorder.none,
                        ),
                        onChanged: controller.setText,
                      ),
                      Text(
                        '$length/1000',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: length > 1000
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (state.images.isNotEmpty)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = (constraints.maxWidth / 112)
                                .floor()
                                .clamp(2, 6);
                            final size =
                                (constraints.maxWidth - (columns - 1) * 8) /
                                columns;
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (i, image) in state.images.indexed)
                                  SizedBox(
                                    width: size,
                                    height: size,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Material(
                                            child: InkWell(
                                              onTap: !enabled
                                                  ? null
                                                  : () async {
                                                      final edited =
                                                          await _choose<
                                                            LocalImage
                                                          >(
                                                            (_) =>
                                                                DynamicImageEditor(
                                                                  image: image,
                                                                ),
                                                          );
                                                      if (edited != null) {
                                                        controller.replaceImage(
                                                          image,
                                                          edited,
                                                        );
                                                      }
                                                    },
                                              child: Image.memory(
                                                image.bytes,
                                                fit: BoxFit.cover,
                                                cacheWidth: 320,
                                                errorBuilder: (_, _, _) =>
                                                    const Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 4,
                                          bottom: 4,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surface
                                                  .withValues(alpha: .9),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              child: Text(
                                                '${i + 1}',
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: IconButton.filledTonal(
                                            tooltip: '移除图片${i + 1}',
                                            onPressed: enabled
                                                ? () => controller.removeImage(
                                                    image,
                                                  )
                                                : null,
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: PopupMenuButton<int>(
                                            tooltip: '调整图片${i + 1}顺序',
                                            enabled: enabled,
                                            icon: const Icon(Icons.swap_horiz),
                                            onSelected: (d) =>
                                                controller.moveImage(i, d),
                                            itemBuilder: (_) => [
                                              if (i > 0)
                                                const PopupMenuItem(
                                                  value: -1,
                                                  child: Text('前移'),
                                                ),
                                              if (i + 1 < state.images.length)
                                                const PopupMenuItem(
                                                  value: 1,
                                                  child: Text('后移'),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      if (state.images.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${state.images.length}/18 张 · 点击预览或裁剪',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (state.poll case final poll?)
                        _attachment(
                          '投票：${poll.title}',
                          Icons.poll_outlined,
                          enabled && !state.uncertain ? _poll : null,
                          enabled && !state.uncertain
                              ? () => controller.setPoll(null)
                              : null,
                        ),
                      if (state.reserve case final reserve?)
                        _attachment(
                          '直播预约：${reserve.title}',
                          Icons.live_tv,
                          enabled && !state.uncertain ? _reserve : null,
                          enabled && !state.uncertain
                              ? () => controller.setReserve(null)
                              : null,
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PopupMenuButton<DynamicReplyPolicy>(
                            enabled: enabled,
                            tooltip: '评论权限',
                            onSelected: (p) => controller.setOptions(
                              DynamicPublishOptions(
                                replyPolicy: p,
                                onlySelf: options.onlySelf,
                                publishAt: options.publishAt,
                              ),
                            ),
                            itemBuilder: (_) => [
                              for (final p in DynamicReplyPolicy.values)
                                PopupMenuItem(
                                  value: p,
                                  child: Text(_replyLabel(p)),
                                ),
                            ],
                            child: Chip(
                              avatar: const Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                              ),
                              label: Text(_replyLabel(options.replyPolicy)),
                            ),
                          ),
                          PopupMenuButton<bool>(
                            enabled: enabled,
                            tooltip: '可见范围',
                            onSelected: (v) => controller.setOptions(
                              DynamicPublishOptions(
                                replyPolicy: options.replyPolicy,
                                onlySelf: v,
                                publishAt: v ? null : options.publishAt,
                              ),
                            ),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: false,
                                child: Text('所有人可见'),
                              ),
                              PopupMenuItem(
                                value: true,
                                enabled: options.publishAt == null,
                                child: const Text('仅自己可见'),
                              ),
                            ],
                            child: Chip(
                              avatar: Icon(
                                options.onlySelf
                                    ? Icons.lock_outline
                                    : Icons.public,
                                size: 18,
                              ),
                              label: Text(options.onlySelf ? '仅自己可见' : '所有人可见'),
                            ),
                          ),
                          if (options.publishAt case final date?)
                            InputChip(
                              label: Text('定时 ${dynamicDateLabel(date)}'),
                              onPressed: enabled ? _time : null,
                              onDeleted: enabled
                                  ? () => controller.setOptions(
                                      DynamicPublishOptions(
                                        replyPolicy: options.replyPolicy,
                                        onlySelf: options.onlySelf,
                                      ),
                                    )
                                  : null,
                            )
                          else
                            OutlinedButton.icon(
                              onPressed:
                                  enabled &&
                                      !options.onlySelf &&
                                      state.editId == null
                                  ? _time
                                  : null,
                              icon: const Icon(Icons.schedule, size: 18),
                              label: const Text('定时发布'),
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
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (state.mid == null) const Text('账号已退出，草稿已清空，请重新登录。'),
                      if (state.uncertain)
                        TextButton(
                          onPressed: () async {
                            final confirmed = await _choose<bool>(
                              (context) => AlertDialog(
                                title: const Text('确认发布结果'),
                                content: const SingleChildScrollView(
                                  child: Text(
                                    '请先核对自己的动态、投票和直播预约，确认未创建的内容后再继续，避免重复发布。',
                                  ),
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
                            if (confirmed == true) {
                              controller.confirmNotPublished();
                            }
                          },
                          child: const Text('核对发布结果'),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    IconButton(
                      tooltip: '添加图片',
                      onPressed:
                          enabled &&
                              state.images.length +
                                      state.existingPictures.length <
                                  18
                          ? _pickImages
                          : null,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    IconButton(
                      tooltip: '选择话题',
                      onPressed: enabled ? _topic : null,
                      icon: const Icon(Icons.tag),
                    ),
                    IconButton(
                      tooltip: '插入表情',
                      onPressed: enabled ? _emoji : null,
                      icon: const Icon(Icons.emoji_emotions_outlined),
                    ),
                    IconButton(
                      tooltip: '@用户',
                      onPressed: enabled ? _mention : null,
                      icon: const Icon(Icons.alternate_email),
                    ),
                    IconButton(
                      tooltip: '投票',
                      onPressed:
                          enabled && !state.uncertain && state.editId == null
                          ? _poll
                          : null,
                      icon: const Icon(Icons.poll_outlined),
                    ),
                    IconButton(
                      tooltip: '直播预约',
                      onPressed:
                          enabled && !state.uncertain && state.editId == null
                          ? _reserve
                          : null,
                      icon: const Icon(Icons.live_tv),
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
                      child: Text(
                        state.busy
                            ? '发布中…'
                            : state.editId != null
                            ? '保存修改'
                            : options.publishAt != null
                            ? '定时发布'
                            : '发布',
                      ),
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

  Widget _attachment(
    String title,
    IconData icon,
    VoidCallback? edit,
    VoidCallback? remove,
  ) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: edit,
      trailing: IconButton(
        tooltip: '移除$title',
        onPressed: remove,
        icon: const Icon(Icons.close),
      ),
    ),
  );
}

String _replyLabel(DynamicReplyPolicy p) => switch (p) {
  DynamicReplyPolicy.allow => '允许评论',
  DynamicReplyPolicy.close => '关闭评论',
  DynamicReplyPolicy.selected => '精选评论',
};

class _DynamicTextController extends TextEditingController {
  _DynamicTextController(String text) : super(text: text);
  List<DynamicTextSpan> spans = const [];
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    var offset = 0;
    final children = <TextSpan>[];
    for (final span in spans) {
      if (span.start < offset || span.end > text.length) continue;
      if (span.start > offset) {
        children.add(TextSpan(text: text.substring(offset, span.start)));
      }
      children.add(
        TextSpan(
          text: text.substring(span.start, span.end),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      );
      offset = span.end;
    }
    children.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: children);
  }
}

class DynamicTopicPicker extends ConsumerStatefulWidget {
  const DynamicTopicPicker({super.key});
  @override
  ConsumerState<DynamicTopicPicker> createState() => DynamicTopicPickerState();
}

class DynamicTopicPickerState extends ConsumerState<DynamicTopicPicker> {
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
    return DynamicFormDialog(
      title: '选择话题',
      body: Column(
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
    );
  }
}
