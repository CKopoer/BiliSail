import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final class DanmakuSendStyleButton extends StatelessWidget {
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
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: style,
    builder: (context, value, _) => PopupMenuButton<({int mode, int color})>(
      tooltip: '发送弹幕样式',
      enabled: enabled,
      icon: Icon(
        Icons.text_fields,
        size: 18,
        color: Color(0xff000000 | value.color),
      ),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final (mode, label) in const [(1, '滚动'), (5, '顶部'), (4, '底部')])
          PopupMenuItem(
            value: (mode: mode, color: value.color),
            child: Text('${value.mode == mode ? '✓ ' : ''}$label'),
          ),
        for (final (color, label) in const [
          (0xffffff, '白色'),
          (0xff6699, '粉色'),
          (0xffd700, '金色'),
          (0x00a1d6, '蓝色'),
        ])
          PopupMenuItem(
            value: (mode: value.mode, color: color),
            child: Text('${value.color == color ? '✓ ' : ''}$label'),
          ),
      ],
    ),
  );
}
