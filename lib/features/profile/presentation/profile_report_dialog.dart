import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../application/profile_report_controller.dart';
import '../domain/profile_report.dart';
import '../domain/profile_repository.dart';

class ProfileReportDialog extends ConsumerStatefulWidget {
  const ProfileReportDialog({
    super.key,
    required this.profile,
    this.cancellation,
  });
  final UserProfile profile;
  final RequestCancellation? cancellation;

  @override
  ConsumerState<ProfileReportDialog> createState() =>
      _ProfileReportDialogState();
}

class _ProfileReportDialogState extends ConsumerState<ProfileReportDialog> {
  final _contents = <ProfileReportContent>{};
  ProfileReportReason? _reason;

  @override
  void initState() {
    super.initState();
    widget.cancellation?.onCancel(
      ref
          .read(profileReportControllerProvider(widget.profile.id).notifier)
          .cancel,
    );
  }

  Future<void> _submit() async {
    final provider = profileReportControllerProvider(widget.profile.id);
    await ref
        .read(provider.notifier)
        .submit(ProfileReport(contents: _contents, reason: _reason));
    if (mounted && ref.read(provider).status == ProfileReportStatus.submitted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileReportControllerProvider(widget.profile.id));
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('profile-report-dialog'),
      insetPadding: const EdgeInsets.all(16),
      title: const Text('举报 UP 主'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.profile.name),
              Text(
                'UID：${widget.profile.id.value}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              const Text('举报内容（必选，可多选）'),
              for (final content in ProfileReportContent.values)
                CheckboxListTile(
                  key: ValueKey(content),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(switch (content) {
                    ProfileReportContent.avatar => '头像违规',
                    ProfileReportContent.nickname => '昵称违规',
                    ProfileReportContent.signature => '签名违规',
                  }),
                  value: _contents.contains(content),
                  onChanged: state.canSubmit
                      ? (selected) => setState(() {
                          if (selected == true) {
                            _contents.add(content);
                          } else {
                            _contents.remove(content);
                          }
                        })
                      : null,
                ),
              const SizedBox(height: 12),
              const Text('举报理由（选填，单选）'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final reason in ProfileReportReason.values)
                    FilterChip(
                      key: ValueKey(reason),
                      label: Text(switch (reason) {
                        ProfileReportReason.sexualContent => '色情低俗',
                        ProfileReportReason.misinformation => '不实信息',
                        ProfileReportReason.prohibitedContent => '违禁',
                        ProfileReportReason.personalAttack => '人身攻击',
                        ProfileReportReason.gamblingFraud => '赌博诈骗',
                        ProfileReportReason.illegalPromotion => '违规引流外链',
                      }),
                      selected: _reason == reason,
                      onSelected: state.canSubmit
                          ? (selected) => setState(() {
                              _reason = selected ? reason : null;
                            })
                          : null,
                    ),
                ],
              ),
              if (state.message case final message?) ...[
                const SizedBox(height: 16),
                Text(message, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(state.canSubmit ? '取消' : '关闭'),
        ),
        FilledButton(
          key: const ValueKey('profile-report-submit'),
          onPressed: state.canSubmit && _contents.isNotEmpty ? _submit : null,
          child: Text(
            state.status == ProfileReportStatus.submitting ? '提交中…' : '提交举报',
          ),
        ),
      ],
    );
  }
}
