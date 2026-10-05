// Explicit guest-only smoke for newly registered read endpoints.
import 'package:bili_api/bili_api.dart';

Future<void> main() async {
  final client = BiliApiClient();
  try {
    await check('recommended', () => client.getRecommended());
    await check(
      'regional_videos',
      () => client.getRegionalVideos(categoryId: '1'),
    );
    await check('ranking', () => client.getRanking());
  } finally {
    client.close();
  }
}

Future<void> check(
  String name,
  Future<ApiPage<ApiVideoSummary>> Function() work,
) async {
  try {
    final result = await work();
    print(
      '$name: success items=${result.items.length} hasMore=${result.hasMore}',
    );
  } on ApiFailure catch (failure) {
    print(
      '$name: ${failure.category.name} http=${failure.httpStatus} code=${failure.businessCode}',
    );
  }
}
