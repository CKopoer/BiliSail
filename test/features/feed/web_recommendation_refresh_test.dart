import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/data/api_feed_repository.dart';
import 'package:bilisail/shared/application/recommendation_filter_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final source in [
    RecommendationSource.web,
    RecommendationSource.desktop,
  ]) {
    group(source.name, () {
      final desktop = source == RecommendationSource.desktop;
      int sample(int webIndex) => desktop ? webIndex - 1 : webIndex;
      late _Transport transport;
      late ApiRequests requests;
      late ApiFeedRepository repository;
      late ProviderContainer container;
      late FeedController controller;

      setUp(() {
        transport = _Transport()..desktop = desktop;
        requests = ApiRequests();
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
        );
        addTearDown(api.close);
        repository = ApiFeedRepository(api, requests);
        container = ProviderContainer(
          overrides: [
            feedRepositoryProvider.overrideWithValue(repository),
            recommendationSettingsProvider.overrideWithValue(
              RecommendationSettings(source: source),
            ),
          ],
        );
        addTearDown(container.dispose);
        controller = container.read(feedControllerProvider.notifier);
      });

      Future<Object> load({
        required int page,
        required String? categoryId,
        required RequestCancellation cancellation,
      }) => desktop && categoryId == null
          ? repository.loadDesktopRecommendations(
              page: page,
              cancellation: cancellation,
            )
          : repository.loadFeed(
              page: page,
              categoryId: categoryId,
              cancellation: cancellation,
            );

      if (desktop) {
        test('Web and desktop keep independent failed-page samples', () async {
          final cancellation = RequestCancellation();
          transport.failNext = true;
          await expectLater(
            repository.loadDesktopRecommendations(
              page: 1,
              cancellation: cancellation,
            ),
            throwsA(isA<AppFailure>()),
          );
          transport.desktop = false;
          await repository.loadFeed(
            page: 1,
            categoryId: null,
            cancellation: cancellation,
          );
          transport.desktop = true;
          await repository.loadDesktopRecommendations(
            page: 1,
            cancellation: cancellation,
          );
          await controller.refresh();
          expect(transport.indices, [0, 1, 0, 1]);
          expect(
            transport.recommendations.map(
              (uri) => uri.queryParameters['fresh_type'],
            ),
            ['0', '4', '0', '3'],
          );
        });
      }

      test('refreshes and pagination advance the sampling index', () async {
        await controller.refresh();
        await controller.loadMore();
        await controller.refresh();
        await controller.refresh();

        expect(transport.indices, [1, 2, 3, 4].map(sample));
        expect(
          container
              .read(feedControllerProvider)
              .items
              .requireValue
              .single
              .title,
          'batch4',
        );
        if (desktop) {
          expect(
            transport.recommendations.map(
              (uri) => uri.queryParameters['fresh_type'],
            ),
            ['0', '4', '3', '3'],
          );
        }
        for (final uri in transport.recommendations) {
          expect(
            uri.queryParameters['fresh_idx_1h'],
            desktop ? isNull : uri.queryParameters['fresh_idx'],
          );
        }
      });

      for (final emptyIndex in [1, 2]) {
        test(
          'refresh advances after successful empty batch $emptyIndex',
          () async {
            transport.emptyIndex = emptyIndex;
            for (var i = 0; i < emptyIndex; i++) {
              await controller.refresh();
            }
            final empty = container.read(feedControllerProvider);
            expect(empty.items.requireValue, isEmpty);
            expect(empty.hasMore, isFalse);

            await controller.refresh();

            expect(
              transport.indices,
              List.generate(emptyIndex + 1, (i) => sample(i + 1)),
            );
            expect(
              container
                  .read(feedControllerProvider)
                  .items
                  .requireValue
                  .single
                  .title,
              'batch${emptyIndex + 1}',
            );
          },
        );
      }

      test(
        'refresh advances after a batch containing only non-video cards',
        () async {
          transport.nonVideoIndex = 1;
          await controller.refresh();
          expect(
            container.read(feedControllerProvider).items.requireValue,
            isEmpty,
          );

          await controller.refresh();

          expect(transport.indices, [1, 2].map(sample));
          expect(
            container.read(feedControllerProvider).items.requireValue,
            hasLength(1),
          );
        },
      );

      test(
        'an explicit pagination retry reuses its failed sampling index',
        () async {
          await controller.refresh();
          transport.failNext = true;
          await controller.loadMore();
          expect(container.read(feedControllerProvider).pageError, isNotNull);

          await controller.loadMore();

          expect(transport.indices, [1, 2, 2].map(sample));
          expect(container.read(feedControllerProvider).pageError, isNull);
          expect(
            container.read(feedControllerProvider).items.requireValue,
            hasLength(2),
          );
        },
      );

      test(
        'a new refresh after a failed refresh starts a new sample',
        () async {
          transport.failNext = true;
          await controller.refresh();
          expect(container.read(feedControllerProvider).items.hasError, isTrue);

          await controller.refresh();

          expect(transport.indices, [1, 2].map(sample));
          expect(container.read(feedControllerProvider).items.hasValue, isTrue);
        },
      );

      test('cancelled pagination cannot change a newer refresh', () async {
        await controller.refresh();
        final held = Completer<ApiHttpResponse>();
        final started = Completer<void>();
        transport.holdNext = held;
        transport.heldStarted = started;
        final pagination = controller.loadMore();
        await started.future;

        await controller.refresh();
        held.complete(_batch(2));
        await pagination;
        await controller.loadMore();

        expect(transport.indices, [1, 2, 3, 4].map(sample));
        expect(
          container
              .read(feedControllerProvider)
              .items
              .requireValue
              .map((v) => v.title),
          ['batch3', 'batch4'],
        );
      });

      test('a session change discards a failed request index even for the same scope', () async {
        final cancellation = RequestCancellation();
        transport.failNext = true;
        await expectLater(
          load(page: 1, categoryId: null, cancellation: cancellation),
          throwsA(isA<AppFailure>()),
        );
        requests.advanceSession();

        await load(page: 1, categoryId: null, cancellation: cancellation);

        expect(transport.indices, desktop ? [0, 0] : [1, 2]);
      });

      test(
        'interleaved query scopes keep their own failed-page retry',
        () async {
          final first = RequestCancellation();
          final second = RequestCancellation();
          await load(page: 1, categoryId: null, cancellation: first);
          transport.failNext = true;
          await expectLater(
            load(page: 2, categoryId: null, cancellation: first),
            throwsA(isA<AppFailure>()),
          );
          await load(page: 1, categoryId: null, cancellation: second);
          await load(page: 2, categoryId: null, cancellation: first);
          await load(page: 3, categoryId: null, cancellation: first);

          expect(transport.indices, [1, 2, 3, 2, 4].map(sample));
        },
      );

      test(
        'regional pagination does not consume Web sampling indices',
        () async {
          await load(
            page: 3,
            categoryId: '1',
            cancellation: RequestCancellation(),
          );
          expect(transport.regional.single.queryParameters['pn'], '3');
          expect(
            transport.regional.single.queryParameters.containsKey('fresh_idx'),
            isFalse,
          );

          await controller.refresh();

          expect(transport.indices, [1].map(sample));
        },
      );

      test(
        'invalid pages and pre-cancelled calls do not consume a sampling index',
        () async {
          await expectLater(
            load(
              page: 0,
              categoryId: null,
              cancellation: RequestCancellation(),
            ),
            throwsArgumentError,
          );
          final cancelled = RequestCancellation()..cancel();
          await expectLater(
            load(page: 1, categoryId: null, cancellation: cancelled),
            throwsA(isA<AppFailure>()),
          );

          await controller.refresh();

          expect(transport.indices, [1].map(sample));
        },
      );
    });
  }
}

