import 'package:flutter/material.dart';

import '../../domain/playback_rates.dart';
import 'app_dialog.dart';

class PlaybackRateOptionsSetting extends StatefulWidget {
  const PlaybackRateOptionsSetting({
    super.key,
    required this.rates,
    required this.onChanged,
  });

  final List<double> rates;
  final Future<void> Function(List<double>) onChanged;

  @override
  State<PlaybackRateOptionsSetting> createState() =>
      _PlaybackRateOptionsSettingState();
}

class _PlaybackRateOptionsSettingState
    extends State<PlaybackRateOptionsSetting> {
  bool _saving = false;
  String? _error;

  Future<void> _save(List<double> rates) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onChanged(rates);
    } catch (_) {
      if (mounted) setState(() => _error = '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    final rate = await showAppDialog<double>(
      context: context,
      builder: (_) => _AddPlaybackRateDialog(rates: widget.rates),
    );
    if (!mounted || rate == null || _saving) return;
    if (widget.rates.contains(rate) ||
        widget.rates.length >= PlaybackRates.maxOptions) {
      return;
    }
    await _save([...widget.rates, rate]);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('倍速选项（${widget.rates.length}/${PlaybackRates.maxOptions}）'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final rate in widget.rates)
              InputChip(
                label: Text('${rate}x'),
                avatar: PlaybackRates.requiredValues.contains(rate)
                    ? const Icon(Icons.lock_outline, size: 16)
                    : null,
                deleteButtonTooltipMessage: '删除 ${rate}x',
                onDeleted:
                    _saving || PlaybackRates.requiredValues.contains(rate)
                    ? null
                    : () => _save([
                        for (final value in widget.rates)
                          if (value != rate) value,
                      ]),
              ),
            OutlinedButton.icon(
              onPressed:
                  _saving || widget.rates.length >= PlaybackRates.maxOptions
                  ? null
                  : _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加倍速'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '最多 9 项，0.5x、1.0x、2.0x 固定保留。删除默认倍速后回到 1.0x。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error case final error?)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}

class _AddPlaybackRateDialog extends StatefulWidget {
  const _AddPlaybackRateDialog({required this.rates});
  final List<double> rates;

  @override
  State<_AddPlaybackRateDialog> createState() => _AddPlaybackRateDialogState();
}

class _AddPlaybackRateDialogState extends State<_AddPlaybackRateDialog> {
  final _form = GlobalKey<FormState>();
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String? _validate(String? text) {
    final value = text?.trim() ?? '';
    final rate = double.tryParse(value);
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value) ||
        rate == null ||
        !PlaybackRates.isValid(rate)) {
      return '请输入 0.25～5.0，最多两位小数';
    }
    if (widget.rates.contains(rate)) return '该倍速已存在';
    return null;
  }

  void _submit() {
    if (_form.currentState?.validate() == true) {
      Navigator.of(context).pop(double.parse(_input.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加倍速'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '播放倍速',
            hintText: '例如 1.75',
            suffixText: 'x',
            helperText: '0.25～5.0，最多两位小数',
            errorMaxLines: 2,
          ),
          validator: _validate,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('添加')),
    ],
  );
}
