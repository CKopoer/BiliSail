import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../domain/recommendation_settings.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';

final class RecommendationSettingsSection extends StatefulWidget {
  const RecommendationSettingsSection({
    super.key,
    required this.settings,
    required this.save,
  });

  final RecommendationSettings settings;
  final Future<void> Function(
    RecommendationSettings Function(RecommendationSettings) change,
  )
  save;

  @override
  State<RecommendationSettingsSection> createState() =>
      _RecommendationSettingsSectionState();
}

final class _RecommendationSettingsSectionState
    extends State<RecommendationSettingsSection> {
  Future<void> _save(
    RecommendationSettings Function(RecommendationSettings) change,
  ) async {
    try {
      await widget.save(change);
    } catch (_) {
      if (mounted) showAppNotice(context, '设置保存失败，请重试');
    }
  }

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    RecommendationSettings Function(RecommendationSettings, bool) change, {
    bool enabled = true,
  }) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: enabled
        ? (value) => _save((current) => change(current, value))
        : null,
  );

  Widget _threshold(
    String name,
    String title,
    int value,
    List<int> values,
    String suffix,
    int maximum,
    RecommendationSettings Function(RecommendationSettings, int) change,
  ) => Padding(
    key: ValueKey('recommendation-$name'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final threshold in {...values, value}.toList()..sort())
              ChoiceChip(
                label: Text(threshold == 0 ? '不限' : '$threshold$suffix'),
                selected: value == threshold,
                onSelected: (_) =>
                    _save((current) => change(current, threshold)),
              ),
            ActionChip(
              label: const Text('自定义'),
              onPressed: () async {
                final result = await showAppDialog<int>(
                  context: context,
                  builder: (_) => _NumberDialog(
                    title: title,
                    value: value,
                    suffix: suffix,
                    maximum: maximum,
                  ),
                );
                if (mounted && result != null) {
                  await _save((current) => change(current, result));
                }
              },
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _editKeywords(bool category) async {
    final words = category
        ? widget.settings.categoryKeywords
        : widget.settings.titleKeywords;
    final result = await showAppDialog<List<String>>(
      context: context,
      builder: (_) => _KeywordDialog(category: category, words: words),
    );
    if (!mounted || result == null) return;
    await _save(
      (current) => category
          ? current.copyWith(categoryKeywords: result)
          : current.copyWith(titleKeywords: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('推荐来源'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in RecommendationSource.values)
              ChoiceChip(
                label: Text(switch (source) {
                  RecommendationSource.web => 'Web 推荐',
                  RecommendationSource.app => 'App 推荐',
                  RecommendationSource.desktop => '桌面端 / PC',
                }),
                selected: s.source == source,
                onSelected: (_) =>
                    _save((current) => current.copyWith(source: source)),
              ),
          ],
        ),
        _toggle(
          '保留首页推荐刷新',
          '刷新后新内容在前，保留最多 200 条上次内容。',
          s.keepPrevious,
          (current, value) => current.copyWith(keepPrevious: value),
        ),
        _toggle(
          '显示上次看到位置提示',
          '在本次新推荐与保留内容之间显示提示。',
          s.showPreviousMarker,
          (current, value) => current.copyWith(showPreviousMarker: value),
          enabled: s.keepPrevious,
        ),
        const Divider(),
        _threshold(
          'like-ratio',
          '最低点赞率',
          s.minimumLikeRatio,
          RecommendationSettings.likeRatios,
          '%',
          RecommendationSettings.maximumLikeRatio,
          (current, value) => current.copyWith(minimumLikeRatio: value),
        ),
        const Text(
          '用于推荐、热门、排行、分区及启用过滤的相关视频；未提供点赞数或播放量时不按点赞率过滤。',
          style: TextStyle(fontSize: 12),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('标题关键词过滤'),
          subtitle: Text(
            s.titleKeywords.isEmpty ? '未设置' : s.titleKeywords.join('、'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editKeywords(false),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('分区关键词过滤'),
          subtitle: Text(
            s.categoryKeywords.isEmpty
                ? '未设置；仅过滤提供分区名称的视频'
                : s.categoryKeywords.join('、'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editKeywords(true),
        ),
        _threshold(
          'duration',
          '最短视频时长',
          s.minimumDurationSeconds,
          RecommendationSettings.durations,
          ' 秒',
          RecommendationSettings.maximumDurationSeconds,
          (current, value) => current.copyWith(minimumDurationSeconds: value),
        ),
        const Text(
          '仅用于推荐及启用过滤的相关视频；未知时长不参与过滤。',
          style: TextStyle(fontSize: 12),
        ),
        _threshold(
          'play-count',
          '最低播放量',
          s.minimumPlayCount,
          RecommendationSettings.playCounts,
          '',
          RecommendationSettings.maximumPlayCount,
          (current, value) => current.copyWith(minimumPlayCount: value),
        ),
        _toggle(
          '已关注 UP 豁免推荐过滤',
          '首页推荐明确标注已关注的 UP 主时，保留其视频；其他列表仍按规则过滤。',
          s.exemptFollowed,
          (current, value) => current.copyWith(exemptFollowed: value),
        ),
        _toggle(
          '过滤器也应用于详情页相关视频',
          '只影响相关视频列表；搜索、动态、历史、收藏和下载保留原内容。',
          s.filterRelated,
          (current, value) => current.copyWith(filterRelated: value),
        ),
        const Text(
          '修改过滤条件立即筛选已加载的视频，无需重新获取。关键词按普通文本匹配，忽略大小写。',
          style: TextStyle(fontSize: 12),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                _save((_) => const RecommendationSettings.defaults()),
            child: const Text('恢复推荐流默认设置'),
          ),
        ),
      ],
    );
  }
}

final class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.value,
    required this.suffix,
    required this.maximum,
  });
  final String title, suffix;
  final int value, maximum;
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

