import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';
import 'danmaku_send_style_panel.dart';

final class DanmakuSendStyleButton extends StatefulWidget {
  const DanmakuSendStyleButton({
    super.key,
    required this.style,
    required this.onChanged,
    this.enabled = true,
  });

  final ValueListenable<({int mode, int color})> style;
  final ValueChanged<({int mode, int color})> onChanged;
  final bool enabled;

  @override
  State<DanmakuSendStyleButton> createState() => _DanmakuSendStyleButtonState();
}

final class _DanmakuSendStyleButtonState extends State<DanmakuSendStyleButton> {
  bool _open = false;

  Future<void> _show() async {
    if (_open || !widget.enabled) return;
    setState(() => _open = true);
    try {
      final result = await showAppDialog<({int mode, int color})>(
        context: context,
        builder: (context) {
          final compact = MediaQuery.sizeOf(context).width < 600;
          return Dialog(
            alignment: compact ? Alignment.bottomCenter : Alignment.center,
            insetPadding: EdgeInsets.all(compact ? 12 : 24),
            constraints: const BoxConstraints(maxWidth: 440),
            clipBehavior: Clip.antiAlias,
            child: DanmakuSendStylePanel(
              initialStyle: widget.style.value,
              onApply: (value) => Navigator.of(context).pop(value),
              onCancel: () => Navigator.of(context).pop(),
            ),
          );
        },
      );
      if (mounted && widget.enabled && result != null) widget.onChanged(result);
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.style,
    builder: (context, value, _) => Semantics(
      value:
          '${switch (value.mode) {
            4 => '底部',
            5 => '顶部',
            _ => '滚动',
          }}，#${value.color.toRadixString(16).padLeft(6, '0').toUpperCase()}',
      child: IconButton(
        tooltip: '发送弹幕样式',
        onPressed: widget.enabled && !_open ? _show : null,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: const EdgeInsets.all(10),
        icon: SizedBox.square(
          dimension: 24,
          child: Stack(
            children: [
              const Icon(Icons.text_fields, size: 20),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xff000000 | value.color),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
