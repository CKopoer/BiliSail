import 'package:flutter/material.dart';

class PlayerDanmakuDialog extends StatelessWidget {
  const PlayerDanmakuDialog({super.key, required this.composer});

  final Widget composer;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      key: const ValueKey('player-danmaku-dialog'),
      alignment: narrow ? Alignment.bottomCenter : Alignment.center,
      insetPadding: EdgeInsets.all(narrow ? 12 : 24),
      constraints: const BoxConstraints(maxWidth: 560),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '发送弹幕',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭发送窗口',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            composer,
          ],
        ),
      ),
    );
  }
}
