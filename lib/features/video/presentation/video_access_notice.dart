import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/video_access_badge.dart';

class VideoAccessNotice extends ConsumerWidget {
  const VideoAccessNotice({super.key, required this.video});

  final VideoSummary video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = video.access;
    if (access.kind == VideoAccessKind.normal) return const SizedBox.shrink();
    final text = access.canWatch == true
        ? '当前账号已取得观看权限，播放内容以服务端返回为准。'
        : access.kind == VideoAccessKind.chargingExclusive
        ? '完整观看需要开通 UP 主指定的充电档位。已开通请登录对应账号；开通或试看可前往官网。'
        : '完整观看需要购买。已购买请登录对应账号；购买或试看可前往官网。';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VideoAccessBadge(access: access),
              TextButton.icon(
                key: const ValueKey('video-access-official'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('前往哔哩哔哩'),
                onPressed: () async {
                  try {
                    final opened = await ref.read(externalLinkOpenerProvider)(
                      Uri.https('www.bilibili.com', '/video/${video.id.value}'),
                    );
                    if (!opened && context.mounted) {
                      showAppNotice(context, '无法打开官方页面');
                    }
                  } on Exception {
                    if (context.mounted) showAppNotice(context, '无法打开官方页面');
                  }
                },
              ),
            ],
          ),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
