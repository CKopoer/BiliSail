import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/shortcut_settings.dart';
import '../../../core/presentation/keyboard_shortcuts.dart';
import '../../../domain/playback_rates.dart';

class ShortcutSettingsSection extends StatelessWidget {
  const ShortcutSettingsSection({
    super.key,
    required this.settings,
    required this.save,
  });
  final ShortcutSettings settings;
  final Future<void> Function(ShortcutSettings) save;
  Future<void> _edit(BuildContext context, ShortcutAction action) async {
    final result = await showDialog<ShortcutSettings>(
      context: context,
      builder: (_) => _ShortcutEditor(settings: settings, action: action),
    );
    if (result != null) await save(result);
  }

  Widget _binding(BuildContext context, ShortcutAction action) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(action.label),
    subtitle: Text(
      settings.keysFor(action).isEmpty
          ? '未绑定'
          : settings.keysFor(action).map(shortcutLabel).join(' / '),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '编辑快捷键',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _edit(context, action),
        ),
        Switch(
          value: settings.isEnabled(action),
          onChanged: (value) => save(settings.withActionEnabled(action, value)),
        ),
      ],
    ),
    onTap: () => _edit(context, action),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('启用快捷键'),
        subtitle: const Text('文本输入和弹窗期间不触发；播放快捷键仅作用于当前播放器。'),
        value: settings.enabled,
        onChanged: (value) => save(settings.withEnabled(value)),
      ),
      const ListTile(contentPadding: EdgeInsets.zero, title: Text('标签页与页面')),
      for (final action in [
        ShortcutAction.closeTab,
        ShortcutAction.newTab,
        ShortcutAction.refresh,
      ])
        _binding(context, action),
      const ListTile(contentPadding: EdgeInsets.zero, title: Text('播放控制')),
      _ShortcutSlider(
        label: '前进 / 后退步长（秒）',
        value: settings.seekSeconds.toDouble(),
        min: 1,
        max: 90,
        divisions: 89,
        save: (value) =>
            save(settings.withPlayback(seekSeconds: value.round())),
      ),
      _ShortcutSlider(
        label: '长按触发延迟（毫秒）',
        value: settings.holdDelayMs.toDouble(),
        min: 200,
        max: 1500,
        divisions: 26,
        save: (value) =>
            save(settings.withPlayback(holdDelayMs: value.round())),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('长按临时倍速'),
        trailing: DropdownButton<double>(
          value: settings.holdRate,
          items: [
            for (final rate in PlaybackRates.values.where((rate) => rate > 1))
              DropdownMenuItem(value: rate, child: Text('${rate}x')),
          ],
          onChanged: (rate) {
            if (rate != null) save(settings.withPlayback(holdRate: rate));
          },
        ),
      ),
      for (final action in ShortcutAction.values.where(
        (action) => ![
          ShortcutAction.closeTab,
          ShortcutAction.newTab,
          ShortcutAction.refresh,
        ].contains(action),
      ))
        _binding(context, action),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => save(const ShortcutSettings.defaults()),
          child: const Text('恢复默认快捷键'),
        ),
      ),
      const Text(
        'Ctrl+Tab / Ctrl+Shift+Tab 保留用于切换标签。UWP 参考中的截图（F10）、小窗（T/F8）、下载（Ctrl+S）、重启（Alt+R）、开发模式（Ctrl+F12）尚无对应底层能力，暂未启用。左右方向键持续步进模式尚未移植；右方向键长按采用临时倍速。',
      ),
    ],
  );
}

class _ShortcutSlider extends StatefulWidget {
  const _ShortcutSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.save,
  });
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> save;
  @override
  State<_ShortcutSlider> createState() => _ShortcutSliderState();
}

class _ShortcutSliderState extends State<_ShortcutSlider> {
  double? _drag;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${widget.label}：${(_drag ?? widget.value).toStringAsFixed(widget.max <= 3 ? 2 : 0)}',
      ),
      Slider(
        value: _drag ?? widget.value,
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChanged: (value) => setState(() => _drag = value),
        onChangeEnd: (value) {
          setState(() => _drag = null);
          widget.save(value);
        },
      ),
    ],
  );
}

class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({required this.settings, required this.action});
  final ShortcutSettings settings;
  final ShortcutAction action;
  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.settings.keysFor(widget.action).join(', '),
  );
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('按下键盘或鼠标侧键'),
        content: MouseShortcutListener(
          onShortcut: (key) {
            Navigator.pop(context, key);
            return true;
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.handled;
              final key = ShortcutSettings.canonicalKey(
                shortcutKey(event) ?? '',
              );
              if (key != null) Navigator.pop(context, key);
              return KeyEventResult.handled;
            },
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '按下键盘按键，或将鼠标移到此处点击侧键。支持 Ctrl / Alt / Shift / Meta 组合键。',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mounted && key != null) {
      _text.text = key;
      setState(() => _error = null);
    }
  }

  void _submit() {
    final raw = _text.text
        .split(',')
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty);
    final parsed = raw.map(ShortcutSettings.canonicalKey).toList();
    if (parsed.any((key) => key == null)) {
      setState(
        () => _error = '键名无效，例如 Space、Ctrl+K、MouseBack、Ctrl+MouseForward',
      );
      return;
    }
    final candidate = widget.settings.withKeys(
      widget.action,
      parsed.whereType<String>().toSet().toList(),
    );
    if (candidate.conflict != null) {
      setState(() => _error = candidate.conflict);
      return;
    }
    Navigator.pop(context, candidate);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.action.label),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入键名，以逗号分隔多个键位；留空解除绑定。鼠标侧键为 MouseBack / MouseForward，也可使用录制按钮。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '快捷键',
                hintText: '例如 Ctrl+W, MouseBack',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            TextButton.icon(
              onPressed: _record,
              icon: const Icon(Icons.keyboard),
              label: const Text('录制组合键'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