ApiHttpResponse _json(Map<String, Object?> body) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode(body))),
  const {},
);

ApiHttpResponse _batch(
  int index, {
  bool empty = false,
  bool nonVideo = false,
}) => _json({
  'code': 0,
  'data': {
    'item': empty
        ? []
        : nonVideo
        ? [
            {'goto': 'live'},
          ]
        : [
            {
              'bvid': 'BV12345678${index.toString().padLeft(2, '0')}',
              'title': 'batch$index',
              'duration': 60,
              'owner': {'name': 'UP'},
              'stat': {'view': 42, 'danmaku': 2},
            },
          ],
  },
});

final class _Transport implements ApiTransport {
  bool desktop = false;
  final recommendations = <Uri>[];
  final regional = <Uri>[];
  List<int> get indices => recommendations
      .map((uri) => int.parse(uri.queryParameters['fresh_idx'] ?? ''))
      .toList();
  int? emptyIndex;
  int? nonVideoIndex;
  bool failNext = false;
  Completer<ApiHttpResponse>? holdNext;
  Completer<void>? heldStarted;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path.endsWith('/nav')) {
      return _json({
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
          },
        },
      });
    }
    if (uri.path == '/x/web-interface/newlist') {
      regional.add(uri);
      return _json({
        'code': 0,
        'data': {'archives': []},
      });
    }
    if (uri.path !=
        (desktop
            ? '/x/web-interface/wbi/index/top/feed/rcmd'
            : '/x/web-interface/index/top/feed/rcmd')) {
      throw StateError('Unexpected endpoint: ${uri.path}');
    }
    final index = int.parse(uri.queryParameters['fresh_idx'] ?? '');
    recommendations.add(uri);
    final held = holdNext;
    if (held != null) {
      holdNext = null;
      heldStarted?.complete();
      return held.future;
    }
    if (failNext) {
      failNext = false;
      return _json({'code': -500});
    }
    final batch = desktop ? index + 1 : index;
    return _batch(
      batch,
      empty: batch == emptyIndex,
      nonVideo: batch == nonVideoIndex,
    );
  }
}
