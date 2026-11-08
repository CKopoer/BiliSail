import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/feed/data/api_home_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late ApiHomeRepository repository;
  var scope = 'user:7';
  setUp(() {
    scope = 'user:7';
    transport = _Transport();
    requests = ApiRequests();
    final api = BiliApiClient(transport: transport, sessionProvider: requests);
    addTearDown(api.close);
    repository = ApiHomeRepository(
      HomeClient(api),
      requests,
      accountScope: () => scope,
    );
  });

  test(
    'maps author identity, avatar and unread marker without reordering',
    () async {
      final page = await repository.loadDynamicAuthors(
        scope: scope,
        cancellation: RequestCancellation(),
      );
      expect(page.items.map((item) => item.id.value), [
        '9007199254740993123',
        '7',
      ]);
      expect(page.items.first.avatarUrl?.scheme, 'https');
      expect(page.items.first.name, '测试 UP 主');
      expect(page.items.first.hasUpdate, isTrue);
    },
  );

  test('stale scope and guests are rejected before HTTP', () async {
    await expectLater(
      repository.loadDynamicAuthors(
        scope: 'user:8',
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (error) => error.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    scope = 'guest';
    await expectLater(
      repository.loadDynamicAuthors(
        scope: scope,
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (error) => error.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
    await expectLater(
      repository.loadAuthorFeed(
        (
          channel: HomeChannel.dynamic,
          section: '全部',
          scope: scope,
          folderId: null,
        ),
        const UserId('7'),
        page: 1,
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (error) => error.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
    expect(transport.calls, 0);
  });

  for (final advanceEpoch in [false, true]) {
    test(
      'pending author read rejects account/epoch change ($advanceEpoch)',
      () async {
        transport.pending = Completer<void>();
        final load = repository.loadDynamicAuthors(
          scope: scope,
          cancellation: RequestCancellation(),
        );
        if (advanceEpoch) {
          requests.advanceSession();
          expect(transport.cancellation?.isCancelled, isTrue);
        } else {
          scope = 'user:8';
        }
        transport.pending?.complete();
        await expectLater(
          load,
          throwsA(
            isA<AppFailure>().having(
              (error) => error.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
      },
    );
  }
}

final class _Transport implements ApiTransport {
  int calls = 0;
  Completer<void>? pending;
  ApiCancellation? cancellation;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls++;
    this.cancellation = cancellation;
    await pending?.future;
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': {
              'up_list': {
                'items': [
                  for (final mid in ['9007199254740993123', 7])
                    {
                      'mid': mid,
                      'uname': '测试 UP 主',
                      'face': '//i0.hdslb.com/face.jpg',
                      'has_update': true,
                    },
                ],
                'has_more': false,
              },
            },
          }),
        ),
      ),
      const {},
    );
  }
}
