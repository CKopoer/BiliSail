import 'package:flutter/material.dart';

import 'system_font_picker.dart';

import '../../features/settings/domain/app_settings.dart';

/// Shared editor for global settings and the in-player dialog.
final class DanmakuSettingsControls extends StatefulWidget {
  const DanmakuSettingsControls({
    super.key,
    required this.settings,
    required this.save,
  });
  final AppSettings settings;
  final Future<void> Function(AppSettings Function(AppSettings)) save;
  @override
  State<DanmakuSettingsControls> createState() =>
      _DanmakuSettingsControlsState();
}

final class _DanmakuSettingsControlsState
    extends State<DanmakuSettingsControls> {
  final _word = TextEditingController();
  late final _offset = TextEditingController(
    text: _seconds(widget.settings.danmakuOffset),
  );
  final _offsetFocus = FocusNode();
  String? _error;

  static String _seconds(Duration value) =>
      (value.inMilliseconds / 1000).toString();
  @override
  void didUpdateWidget(covariant DanmakuSettingsControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_offsetFocus.hasFocus) {
      _offset.text = _seconds(widget.settings.danmakuOffset);
    }
  }

  @override
  void dispose() {
    _word.dispose();
    _offset.dispose();
    _offsetFocus.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings Function(AppSettings) change) async {
    try {
      await widget.save(change);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = '设置保存失败，请重试');
    }
  }

  Widget _toggle(
    String title,
    bool value,
    AppSettings Function(AppSettings, bool) change,
  ) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: (v) => _save((s) => change(s, v)),
  );

  Widget _slider(
    String title,
    String key,
    double value,
    double min,
    double max,
    AppSettings Function(AppSettings, double) change, {
    int? divisions,
    String suffix = '',
  }) => _DanmakuSlider(
    key: ValueKey(key),
    title: title,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    suffix: suffix,
    save: (v) => _save((s) => change(s, v)),
  );

  Widget _choice<T>(
    String title,
    String key,
    T value,
    Map<T, String> choices,
    AppSettings Function(AppSettings, T) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      DropdownButton<T>(
        key: ValueKey(key),
        isExpanded: true,
        value: value,
        items: [
          for (final e in choices.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) _save((s) => change(s, v));
        },
      ),
    ],
  );

  Future<void> _setOffset() async {
    final seconds = double.tryParse(_offset.text.trim());
    if (seconds == null || !seconds.isFinite || seconds < -60 || seconds > 60) {
      setState(() => _error = '弹幕偏移请输入 -60 到 60 秒');
      return;
    }
    _offsetFocus.unfocus();
    await _save(
      (s) => s.copyWith(
        danmakuOffset: Duration(milliseconds: (seconds * 1000).round()),
      ),
    );
    if (mounted) _offset.text = _seconds(widget.settings.danmakuOffset);
  }

  Future<void> _adjustOffset(Duration delta, {bool reset = false}) async {
    _offsetFocus.unfocus();
    await _save(
      (s) => s.copyWith(
        danmakuOffset: reset ? Duration.zero : s.danmakuOffset + delta,
      ),
    );
    if (mounted) _offset.text = _seconds(widget.settings.danmakuOffset);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toggle(
          '显示弹幕',
          s.danmakuEnabled,
          (s, v) => s.copyWith(danmakuEnabled: v),
        ),
        _toggle(
          '隐藏滚动弹幕',
          !s.danmakuScrollEnabled,
          (s, v) => s.copyWith(danmakuScrollEnabled: !v),
        ),
        _slider(
          '显示区域',
          'danmaku-area',
          s.danmakuArea,
          .25,
          1,
          (s, v) => s.copyWith(danmakuArea: v),
        ),
        _slider(
          '字号缩放',
          'danmaku-font-scale',
          s.danmakuFontScale,
          .7,
          1.5,
          (s, v) => s.copyWith(danmakuFontScale: v),
          suffix: '×',
        ),
        _slider(
          '滚动速度',
          'danmaku-speed',
          s.danmakuSpeed,
          .5,
          2,
          (s, v) => s.copyWith(danmakuSpeed: v),
          suffix: '×',
        ),
        _slider(
          '弹幕行距',
          'danmaku-line-spacing',
          s.danmakuLineSpacing,
          0,
          100,
          (s, v) => s.copyWith(danmakuLineSpacing: v),
          divisions: 100,
          suffix: ' px',
        ),
        const Text('上一行文字底部到下一行文字顶部的距离，0 时两行紧挨着。'),
        _slider(
          '不透明度',
          'danmaku-opacity',
          s.danmakuOpacity,
          .2,
          1,
          (s, v) => s.copyWith(danmakuOpacity: v),
        ),
        _slider(
          '顶部距离',
          'danmaku-top-margin',
          s.danmakuTopMargin,
          0,
          200,
          (s, v) => s.copyWith(danmakuTopMargin: v),
          divisions: 50,
          suffix: ' px',
        ),
        _slider(
          '同屏密度（0 为不限）',
          'danmaku-on-screen',
          s.danmakuMaxOnScreen.toDouble(),
          0,
          120,
          (s, v) => s.copyWith(danmakuMaxOnScreen: v.round()),
          divisions: 120,
          suffix: ' 条',
        ),
        _slider(
          '每秒最大数量（0 为不限）',
          'danmaku-density',
          s.danmakuMaxPerSecond.toDouble(),
          0,
          100,
          (s, v) => s.copyWith(danmakuMaxPerSecond: v.round()),
          divisions: 100,
          suffix: ' 条',
        ),
        _choice('弹幕字体', 'danmaku-font', s.danmakuFont, {
          DanmakuFontPreference.system: '系统默认',
          DanmakuFontPreference.harmonyOsSans: 'HarmonyOS Sans',
          DanmakuFontPreference.alibabaPuHuiTi: '阿里巴巴普惠体 3.0',
          if (s.danmakuFont == DanmakuFontPreference.installed)
            DanmakuFontPreference.installed:
                '系统字体：${s.danmakuSystemFontFamily}',
        }, (s, v) => s.copyWith(danmakuFont: v)),
        SystemFontPicker(
          family: s.danmakuFont == DanmakuFontPreference.installed
              ? s.danmakuSystemFontFamily
              : null,
          onSelected: (family) => _save(
            (s) => s.copyWith(
              danmakuFont: DanmakuFontPreference.installed,
              danmakuSystemFontFamily: family,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('弹幕偏移（秒）'),
        const Text('正数延后，负数提前；直播仅支持延后', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('danmaku-offset'),
          controller: _offset,
          focusNode: _offsetFocus,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onSubmitted: (_) => _setOffset(),
          decoration: InputDecoration(
            isDense: true,
            suffixText: '秒',
            suffixIcon: IconButton(
              tooltip: '应用弹幕偏移',
              onPressed: _setOffset,
              icon: const Icon(Icons.check),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _adjustOffset(const Duration(seconds: -1)),
              child: const Text('-1 秒'),
            ),
            TextButton(
              onPressed: () => _adjustOffset(const Duration(seconds: 1)),
              child: const Text('+1 秒'),
            ),
            TextButton(
              onPressed: () => _adjustOffset(Duration.zero, reset: true),
              child: const Text('重置偏移'),
            ),
          ],
        ),
        _toggle('字体加粗', s.danmakuBold, (s, v) => s.copyWith(danmakuBold: v)),
        _choice('弹幕样式', 'danmaku-style', s.danmakuStyle, const {
          DanmakuStylePreference.shadow: '阴影',
          DanmakuStylePreference.stroke: '描边',
          DanmakuStylePreference.plain: '无效果',
        }, (s, v) => s.copyWith(danmakuStyle: v)),
        _toggle(
          '合并重复弹幕',
          s.danmakuMergeDuplicates,
          (s, v) => s.copyWith(danmakuMergeDuplicates: v),
        ),
        _slider(
          '屏蔽等级（0 为不屏蔽，仅点播）',
          'danmaku-weight',
          s.danmakuMinimumWeight.toDouble(),
          0,
          10,
          (s, v) => s.copyWith(danmakuMinimumWeight: v.round()),
          divisions: 10,
          suffix: ' 级',
        ),
        _toggle(
          '屏蔽彩色弹幕',
          s.danmakuBlockColored,
          (s, v) => s.copyWith(danmakuBlockColored: v),
        ),
        _toggle(
          '顶部弹幕',
          s.danmakuTopEnabled,
          (s, v) => s.copyWith(danmakuTopEnabled: v),
        ),
        _toggle(
          '底部弹幕',
          s.danmakuBottomEnabled,
          (s, v) => s.copyWith(danmakuBottomEnabled: v),
        ),
        const Text('关键词屏蔽（最多 200 项，每项 100 字）'),
        TextField(
          key: const ValueKey('danmaku-blocked-word'),
          controller: _word,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '输入要屏蔽的关键词'),
        ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('添加关键词'),
          onPressed: () async {
            final word = _word.text.trim();
            if (word.isEmpty) return;
            await _save(
              (s) => s.copyWith(
                danmakuBlockedWords: [...s.danmakuBlockedWords, word],
              ),
            );
            if (mounted && _error == null) _word.clear();
          },
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final word in s.danmakuBlockedWords)
              InputChip(
                label: Text(word),
                onDeleted: () => _save(
                  (s) => s.copyWith(
                    danmakuBlockedWords: s.danmakuBlockedWords
                        .where((v) => v != word)
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
        if (_error != null)
          Text(
            _error ?? '',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

final class _DanmakuSlider extends StatefulWidget {
  const _DanmakuSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.save,
    required this.suffix,
    this.divisions,
  });
  final String title, suffix;
  final double value, min, max;
  final int? divisions;
  final Future<void> Function(double) save;
  @override
  State<_DanmakuSlider> createState() => _DanmakuSliderState();
}

final class _DanmakuSliderState extends State<_DanmakuSlider> {
  double? _draft;
  @override
  Widget build(BuildContext context) {
    final value = (_draft ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '${widget.title}  ${value.toStringAsFixed(widget.max > 3 ? 0 : 2)}${widget.suffix}',
          ),
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          divisions:
              widget.divisions ?? ((widget.max - widget.min) * 20).round(),
          onChanged: (v) => setState(() => _draft = v),
          onChangeEnd: (v) async {
            await widget.save(v);
            if (mounted) setState(() => _draft = null);
          },
        ),
      ],
    );
  }
}
