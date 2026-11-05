import 'package:flutter/material.dart';

import '../../../shared/ui/app_dialog.dart';
import '../domain/profile_repository.dart';

Future<void> showProfileDetails(
  BuildContext context, {
  required UserProfile profile,
  ProfileSpaceDetails? details,
  String? detailsMessage,
}) => showAppDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('用户资料'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Detail(label: '昵称', value: profile.name),
              _Detail(label: 'UID', value: profile.id.value),
              if (profile.level case final level?)
                _Detail(label: '等级', value: 'LV$level'),
              if (profile.vipLabel case final value? when value.isNotEmpty)
                _Detail(label: '会员', value: value),
              if (profile.verifyDescription case final value?
                  when value.isNotEmpty)
                _Detail(label: '认证', value: value),
              if (details case final value?) ...[
                if (value.gender.isNotEmpty)
                  _Detail(label: '性别', value: value.gender),
                if (value.birthday.isNotEmpty)
                  _Detail(label: '生日', value: value.birthday),
              ],
              for (final (label, count) in [
                ('关注', profile.followingCount),
                ('粉丝', profile.followerCount),
                ('获赞', profile.likeCount),
                ('投稿', profile.videoCount),
              ])
                _Detail(label: label, value: '${count ?? '未知'}'),
              _Detail(
                label: '简介',
                value: profile.signature.isEmpty ? '暂无简介' : profile.signature,
              ),
              if (detailsMessage != null) Text('扩展资料：$detailsMessage'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  ),
);

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}
