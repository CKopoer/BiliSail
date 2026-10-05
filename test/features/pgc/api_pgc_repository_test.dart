import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bili_lite/core/network/api_requests.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/features/pgc/data/api_pgc_repository.dart';
import 'package:bili_lite/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Transport implements ApiTransport {
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'result': {
            'season_id': '42',
            'title': '本篇',
            'episodes': const [],
            'seasons': [
              {
                'season_id': '9007199254740993',
                'season_title': '续作',
                'cover': '',
              },
            ],
          },
        }),
      ),
    ),
    const {},
  );
}

void main() {
  test(
    'repository retains related season ID, nullable cover and immutable list',
    () async {
      final requests = ApiRequests();
      final repository = ApiPgcRepository(
        PgcClient(
          BiliApiClient(transport: _Transport(), sessionProvider: requests),
        ),
        requests,
        accountScope: () => 'guest',
      );
      final season = await repository.detail(
        seasonId: const PgcSeasonId('42'),
        cancellation: RequestCancellation(),
      );
      expect(season.relatedSeasons.single.id.value, '9007199254740993');
      expect(season.relatedSeasons.single.title, '续作');
      expect(season.relatedSeasons.single.coverUrl, isNull);
      expect(
        () => season.relatedSeasons.add(
          const PgcSeasonSummary(id: PgcSeasonId('2'), title: '额外作品'),
        ),
        throwsUnsupportedError,
      );
    },
  );
}
