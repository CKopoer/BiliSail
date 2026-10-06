// Guest-only date comparison. Legacy IDs are diagnostic inputs, never fallback.
import 'package:bili_api/bili_api.dart';

Future<void> main(List<String> arguments) async {
  final client = BiliApiClient();
  try {
    final regions = await RankingClient(client).getRegions();
    print('ranking_regions: success items=${regions.length}');
    for (final region in regions.take(2)) {
      await check(client, 'current_${region.id}', region.id);
    }
    for (final id in arguments) {
      await check(client, 'legacy_$id', id);
    }
  } on ApiFailure catch (failure) {
    print(
      'ranking_regions: ${failure.category.name} code=${failure.businessCode}',
    );
  } finally {
    client.close();
  }
}

Future<void> check(BiliApiClient client, String name, String id) async {
  try {
    final page = await client.getRanking(categoryId: id);
    final dates =
        page.items.map((item) => item.publishedAt?.toUtc()).nonNulls.toList()
          ..sort();
    final range =
        dates.isEmpty ? 'unknown' : '${day(dates.first)}..${day(dates.last)}';
    print('$name: success items=${page.items.length} published_utc=$range');
  } on ApiFailure catch (failure) {
    print('$name: ${failure.category.name} code=${failure.businessCode}');
  }
}

String day(DateTime date) => date.toIso8601String().split('T').first;
