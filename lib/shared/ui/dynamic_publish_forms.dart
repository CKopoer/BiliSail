import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_failure.dart';
import '../../features/dynamic/application/dynamic_compose_choices.dart';
import '../../features/dynamic/application/dynamic_composer_controller.dart';
import '../../features/dynamic/domain/dynamic_draft.dart';
import 'app_dialog.dart';
import 'app_network_image.dart';
import 'app_notice.dart';
import 'emoticon_picker_dialog.dart';

class DynamicEmotePicker extends ConsumerWidget {
  const DynamicEmotePicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(dynamicComposeEmotesProvider);
    final packages = result.asData?.value ?? const <DynamicEmotePackage>[];
    return EmoticonPickerDialog(
      title: 'B站表情',
      loading: result.isLoading,
      message: result.hasError ? '表情加载失败，请重试' : null,
      emptyMessage: '暂无可用表情',
      onRetry: () => ref.invalidate(dynamicComposeEmotesProvider),
      packageNames: [for (final p in packages) p.name],
      packageBuilder: (context, index) => GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 76,
          mainAxisExtent: 64,
        ),
        itemCount: packages[index].items.length,
        itemBuilder: (context, i) {
          final e = packages[index].items[i];
          return Tooltip(
            message: e.text,
            child: TextButton(
              onPressed: () => Navigator.pop(context, e),
              child: e.imageUrl == null
                  ? Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis)
                  : AppNetworkImage(
                      url: e.imageUrl.toString(),
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      cacheWidth: 108,
                      cacheHeight: 108,
                      errorBuilder: (_, _, _) => Text(
                        e.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class DynamicMentionPicker extends ConsumerStatefulWidget {
  const DynamicMentionPicker({super.key});
  @override
  ConsumerState<DynamicMentionPicker> createState() =>
      _DynamicMentionPickerState();
}

class _DynamicMentionPickerState extends ConsumerState<DynamicMentionPicker> {
  final _search = TextEditingController();
  String _keyword = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = dynamicComposeMentionsProvider(_keyword);
    final items = ref.watch(provider);
    void search() => setState(() => _keyword = _search.text.trim());
    return DynamicFormDialog(
      title: '@用户',
      body: Column(
        children: [
          TextField(
            controller: _search,
            maxLength: 512,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              hintText: '搜索用户',
              suffixIcon: IconButton(
                tooltip: '搜索用户',
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('加载失败，重试'),
                ),
              ),
              data: (users) => users.isEmpty
                  ? const Center(child: Text('没有找到用户'))
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(users[i].name),
                        subtitle: Text('UID ${users[i].id}'),
                        onTap: () => Navigator.pop(context, users[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bounded by the actual dialog area, including keyboard and window resizing.
class DynamicFormDialog extends StatelessWidget {
  const DynamicFormDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.canClose = true,
  });
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool canClose;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 600,
      height: 680,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: canClose ? () => Navigator.pop(context) : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: body),
            if (actions.isNotEmpty) ...[
              const Divider(),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String dynamicDateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Future<DateTime?> chooseDynamicTime(
  BuildContext context, {
  required DateTime now,
  required DateTime initial,
  required int maxDays,
}) => showAppDialog<DateTime>(
  context: context,
  builder: (_) =>
      DynamicDateTimePicker(now: now, initial: initial, maxDays: maxDays),
);

class DynamicDateTimePicker extends StatefulWidget {
  const DynamicDateTimePicker({
    super.key,
    required this.now,
    required this.initial,
    required this.maxDays,
  });
  final DateTime now, initial;
  final int maxDays;
  @override
  State<DynamicDateTimePicker> createState() => _DynamicDateTimePickerState();
}

class _DynamicDateTimePickerState extends State<DynamicDateTimePicker> {
  late final _last = widget.now.add(Duration(days: widget.maxDays));
  late DateTime _date = widget.initial.isAfter(_last)
      ? _last
      : widget.initial.isBefore(widget.now)
      ? widget.now
      : widget.initial;
  late int _hour = widget.initial.hour, _minute = widget.initial.minute;
  @override
  Widget build(BuildContext context) => DynamicFormDialog(
    title: '选择日期和时间',
    body: ListView(
      children: [
        // The calendar follows Flutter's own bounded calendar text scale; other
        // controls retain the user's scale and stay reachable by scrolling.
        SizedBox(
          height: 360,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: CalendarDatePicker(
              initialDate: _date,
              firstDate: widget.now,
              lastDate: _last,
              onDateChanged: (date) => setState(() => _date = date),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _hour,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '小时'),
                items: [
                  for (var h = 0; h < 24; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text(h.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (h) => setState(() => _hour = h ?? _hour),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _minute,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分钟'),
                items: [
                  for (var m = 0; m < 60; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (m) => setState(() => _minute = m ?? _minute),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '本地时间 ${dynamicDateLabel(DateTime(_date.year, _date.month, _date.day, _hour, _minute))}',
        ),
      ],
    ),
    actions: [
      FilledButton(
        key: const ValueKey('dynamic-time-confirm'),
        onPressed: () => Navigator.pop(
          context,
          DateTime(_date.year, _date.month, _date.day, _hour, _minute),
        ),
        child: const Text('确定'),
      ),
    ],
  );
}

class DynamicPollEditor extends ConsumerStatefulWidget {
  const DynamicPollEditor({super.key, this.draft});
  final DynamicPollDraft? draft;
  @override
  ConsumerState<DynamicPollEditor> createState() => _DynamicPollEditorState();
}

class _DynamicPollEditorState extends ConsumerState<DynamicPollEditor> {
  late final _title = TextEditingController(text: widget.draft?.title);
  late final _description = TextEditingController(
    text: widget.draft?.description,
  );
  late final _options = [
    for (final o
        in widget.draft?.options ??
            const [DynamicPollOption(''), DynamicPollOption('')])
      (text: TextEditingController(text: o.text), image: o.image),
  ];
  late DateTime _end =
      widget.draft?.endsAt ??
      ref.read(dynamicComposerClockProvider)().add(const Duration(days: 1));
  late int _choices = widget.draft?.maxChoices ?? 1;
  late bool _withImages = widget.draft?.withImages ?? false;
  bool _picking = false;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final o in _options) {
      o.text.dispose();
    }
    super.dispose();
  }

  Future<void> _image(int index) async {
    final controller = ref.read(dynamicComposerProvider.notifier);
    final draft = ref.read(dynamicComposerProvider);
    setState(() => _picking = true);
    try {
      final images = await ref.read(dynamicImagePickerProvider)(1);
      if (mounted &&
          controller.isCurrent(draft.accountScope, draft.sessionEpoch) &&
          images.isNotEmpty) {
        setState(
          () => _options[index] = (
            text: _options[index].text,
            image: images.first,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotice(context, e is AppFailure ? e.message : '无法读取图片');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => DynamicFormDialog(
    title: '投票',
    body: ListView(
      children: [
        TextField(
          key: const ValueKey('dynamic-poll-title'),
          controller: _title,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '投票标题'),
        ),
        TextField(
          controller: _description,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '补充说明（选填）'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('图片投票'),
          value: _withImages,
          onChanged: _picking ? null : (v) => setState(() => _withImages = v),
        ),
        for (final (i, option) in _options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('dynamic-poll-option-$i'),
                        controller: option.text,
                        maxLength: 50,
                        decoration: InputDecoration(labelText: '选项${i + 1}'),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除选项${i + 1}',
                      onPressed: _picking || _options.length <= 2
                          ? null
                          : () => setState(() {
                              _options.removeAt(i).text.dispose();
                              if (_choices > _options.length) {
                                _choices = _options.length;
                              }
                            }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                if (_withImages)
                  OutlinedButton.icon(
                    onPressed: _picking ? null : () => _image(i),
                    icon: option.image == null
                        ? const Icon(Icons.add_photo_alternate_outlined)
                        : Image.memory(
                            option.image!.bytes,
                            width: 48,
                            height: 48,
                            cacheWidth: 96,
                            errorBuilder: (_, _, _) => const Icon(Icons.image),
                          ),
                    label: Text(option.image == null ? '添加选项图片' : '更换选项图片'),
                  ),
              ],
            ),
          ),
        if (_options.length < 20)
          TextButton.icon(
            onPressed: _picking
                ? null
                : () => setState(
                    () => _options.add((
                      text: TextEditingController(),
                      image: null,
                    )),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('添加选项'),
          ),
        DropdownButtonFormField<int>(
          key: ValueKey('dynamic-poll-choices-$_choices'),
          initialValue: _choices,
          decoration: const InputDecoration(labelText: '可选数量'),
          items: [
            for (var i = 1; i <= _options.length; i++)
              DropdownMenuItem(value: i, child: Text(i == 1 ? '单选' : '最多选$i项')),
          ],
          onChanged: (v) => setState(() => _choices = v ?? 1),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () async {
            final date = await chooseDynamicTime(
              context,
              now: ref.read(dynamicComposerClockProvider)(),
              initial: _end,
              maxDays: 90,
            );
            if (date != null && mounted) setState(() => _end = date);
          },
          child: Text('截止时间 ${dynamicDateLabel(_end)}'),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: _picking
            ? null
            : () {
                final poll = DynamicPollDraft(
                  title: _title.text,
                  description: _description.text,
                  options: [
                    for (final o in _options)
                      DynamicPollOption(
                        o.text.text,
                        image: _withImages ? o.image : null,
                      ),
                  ],
                  endsAt: _end,
                  maxChoices: _choices,
                  withImages: _withImages,
                );
                if (!poll.validAt(ref.read(dynamicComposerClockProvider)())) {
                  showAppNotice(context, '请填写标题和2至20个完整选项，截止时间须在未来90天内');
                  return;
                }
                Navigator.pop(context, poll);
              },
        child: const Text('保存投票'),
      ),
    ],
  );
}

class DynamicReserveEditor extends ConsumerStatefulWidget {
  const DynamicReserveEditor({super.key, this.draft});
  final DynamicReserveDraft? draft;
  @override
  ConsumerState<DynamicReserveEditor> createState() =>
      _DynamicReserveEditorState();
}

class _DynamicReserveEditorState extends ConsumerState<DynamicReserveEditor> {
  late final _title = TextEditingController(text: widget.draft?.title);
  late DateTime _time =
      widget.draft?.startsAt ??
      ref.read(dynamicComposerClockProvider)().add(const Duration(days: 1));
  late bool _members = widget.draft?.onlyMembers ?? false;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DynamicFormDialog(
    title: '直播预约',
    body: ListView(
      children: [
        TextField(
          key: const ValueKey('dynamic-reserve-title'),
          controller: _title,
          maxLength: 50,
          decoration: const InputDecoration(labelText: '预约标题'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('大航海直播'),
          value: _members,
          onChanged: (v) => setState(() => _members = v),
        ),
        OutlinedButton(
          onPressed: () async {
            final date = await chooseDynamicTime(
              context,
              now: ref.read(dynamicComposerClockProvider)(),
              initial: _time,
              maxDays: 90,
            );
            if (date != null && mounted) setState(() => _time = date);
          },
          child: Text('开播时间 ${dynamicDateLabel(_time)}'),
        ),
        const Text('点击发布时创建预约；请确认账号拥有对应直播权限。'),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () {
          final draft = DynamicReserveDraft(
            _title.text,
            _time,
            onlyMembers: _members,
          );
          if (!draft.validAt(ref.read(dynamicComposerClockProvider)())) {
            showAppNotice(context, '请填写标题，并选择未来90天内的开播时间');
            return;
          }
          Navigator.pop(context, draft);
        },
        child: const Text('保存预约'),
      ),
    ],
  );
}
