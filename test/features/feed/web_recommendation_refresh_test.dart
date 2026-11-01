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
  late _Transport transport;
  late ApiRequests requests;
  late ApiFeedRepository repository;
  late ProviderContainer container;
  late FeedController controller;

  setUp(() {
    transport = _Transport();
    requests = ApiRequests();
    final api = BiliApiClient(transport: transport, sessionProvider: requests);
    addTearDown(api.close);
    repository = ApiFeedRepository(api, requests);
    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(repository),
        recommendationSettingsProvider.overrideWithValue(
          const RecommendationSettings.defaults(),
        ),
      ],
    );
    addTearDown(container.dispose);
    controller = container.read(feedControllerProvider.notifier);
  });

  test('refreshes and pagination advance the Web sampling index', () async {
    await controller.refresh();
    await controller.loadMore();
    await controller.refresh();
    await controller.refresh();

    expect(transport.indices, [1, 2, 3, 4]);
    expect(
      container.read(feedControllerProvider).items.requireValue.single.title,
      'batch4',
    );
    for (final uri in transport.recommendations) {
      expect(
        uri.queryParameters['fresh_idx_1h'],
        uri.queryParameters['fresh_idx'],
      );
    }
  });

  for (final emptyIndex in [1, 2]) {
    test('refresh advances after successful empty batch $emptyIndex', () async {
      transport.emptyIndex = emptyIndex;
      for (var i = 0; i < emptyIndex; i++) {
        await controller.refresh();
      }
      final empty = container.read(feedControllerProvider);
      expect(empty.items.requireValue, isEmpty);
      expect(empty.hasMore, isFalse);

      await controller.refresh();

      expect(transport.indices, List.generate(emptyIndex + 1, (i) => i + 1));
      expect(
        container.read(feedControllerProvider).items.requireValue.single.title,
        'batch${emptyIndex + 1}',
      );
    });
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

      expect(transport.indices, [1, 2]);
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

      expect(transport.indices, [1, 2, 2]);
      expect(container.read(feedControllerProvider).pageError, isNull);
      expect(
        container.read(feedControllerProvider).items.requireValue,
        hasLength(2),
      );
    },
  );

  test('a new refresh after a failed refresh starts a new sample', () async {
    transport.failNext = true;
    await controller.refresh();
    expect(container.read(feedControllerProvider).items.hasError, isTrue);

    await controller.refresh();

    expect(transport.indices, [1, 2]);
    expect(container.read(feedControllerProvider).items.hasValue, isTrue);
  });

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

    expect(transport.indices, [1, 2, 3, 4]);
    expect(
      container
          .read(feedControllerProvider)
          .items
          .requireValue
          .map((v) => v.title),
      ['batch3', 'batch4'],
    );
  });

  test(
    'a session change discards a failed request index even for the same scope',
    () async {
      final cancellation = RequestCancellation();
      transport.failNext = true;
      await expectLater(
        repository.loadFeed(
          page: 1,
          categoryId: null,
          cancellation: cancellation,
        ),
        throwsA(isA<AppFailure>()),
      );
      requests.advanceSession();

      await repository.loadFeed(
        page: 1,
        categoryId: null,
        cancellation: cancellation,
      );

      expect(transport.indices, [1, 2]);
    },
  );

  test('interleaved query scopes keep their own failed-page retry', () async {
    final first = RequestCancellation();
    final second = RequestCancellation();
    await repository.loadFeed(page: 1, categoryId: null, cancellation: first);
    transport.failNext = true;
    await expectLater(
      repository.loadFeed(page: 2, categoryId: null, cancellation: first),
      throwsA(isA<AppFailure>()),
    );
    await repository.loadFeed(page: 1, categoryId: null, cancellation: second);
    await repository.loadFeed(page: 2, categoryId: null, cancellation: first);
    await repository.loadFeed(page: 3, categoryId: null, cancellation: first);

    expect(transport.indices, [1, 2, 3, 2, 4]);
  });

  test('regional pagination does not consume Web sampling indices', () async {
    await repository.loadFeed(
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

    expect(transport.indices, [1]);
  });

  test(
    'invalid pages and pre-cancelled calls do not consume a sampling index',
    () async {
      await expectLater(
        repository.loadFeed(
          page: 0,
          categoryId: null,
          cancellation: RequestCancellation(),
        ),
        throwsArgumentError,
      );
      final cancelled = RequestCancellation()..cancel();
      await expectLater(
        repository.loadFeed(page: 1, categoryId: null, cancellation: cancelled),
        throwsA(isA<AppFailure>()),
      );

      await controller.refresh();

      expect(transport.indices, [1]);
    },
  );
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
    if (uri.path != '/x/web-interface/index/top/feed/rcmd') {
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
    return _batch(
      index,
      empty: index == emptyIndex,
      nonVideo: index == nonVideoIndex,
    );
  }
}
