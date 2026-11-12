import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/pgc/data/api_pgc_follow_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_follow_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = PgcSeasonId('42');
ApiHttpResponse _response({int code = 0}) => ApiHttpResponse(
  200,
  Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'code': code,
        'result': {'follow': 1},
      }),
    ),
  ),
  const {},
);

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late ApiPgcFollowRepository repo;
  late String scope;
  setUp(() {
    transport = _Transport();
    requests = ApiRequests();
    scope = 'user:7';
    repo = ApiPgcFollowRepository(
      PgcClient(
        BiliApiClient(
          transport: transport,
          sessionProvider: requests,
          cookieJar: ApiCookieJar()
            ..receive(Uri.https('api.bilibili.com', '/'), [
              'SESSDATA=fixture; Path=/; Secure',
              'bili_jct=fixture-csrf; Path=/; Secure',
            ]),
        ),
      ),
      requests,
      accountScope: () => scope,
    );
  });

  test(
    'guest reads and writes are rejected before reaching the client',
    () async {
      scope = 'guest';
      for (final result in [
        repo.isFollowed(_id, RequestCancellation()),
        repo.setFollowed(_id, true, RequestCancellation()),
      ]) {
        await expectLater(
          result,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.authentication,
            ),
          ),
        );
      }
      expect(transport.calls, 0);
    },
  );

  test('state read maps the authenticated user status', () async {
    expect(await repo.isFollowed(_id, RequestCancellation()), isTrue);
    expect(transport.calls, 1);
  });

  for (final category in [
    ApiFailureCategory.network,
    ApiFailureCategory.timeout,
    ApiFailureCategory.http,
    ApiFailureCategory.protocol,
  ]) {
    test('$category write failure is uncertain and never replayed', () async {
      transport.failure = ApiFailure(category, 'pgc_follow_write');
      await expectLater(
        repo.setFollowed(_id, true, RequestCancellation()),
        throwsA(isA<PgcFollowWriteUncertain>()),
      );
      expect(transport.calls, 1);
    });
  }

  test('business rejection remains a known authentication failure', () async {
    transport.response = _response(code: -101);
    await expectLater(
      repo.setFollowed(_id, false, RequestCancellation()),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
    expect(transport.calls, 1);
  });

  for (final operation in ['read', 'write']) {
    for (final transition in ['scope', 'epoch', 'cancel']) {
      test(
        'pending $operation discards success after $transition changes',
        () async {
          transport.pending = Completer<ApiHttpResponse>();
          final cancellation = RequestCancellation();
          final Future<Object?> result = operation == 'read'
              ? repo.isFollowed(_id, cancellation)
              : repo.setFollowed(_id, true, cancellation);
          final check = expectLater(
            result,
            throwsA(
              isA<AppFailure>().having(
                (e) => e.kind,
                'kind',
                AppFailureKind.cancelled,
              ),
            ),
          );
          if (transition == 'scope') scope = 'user:8';
          if (transition == 'epoch') requests.advanceSession();
          if (transition == 'cancel') cancellation.cancel();
          transport.pending!.complete(_response());
          await check;
          expect(transport.calls, 1);
        },
      );
    }
  }
}

class _Transport implements ApiTransport, ApiFormTransport {
  int calls = 0;
  ApiHttpResponse response = _response();
  ApiFailure? failure;
  Completer<ApiHttpResponse>? pending;
  Future<ApiHttpResponse> _send() async {
    calls++;
    if (failure case final error?) throw error;
    return pending?.future ?? response;
  }

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send();
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send();
}
