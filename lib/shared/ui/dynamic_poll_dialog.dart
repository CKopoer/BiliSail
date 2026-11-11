import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dynamic/application/dynamic_poll_controller.dart';
import '../../features/dynamic/domain/dynamic_poll.dart';
import 'app_dialog.dart';
import 'app_network_image.dart';

Future<void> showDynamicPollDialog(
  BuildContext context,
  String id, {
  String? dynamicId,
  VoidCallback? onLogin,
}) {
  final container = ProviderScope.containerOf(context);
  return showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: DynamicPollDialog(id: id, dynamicId: dynamicId, onLogin: onLogin),
    ),
  );
}

class DynamicPollDialog extends ConsumerWidget {
  const DynamicPollDialog({
    super.key,
    required this.id,
    this.dynamicId,
    this.onLogin,
  });
  final String id;
  final String? dynamicId;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dynamicPollProvider(id));
    final controller = ref.read(dynamicPollProvider(id).notifier);
    final poll = state.poll;
    final theme = Theme.of(context);
    final ended = poll?.endedAt(ref.read(dynamicPollClockProvider)()) ?? false;
    final canChoose = controller.canChoose;
    return PopScope(
      canPop: !state.submitting,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 800),
          child: SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('投票详情', style: theme.textTheme.titleMedium),
                      ),
                      IconButton(
                        tooltip: '刷新投票',
                        onPressed: state.busy
                            ? null
                            : () => unawaited(controller.load()),
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: '关闭投票',
                        onPressed: state.submitting
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (state.busy) const LinearProgressIndicator(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (poll != null) ...[
                          Text(poll.title, style: theme.textTheme.titleLarge),
                          if (poll.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(poll.description),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              Text('${poll.joinCount}人参与'),
                              Text(
                                poll.maxChoices == 1
                                    ? '单选'
                                    : '最多选择${poll.maxChoices}项',
                              ),
                              Text(
                                ended
                                    ? '已结束'
                                    : poll.hasVoted
                                    ? '已投票'
                                    : '进行中',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '截止时间 ${_dateLabel(poll.endsAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          for (final option in poll.options) ...[
                            _PollOption(
                              option: option,
                              selected: state.selected.contains(option.index),
                              showResults: state.showResults,
                              totalVotes: poll.totalVotes,
                              onTap: canChoose
                                  ? () => controller.select(option.index)
                                  : null,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (canChoose || state.uncertain) ...[
                            Wrap(
                              spacing: 8,
                              children: [
                                FilterChip(
                                  label: const Text('显示比例'),
                                  selected: state.showResults,
                                  onSelected: controller.setShowResults,
                                ),
                                FilterChip(
                                  label: const Text('匿名投票'),
                                  selected: state.anonymous,
                                  onSelected: canChoose
                                      ? controller.setAnonymous
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                        if (state.message case final message?)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(message),
                          ),
                        if (poll == null && !state.busy)
                          OutlinedButton(
                            onPressed: () => unawaited(controller.load()),
                            child: const Text('重试'),
                          ),
                        if (poll != null && !ended && !poll.hasVoted)
                          FilledButton(
                            onPressed:
                                state.busy ||
                                    state.uncertain ||
                                    (state.signedIn && state.selected.isEmpty)
                                ? null
                                : () {
                                    if (!state.signedIn) {
                                      if (onLogin != null) {
                                        Navigator.pop(context);
                                        onLogin!();
                                      }
                                      return;
                                    }
                                    unawaited(
                                      controller.submit(dynamicId: dynamicId),
                                    );
                                  },
                            child: Text(
                              state.submitting
                                  ? '正在投票…'
                                  : state.signedIn
                                  ? '投票'
                                  : '登录后投票',
                            ),
                          ),
                      ],
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
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.option,
    required this.selected,
    required this.showResults,
    required this.totalVotes,
    this.onTap,
  });
  final DynamicPollOption option;
  final bool selected, showResults;
  final int totalVotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = totalVotes == 0 ? 0.0 : option.count / totalVotes;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('poll-option-${option.index}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (option.imageUrl case final image?) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: AppNetworkImage(
                      url: image.toString(),
                      cacheWidth: 640,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 80,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(option.text)),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle, size: 20, color: scheme.primary),
                    ],
                  ],
                ),
                if (showResults) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${option.count}票 · ${(ratio * 100).toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: ratio),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