final class _NumberDialogState extends State<_NumberDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: '${widget.value}');
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('自定义${widget.title}'),
    content: SizedBox(
      width: 360,
      child: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('recommendation-custom-threshold'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: widget.maximum.toString().length,
          decoration: InputDecoration(
            suffixText: widget.suffix,
            helperText: '0 表示不限，最大 ${widget.maximum}',
          ),
          validator: (text) {
            final value = int.tryParse(text ?? '');
            return value == null || value < 0 || value > widget.maximum
                ? '请输入 0 到 ${widget.maximum} 的整数'
                : null;
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(_controller.text);
          if (_form.currentState?.validate() == true && value != null) {
            Navigator.of(context).pop(value);
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

final class _KeywordDialog extends StatefulWidget {
  const _KeywordDialog({required this.category, required this.words});
  final bool category;
  final List<String> words;
  @override
  State<_KeywordDialog> createState() => _KeywordDialogState();
}

final class _KeywordDialogState extends State<_KeywordDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.words.join('\n'));
  List<String> _words(String text) => text
      .split('\n')
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toSet()
      .toList();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.category ? '分区关键词过滤' : '标题关键词过滤'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('recommendation-keywords'),
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          maxLength:
              RecommendationSettings.maximumKeywords *
              (RecommendationSettings.maximumKeywordLength + 1),
          decoration: const InputDecoration(
            helperText: '每行一个普通文本关键词，最多 32 个\n每个最多 64 字符；清空后关闭此项过滤',
            helperMaxLines: 3,
          ),
          validator: (text) {
            final words = _words(text ?? '');
            if (words.length > RecommendationSettings.maximumKeywords) {
              return '最多设置 32 个关键词';
            }
            if (words.any(
              (word) =>
                  word.length > RecommendationSettings.maximumKeywordLength,
            )) {
              return '每个关键词最多 64 字符';
            }
            return null;
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() == true) {
            Navigator.of(context).pop(_words(_controller.text));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
