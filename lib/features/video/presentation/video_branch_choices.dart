import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/app_failure.dart';
import '../domain/interactive_video_repository.dart';

class VideoBranchChoices extends StatelessWidget {
  const VideoBranchChoices({
    super.key,
    required this.choices,
    required this.onChoose,
    required this.onRetry,
    this.onRestart,
  });

  final AsyncValue<List<InteractiveVideoChoice>> choices;
  final ValueChanged<InteractiveVideoChoice> onChoose;
  final VoidCallback onRetry;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final actions = switch (choices) {
      _ when choices.isLoading => <Widget>[const Text('正在加载剧情选项…')],
      AsyncError(:final error)
          when error is AppFailure && error.kind == AppFailureKind.cancelled =>
        const <Widget>[],
      AsyncError() => <Widget>[
        const Text('剧情选项加载失败'),
        FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        if (onRestart != null)
          FilledButton.tonal(onPressed: onRestart, child: const Text('从头再看')),
      ],
      AsyncData(:final value) => <Widget>[
        for (final choice in value)
          FilledButton.tonal(
            onPressed: () => onChoose(choice),
            child: Text(
              choice.label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (value.isEmpty && onRestart != null)
          FilledButton.tonal(onPressed: onRestart, child: const Text('从头再看')),
      ],
      _ => const <Widget>[],
    };
    if (actions.isEmpty) return const SizedBox.shrink();
    return FractionallySizedBox(
      widthFactor: .9,
      heightFactor: .58,
      child: Center(
        child: SingleChildScrollView(
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
