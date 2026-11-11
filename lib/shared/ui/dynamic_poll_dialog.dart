import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/user.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/dynamic/application/dynamic_poll_controller.dart';
import 'app_dialog.dart';
import 'app_network_image.dart';
import 'dynamic_publish_forms.dart';
import 'image_viewer.dart';

Future<void> showDynamicPollDialog(
  BuildContext context,
  String id, {
  String? dynamicId,
  VoidCallback? onLogin,
  ValueChanged<UserId>? onOpenUser,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => DynamicPollDialog(
    id: id,
    dynamicId: dynamicId,
    onLogin: onLogin,
    onOpenUser: onOpenUser,
  ),
);

class DynamicPollDialog extends ConsumerStatefulWidget {
  const DynamicPollDialog({
    super.key,
    required this.id,
    this.dynamicId,
    this.onLogin,
    this.onOpenUser,
  });
  final String id;
  final String? dynamicId;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  @override
  ConsumerState<DynamicPollDialog> createState() => _DynamicPollDialogState();
}

class _DynamicPollDialogState extends ConsumerState<DynamicPollDialog> {
  @override
  Widget build(BuildContext context) {
    final provider = dynamicPollProvider(widget.id),
        state = ref.watch(provider),
        controller = ref.read(provider.notifier);
    final signedIn = ref.watch(
      authControllerProvider.select((a) => a.isSignedIn),
    );
    final poll = state.poll, now = ref.read(dynamicPollClockProvider)();
    final open = poll?.openAt(now) == true;
    final results = state.showResults || !open;
    return PopScope(
      canPop: !state.submitting,
      child: DynamicFormDialog(
        title: '投票详情',
        closeTooltip: '关闭投票',
        canClose: !state.submitting,
        body: state.loading && poll == null
            ? const Center(child: LinearProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (poll != null) ...[
                      Text(
                        poll.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (poll.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(poll.description),
                        ),
                      Wrap(
                        spacing: 12,
                        children: [
                          Text('${poll.joinCount}人参与'),
                          Text(
                            poll.maxChoices == 1
                                ? '单选'
                                : '最多选${poll.maxChoices}项',
                          ),
                        ],
                      ),
                      Text('截止 ${dynamicDateLabel(poll.endsAt.toLocal())}'),
                      const SizedBox(height: 12),
                      for (final option in poll.options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: state.selected.contains(option.index)
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              key: ValueKey('poll-option-${option.index}'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: open && !state.busy && !state.uncertain
                                  ? () => controller.select(option.index)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (option.imageUrl case final image?)
                                      GestureDetector(
                                        onLongPress: () => showImageViewer(
                                          context,
                                          [image],
                                          0,
                                        ),
                                        onSecondaryTap: () => showImageViewer(
                                          context,
                                          [image],
                                          0,
                                        ),
                                        child: AppNetworkImage(
                                          url: image.toString(),
                                          height: 140,
                                          fit: BoxFit.contain,
                                          cacheWidth: 600,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox(
                                                height: 140,
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                ),
                                              ),
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        Icon(
                                          state.selected.contains(option.index)
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(option.text)),
                                      ],
                                    ),
                                    if (results) ...[
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: poll.fraction(option.index),
                                      ),
                                      Text(
                                        '${option.count}票 · ${(poll.fraction(option.index) * 100).toStringAsFixed(1)}%',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (open)
                        Wrap(
                          spacing: 12,
                          children: [
                            FilterChip(
                              label: const Text('显示比例'),
                              selected: state.showResults,
                              onSelected: controller.setShowResults,
                            ),
                            FilterChip(
                              label: const Text('匿名投票'),
                              selected: state.anonymous,
                              onSelected: state.busy || state.uncertain
                                  ? null
                                  : controller.setAnonymous,
                            ),
                          ],
                        ),
                      if (state.followees.isNotEmpty) ...[
                        const Divider(),
                        const Text('关注的人的投票'),
                        for (final person in state.followees)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(person.name),
                            subtitle: Text(
                              [
                                for (final c in poll.options)
                                  if (person.votes.contains(c.index)) c.text,
                              ].join('、'),
                            ),
                            onTap: widget.onOpenUser == null
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    widget.onOpenUser!(person.id);
                                  },
                          ),
                      ],
                    ],
                    if (state.message case final message?)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(message),
                      ),
                    if (poll == null && !state.busy)
                      OutlinedButton(
                        onPressed: controller.load,
                        child: const Text('重试'),
                      ),
                  ],
                ),
              ),
        actions: [
          if (poll != null && !open)
            Text(poll.myVotes.isNotEmpty ? '已投票' : '已结束'),
          TextButton(
            onPressed: state.busy ? null : controller.load,
            child: const Text('刷新投票'),
          ),
          if (state.canConfirmNotVoted)
            TextButton(
              onPressed: () async {
                final confirmed = await showAppDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认投票结果'),
                    content: const Text('刷新后尚未查到已投记录。请确认这次投票没有成功，再解除重试限制。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('继续核对'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确认未投票'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) controller.confirmNotVoted();
              },
              child: const Text('已核对，确认未投票'),
            ),
          if (open)
            FilledButton(
              key: const ValueKey('dynamic-poll-submit'),
              onPressed:
                  state.busy ||
                      state.uncertain ||
                      (signedIn && state.selected.isEmpty)
                  ? null
                  : () async {
                      if (!signedIn) {
                        if (widget.onLogin != null) {
                          Navigator.pop(context);
                          widget.onLogin!();
                        }
                        return;
                      }
                      await controller.submit(dynamicId: widget.dynamicId);
                    },
              child: Text(
                state.busy
                    ? '投票中…'
                    : signedIn
                    ? '投票'
                    : '登录后投票',
              ),
            ),
        ],
      ),
    );
  }
}
