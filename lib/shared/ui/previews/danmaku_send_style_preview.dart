import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../danmaku_send_style_panel.dart';

@Preview(name: '手机', group: '弹幕发送', size: Size(360, 720))
@Preview(name: '桌面', group: '弹幕发送', size: Size(480, 600))
@Preview(name: '大字号', group: '弹幕发送', size: Size(320, 600), textScaleFactor: 2)
Widget danmakuSendStylePreview() => MaterialApp(
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Material(
          child: DanmakuSendStylePanel(
            initialStyle: (mode: 1, color: 0xff6699),
            onApply: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  ),
);
