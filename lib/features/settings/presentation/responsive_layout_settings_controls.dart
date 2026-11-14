import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/responsive_layout_settings.dart';
import '../../../shared/ui/app_dialog.dart';
import 'video_grid_breakpoint_editor.dart';

class ResponsiveLayoutSettingsControls extends StatelessWidget {
  const ResponsiveLayoutSettingsControls({
    super.key,
    required this.settings,
    required this.onVideoGridChanged,
    required this.onSidebarChanged,
    required this.onPlaybackChanged,
  });

  final ResponsiveLayoutSettings settings;
  final Future<void> Function(List<int>?) onVideoGridChanged;
  final Future<void> Function(int) onSidebarChanged;
  final Future<void> Function(int) onPlaybackChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('视频卡片列数阈值'),
        subtitle: Text(
          settings.videoGridMinWidths == null
              ? '默认规则：2 列 300、3 列 492、4 列 1100 起'
              : '自定义：2 列 ${settings.videoGridMinWidths?[0]}、'
                    '3 列 ${settings.videoGridMinWidths?[1]}、'
                    '4 列 ${settings.videoGridMinWidths?[2]} 起',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppDialog<void>(
          context: context,
          builder: (_) => _BreakpointDialog(
            title: '视频卡片列数阈值',
            description:
                '拖动滑块设置进入 2–12 列的最小宽度，以扣除侧栏和边距后的网格宽度为准。'
                '首页、搜索和历史同步生效；放大标题字号时阈值同比提高，恢复默认则沿用原有规则。',
            labels: [
              for (var columns = 2; columns <= 12; columns++) '$columns 列起',
            ],
            initial:
                settings.videoGridMinWidths ??
                ResponsiveLayoutSettings.defaultVideoGridMinWidths,
            defaults: ResponsiveLayoutSettings.defaultVideoGridMinWidths,
            useDefaultRules: settings.videoGridMinWidths == null,
            grid: true,
            onSave: onVideoGridChanged,
          ),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('侧栏展开阈值'),
        subtitle: Text(
          '${settings.sidebarExpandedWidth} 逻辑像素；侧栏样式选择“随窗口宽度”时生效',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppDialog<void>(
          context: context,
          builder: (_) => _BreakpointDialog(
            title: '侧栏展开阈值',
            description: '安全区内窗口宽度达到此值时展开完整侧栏。底栏／侧栏的切换规则及手动侧栏样式保持原设置。',
            labels: const ['展开宽度'],
            initial: [settings.sidebarExpandedWidth],
            defaults: const [1600],
            onSave: (values) => onSidebarChanged(values?.first ?? 1600),
          ),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('播放页左右布局阈值'),
        subtitle: Text('${settings.playbackSideBySideWidth} 逻辑像素；视频和影视播放页共用'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppDialog<void>(
          context: context,
          builder: (_) => _BreakpointDialog(
            title: '播放页左右布局阈值',
            description: '播放页自身可用宽度达到此值时使用左右布局，否则使用上下布局。右侧信息区保持 380 逻辑像素宽。',
            labels: const ['左右布局宽度'],
            initial: [settings.playbackSideBySideWidth],
            defaults: const [1000],
            onSave: (values) => onPlaybackChanged(values?.first ?? 1000),
          ),
        ),
      ),
    ],
  );
}

class _BreakpointDialog extends StatefulWidget {
  const _BreakpointDialog({
    required this.title,
    required this.description,
    required this.labels,
    required this.initial,
    required this.defaults,
    required this.onSave,
    this.grid = false,
    this.useDefaultRules = false,
  });

  final String title, description;
  final List<String> labels;
  final List<int> initial, defaults;
  final bool grid, useDefaultRules;
  final Future<void> Function(List<int>?) onSave;

  @override
  State<_BreakpointDialog> createState() => _BreakpointDialogState();
}

class _BreakpointDialogState extends State<_BreakpointDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = [
    if (!widget.grid)
      for (final value in widget.initial) TextEditingController(text: '$value'),
  ];
  late List<int> _gridValues = [...widget.initial];
  var _gridResetRevision = 0;
  late bool _useDefaultRules = widget.useDefaultRules;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final values = widget.grid
        ? _gridValues
        : [for (final controller in _controllers) int.parse(controller.text)];
    if (widget.grid && !ResponsiveLayoutSettings.validVideoGridWidths(values)) {
      setState(() => _error = '列数越多，切换阈值必须越大');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.grid && _useDefaultRules ? null : values);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: widget.grid ? 560 : 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.description),
              const SizedBox(height: 16),
              if (widget.grid)
                IgnorePointer(
                  ignoring: _saving,
                  child: ExcludeFocus(
                    excluding: _saving,
                    child: VideoGridBreakpointEditor(
                      key: ValueKey(_gridResetRevision),
                      values: _gridValues,
                      onChanged: (values) => setState(() {
                        _gridValues = values;
                        _useDefaultRules = false;
                        _error = null;
                      }),
                    ),
                  ),
                ),
              for (var i = 0; i < _controllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    key: ValueKey('layout-breakpoint-$i'),
                    controller: _controllers[i],
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: widget.labels[i],
                      suffixText: '逻辑像素',
                      helperText:
                          '范围 ${widget.grid ? 200 : 600}–${widget.grid ? 12000 : 6000}',
                    ),
                    onChanged: (_) => setState(() {
                      _useDefaultRules = false;
                      _error = null;
                    }),
                    validator: (text) {
                      final value = int.tryParse(text ?? '');
                      final minimum = widget.grid ? 200 : 600;
                      final maximum = widget.grid ? 12000 : 6000;
                      return value == null || value < minimum || value > maximum
                          ? '请输入 $minimum–$maximum 之间的整数'
                          : null;
                    },
                  ),
                ),
              if (_error case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                  _form.currentState?.reset();
                  _gridValues = [...widget.defaults];
                  _gridResetRevision++;
                  for (var i = 0; i < _controllers.length; i++) {
                    _controllers[i].text = '${widget.defaults[i]}';
                  }
                  _useDefaultRules = true;
                  _error = null;
                }),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
