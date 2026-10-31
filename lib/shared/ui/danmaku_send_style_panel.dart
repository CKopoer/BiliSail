import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Ordinary RGB presets from the reference palette; retain the original three
// non-white choices so existing session selections remain directly available.
const _colors = [
  (0xffffff, '白色'),
  (0xfe0302, '红色'),
  (0xff7204, '橙色'),
  (0xffaa02, '琥珀色'),
  (0xffd302, '金黄色'),
  (0xffff00, '黄色'),
  (0xa0ee00, '黄绿色'),
  (0x00cd00, '绿色'),
  (0x019899, '青色'),
  (0x4266be, '靛蓝色'),
  (0x89d5ff, '浅蓝色'),
  (0xcc0273, '玫红色'),
  (0x222222, '深灰色'),
  (0x9b9b9b, '灰色'),
  (0xff6699, '粉色'),
  (0xffd700, '金色'),
  (0x00a1d6, '蓝色'),
];
const _modes = [(1, '滚动'), (5, '顶部'), (4, '底部')];

final class DanmakuSendStylePanel extends StatefulWidget {
  const DanmakuSendStylePanel({
    super.key,
    required this.initialStyle,
    required this.onApply,
    required this.onCancel,
  });
  final ({int mode, int color}) initialStyle;
  final ValueChanged<({int mode, int color})> onApply;
  final VoidCallback onCancel;
  @override
  State<DanmakuSendStylePanel> createState() => _DanmakuSendStylePanelState();
}

final class _DanmakuSendStylePanelState extends State<DanmakuSendStylePanel> {
  late int _mode = widget.initialStyle.mode;
  late int _color = widget.initialStyle.color;
  late bool _custom = !_colors.any((entry) => entry.$1 == _color);
  late final _hex = TextEditingController(text: _hexValue);
  bool _valid = true;
  String get _hexValue =>
      _color.toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(int color) {
    setState(() {
      _color = color;
      _valid = true;
      _hex.value = TextEditingValue(
        text: _hexValue,
        selection: TextSelection.collapsed(offset: 6),
      );
    });
  }

  void _apply() {
    if (_valid) widget.onApply((mode: _mode, color: _color));
  }

  Widget _swatch(int rgb, String label) {
    final color = Color(0xff000000 | rgb);
    final selected = _color == rgb;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label，#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
      selected: selected,
      button: true,
      onTap: () => _setColor(rgb),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          excludeFromSemantics: true,
          key: ValueKey(
            'danmaku-send-color-${rgb.toRadixString(16).padLeft(6, '0')}',
          ),
          onTap: () => _setColor(rgb),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: color.computeLuminance() > .45
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _channel(String label, String name, int shift) {
    final value = (_color >> shift) & 0xff;
    return Row(
      children: [
        Text(label),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            key: ValueKey('danmaku-send-$label'),
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            semanticFormatterCallback: (value) => '$name ${value.round()}',
            onChanged: (value) => _setColor(
              (_color & ~(0xff << shift)) | (value.round() << shift),
            ),
          ),
        ),
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(14) * 2,
          child: Text('$value', textAlign: TextAlign.end),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modeLabel = _modes.firstWhere((entry) => entry.$1 == _mode).$2;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('发送弹幕样式', style: theme.textTheme.titleLarge),
              ),
              IconButton(
                tooltip: '关闭样式面板',
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('弹幕位置', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (mode, label) in _modes)
                ChoiceChip(
                  label: Text(label),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('弹幕颜色', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (color, label) in _colors) _swatch(color, label),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              if (_custom && !_valid) _setColor(_color);
              setState(() => _custom = !_custom);
            },
            icon: Icon(_custom ? Icons.expand_less : Icons.tune),
            label: const Text('自定义颜色'),
          ),
          if (_custom) ...[
            TextField(
              key: const ValueKey('danmaku-send-hex'),
              controller: _hex,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: '颜色代码',
                prefixText: '#',
                hintText: 'RRGGBB',
                errorText: _valid ? null : '请输入完整的 6 位颜色代码',
              ),
              onChanged: (value) => setState(() {
                final parsed = value.length == 6
                    ? int.tryParse(value, radix: 16)
                    : null;
                _valid = parsed != null;
                if (parsed != null) _color = parsed;
              }),
              onSubmitted: (_) => _apply(),
            ),
            _channel('R', '红色', 16),
            _channel('G', '绿色', 8),
            _channel('B', '蓝色', 0),
          ],
          const SizedBox(height: 8),
          Text(
            '预览 · $modeLabel · #$_hexValue',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                for (final background in [
                  const Color(0xff171b24),
                  const Color(0xfff0f2f5),
                ])
                  Expanded(
                    child: ColoredBox(
                      color: background,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: Text(
                          '弹幕预览',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Color(0xff000000 | _color),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OverflowBar(
            spacing: 8,
            overflowSpacing: 8,
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: widget.onCancel, child: const Text('取消')),
              FilledButton(
                onPressed: _valid ? _apply : null,
                child: const Text('完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
