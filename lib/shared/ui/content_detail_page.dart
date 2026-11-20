import 'package:material_ui/material_ui.dart';

import 'playback_navigation.dart';

class ContentDetailPage extends StatelessWidget {
  const ContentDetailPage({
    super.key,
    required this.title,
    required this.body,
    this.backButtonKey,
    this.action,
  });

  final String title;
  final Widget body;
  final Key? backButtonKey;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          IconButton(
            key: backButtonKey,
            tooltip: '返回',
            onPressed:
                PlaybackNavigation.maybeOf(context)?.onBack ??
                () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
      const Divider(height: 1),
      Expanded(child: body),
    ],
  );
}
