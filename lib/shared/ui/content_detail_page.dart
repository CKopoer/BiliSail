import 'dart:ui' show SemanticsRole;

import 'package:material_ui/material_ui.dart';

import 'playback_navigation.dart';

class ContentDetailPage extends StatelessWidget {
  const ContentDetailPage({
    super.key,
    required this.title,
    required this.body,
    this.backButtonKey,
    this.action,
    this.inDialog = false,
  });

  final String title;
  final Widget body;
  final Key? backButtonKey;
  final Widget? action;
  final bool inDialog;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    constraints: const BoxConstraints(maxWidth: 1280, maxHeight: 1000),
    clipBehavior: Clip.antiAlias,
    semanticsRole: inDialog ? SemanticsRole.dialog : SemanticsRole.none,
    child: SizedBox(
      width: 1280,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?action,
                IconButton(
                  key: backButtonKey,
                  tooltip: inDialog ? '关闭' : '返回',
                  onPressed: inDialog
                      ? () => Navigator.pop(context)
                      : PlaybackNavigation.maybeOf(context)?.onBack ??
                            () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    ),
  );
}
