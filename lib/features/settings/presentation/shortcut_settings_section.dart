import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/input/input_stroke.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/presentation/input_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_notice.dart';

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
  Future<void> _save(BuildContext context, ShortcutSettings value) async {
    try {
      await save(value);
    } catch (_) {
      if (context.mounted) showAppNotice(context, '设置保存失败，请重试');
    }
  }

  Future<void> _edit(BuildContext context, ShortcutAction action) async {
    await showDialog<ShortcutSettings>(
      context: context,
      builder: (_) =>
          _ShortcutEditor(settings: settings, action: action, save: save),
    );
    // The editor persists before closing so a failed write retains its draft.
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
          onChanged: (value) =>
              _save(context, settings.withActionEnabled(action, value)),
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
        subtitle: const Text(
          '仅控制当前活动页。输入时保留编辑；明确绑定的侧键或 Ctrl / Meta 关闭组合仍可关闭标签。弹窗隔离底层；固定标签循环和图片操作不受总开关影响。',
        ),
        value: settings.enabled,
        onChanged: (value) => _save(context, settings.withEnabled(value)),
      ),
      for (final issue in settings.issues) Text(issue),
      const _ShortcutDiagnostics(),
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
            _save(context, settings.withPlayback(seekSeconds: value.round())),
      ),
      _ShortcutSlider(
        label: '长按触发延迟（毫秒）',
        value: settings.holdDelayMs.toDouble(),
        min: 200,
        max: 1500,
        divisions: 26,
        save: (value) =>
            _save(context, settings.withPlayback(holdDelayMs: value.round())),
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
            if (rate != null) {
              _save(context, settings.withPlayback(holdRate: rate));
            }
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
          onPressed: () => _save(context, const ShortcutSettings.defaults()),
          child: const Text('恢复默认快捷键'),
        ),
      ),
      const Text(
        'Ctrl+Tab / Ctrl+Shift+Tab 保留用于切换标签。UWP 参考中的截图（F10）、小窗（T/F8）、重启（Alt+R）、开发模式（Ctrl+F12）尚无对应底层能力，暂未启用。下载可从视频或影视菜单进入，Ctrl+S 暂未接入。左右方向键持续步进模式尚未移植；右方向键长按采用临时倍速。',
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
  const _ShortcutEditor({
    required this.settings,
    required this.action,
    required this.save,
  });
  final Future<void> Function(ShortcutSettings) save;
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
      barrierDismissible: false,
      builder: (_) => const _ShortcutRecorder(),
    );
    if (mounted && key != null) {
      _text.text = key;
      setState(() => _error = null);
    }
  }

  Future<void> _submit() async {
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
    try {
      await widget.save(candidate);
      if (mounted) Navigator.pop(context, candidate);
    } catch (_) {
      if (mounted) setState(() => _error = '设置保存失败，请重试；当前键位尚未生效');
    }
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

class _ShortcutRecorder extends StatefulWidget {
  const _ShortcutRecorder();
  @override
  State<_ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends State<_ShortcutRecorder> {
  ShortcutDispatcher<Object>? _dispatcher;
  String? _candidate, _identity;
  FutureOr<CommandOutcome> _capture(InputStroke stroke) {
    if (stroke.phase == InputPhase.down &&
        stroke.chord != null &&
        _candidate == null) {
      _candidate = stroke.chord.toString();
      _identity = stroke.identity;
      setState(() {});
    }
    if (stroke.phase == InputPhase.up && stroke.identity == _identity) {
      Navigator.pop(context, _candidate);
    }
    return CommandOutcome.completed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dispatcher = InputScope.of<Object>(context)?.dispatcher;
    _dispatcher?.recording = _capture;
  }

  @override
  void dispose() {
    if (_dispatcher?.recording == _capture) _dispatcher?.recording = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('按下键盘或鼠标侧键'),
    content: Text(
      _candidate == null
          ? '按下键盘按键或鼠标侧键。支持 Ctrl / Alt / Shift / Meta 组合键；侧键在整个应用客户区均可录制。'
          : '已识别 $_candidate，释放按键后完成录制。',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}

class _ShortcutDiagnostics extends StatefulWidget {
  const _ShortcutDiagnostics();
  @override
  State<_ShortcutDiagnostics> createState() => _ShortcutDiagnosticsState();
}

class _ShortcutDiagnosticsState extends State<_ShortcutDiagnostics> {
  ShortcutDispatcher<Object>? _input;
  Timer? _poll;
  bool _enabled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _input = InputScope.of<Object>(context)?.dispatcher;
    if (!WorkspaceActivity.isActive(context)) _stop();
  }

  void _stop() {
    _poll?.cancel();
    _poll = null;
    _enabled = false;
    _input?.diagnosticsEnabled = false;
    _input?.diagnostics.clear();
  }

  void _toggle(bool value) {
    if (!value) {
      setState(_stop);
      return;
    }
    _enabled = true;
    _input?.diagnosticsEnabled = true;
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('快捷键诊断（本次运行）'),
        subtitle: const Text('最多保留 256 条输入与分发结果。输入框只记录保护原因，关闭后清空。'),
        value: _enabled,
        onChanged: _input == null ? null : _toggle,
      ),
      if (_enabled) ...[
        Text('已捕获 ${_input?.diagnostics.length ?? 0} 条'),
        for (final entry
            in (_input?.diagnostics.reversed.take(8) ?? <InputTrace<Object>>[]))
          Text(
            '#${entry.sequence} ${(entry.elapsedMicros ?? 0) ~/ 1000}ms ${entry.device.name} ${entry.phase.name} '
            '${entry.chord ?? "输入保护"} ${entry.fallback ? "物理回退" : "逻辑匹配"} → '
            '${entry.result.command ?? ""} ${entry.result.reason.name} '
            '${entry.result.scope?.name ?? ""} ${entry.result.ownerGeneration ?? ""}'
            '${entry.logicalKeyId == null ? "" : " logical=${entry.logicalKeyId} physical=${entry.physicalKeyId}"}'
            '${entry.buttons == null ? "" : " buttons=${entry.buttons}"}',
          ),
      ],
    ],
  );
}
