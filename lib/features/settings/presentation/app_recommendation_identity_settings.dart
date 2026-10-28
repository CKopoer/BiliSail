import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/application/app_recommendation_identity.dart';

final class AppRecommendationIdentitySettings extends ConsumerWidget {
  const AppRecommendationIdentitySettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(appRecommendationIdentityProvider)
      .when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: LinearProgressIndicator(),
        ),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('推荐登录状态读取失败，请重试。'),
            TextButton(
              onPressed: () =>
                  ref.invalidate(appRecommendationIdentityProvider),
              child: const Text('重试'),
            ),
          ],
        ),
        data: (identity) => Text(
          identity.authorizedMid == null
              ? '当前使用游客推荐。'
              : identity.expired
              ? '账号推荐登录已失效，请重新扫码登录。'
              : '当前使用账号推荐。',
        ),
      );
}
