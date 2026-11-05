import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/messages/data/api_message_center_repository.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class BatchTransport implements ApiTransport, ApiFormTransport {
  final List<(String, Map<String, String>)> requests = [];
  List<int> statuses = [200, 503, 200];
  void Function()? afterFirst;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => throw StateError('Batch must not fetch or sync sessions');
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add((uri.path, Map.of(fields)));
    if (requests.length == 1) afterFirst?.call();
    final status = statuses[requests.length - 1];
    return ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': {}}))),
      const {},
    );
  }
}

void main() {
  late BatchTransport transport;
  late ApiRequests requests;
  late ApiMessageCenterRepository repository;
  final entries = List.generate(
    3,
    (index) => InboxEntry(
      id: '1:${index + 2}',
      title: '会话$index',
      text: '',
      sessionType: 1,
      userId: UserId('${index + 2}'),
      unread: 1,
      lastSequence: '900719925474099312$index',
    ),
  );
  setUp(() {
    requests = ApiRequests();
    transport = BatchTransport();
    final jar = ApiCookieJar()
      ..receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
        'bili_jct=fixture-csrf; Domain=.bilibili.com; Path=/; Secure',
      ]);
    repository = ApiMessageCenterRepository(
      MessageCenterClient(
        BiliApiClient(
          transport: transport,
          cookieJar: jar,
          sessionProvider: requests,
        ),
      ),
      requests,
      accountScope: () => 'user:1',
    );
  });
  test('clear removes only confirmed bounded targets and stops on uncertain failure', () async {
    final result = await repository.clearConversations(
      entries,
      cancellation: RequestCancellation(),
    );
    expect(result.requested, 3);
    expect(result.removed, 1);
    expect(result.uncertain, isTrue);
    expect(result.complete, isFalse);
    expect(transport.requests, hasLength(2));
    expect(
      transport.requests.first.$1,
      '/session_svr/v1/session_svr/remove_session',
    );
    expect(transport.requests.first.$2['talker_id'], '2');
  });
  test('explicit bulk read uses exact known last sequence and never ack sync endpoint', () async {
    final result = await repository.markAllPrivateRead(
      entries,
      cancellation: RequestCancellation(),
    );
    expect(result.requested, 3);
    expect(result.acknowledged, 1);
    expect(result.uncertain, isTrue);
    expect(transport.requests, hasLength(2));
    expect(
      transport.requests.first.$1,
      '/session_svr/v1/session_svr/update_ack',
    );
    expect(transport.requests.first.$2['ack_seqno'], '9007199254740993120');
    expect(transport.requests.last.$2['talker_id'], '3');
  });
  test(
    'authentication failure is explicit partial result, not unknown success',
    () async {
      transport.statuses = [200, 403, 200];
      final result = await repository.clearConversations(
        entries,
        cancellation: RequestCancellation(),
      );
      expect(result.removed, 1);
      expect(result.failed, 1);
      expect(result.uncertain, isFalse);
      expect(transport.requests, hasLength(2));
    },
  );
  test('account cancellation stops batch before the next identity', () async {
    transport.afterFirst = requests.advanceSession;
    await expectLater(
      repository.markAllPrivateRead(
        entries,
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    expect(transport.requests, hasLength(1));
  });
  test(
    'invalid sequence and oversized clear scopes are rejected before network',
    () async {
      expect(
        () => repository.markAllPrivateRead([
          const InboxEntry(
            id: '1:2',
            title: 'bad',
            text: '',
            sessionType: 1,
            userId: UserId('2'),
            lastSequence: '1e18',
          ),
        ], cancellation: RequestCancellation()),
        throwsArgumentError,
      );
      expect(
        () => repository.clearConversations(
          List.filled(501, entries.first),
          cancellation: RequestCancellation(),
        ),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    },
  );
}
