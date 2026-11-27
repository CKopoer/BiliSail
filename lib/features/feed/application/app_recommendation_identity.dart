import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/recommendation_settings.dart';
import '../../../domain/app_failure.dart';
import '../../../shared/application/recommendation_filter_provider.dart';
import '../domain/app_recommendation_identity_repository.dart';

final appRecommendationIdentityRepositoryProvider =
    Provider<AppRecommendationIdentityRepository?>((ref) => null);

final appRecommendationIdentityChangesProvider = StreamProvider<int>(
  (ref) =>
      ref.watch(appRecommendationIdentityRepositoryProvider)?.changes ??
      const Stream.empty(),
);

final appRecommendationIdentityProvider =
    AsyncNotifierProvider<
      AppRecommendationIdentityController,
      AppRecommendationIdentity
    >(AppRecommendationIdentityController.new, retry: (_, _) => null);

final class AppRecommendationIdentityController
    extends AsyncNotifier<AppRecommendationIdentity> {
  @override
  Future<AppRecommendationIdentity> build() async {
    ref.watch(appRecommendationIdentityChangesProvider);
    return await ref
            .watch(appRecommendationIdentityRepositoryProvider)
            ?.load() ??
        const AppRecommendationIdentity();
  }

  AppRecommendationIdentityRepository get _repository =>
      ref.read(appRecommendationIdentityRepositoryProvider) ??
      (throw const AppFailure(AppFailureKind.protocol, '当前环境暂不支持 App 推荐身份设置'));
  Future<void> _update(Future<void> Function() action) async {
    await action();
    // A successful retry must also recover a previously failed identity load.
    if (ref.mounted) ref.invalidateSelf();
  }

  Future<void> setBuvid(String value) =>
      _update(() => _repository.setBuvid(value));
  Future<void> randomizeBuvid() => _update(_repository.randomizeBuvid);
}

final recommendationQueryKeyProvider = Provider((ref) {
  final source = ref.watch(
    recommendationSettingsProvider.select((value) => value.source),
  );
  final identity = source == RecommendationSource.app
      ? ref.watch(appRecommendationIdentityChangesProvider).asData?.value ??
            ref.watch(appRecommendationIdentityRepositoryProvider)?.revision ??
            0
      : 0;
  return (source: source, identity: identity);
});
