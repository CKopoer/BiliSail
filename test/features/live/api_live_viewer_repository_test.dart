import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/live/data/api_live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'exact viewer read carries cancellation and rejects old account response',
    () async {
      final requests = ApiRequests();
      final transport = _Transport();
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final repository = ApiLiveRepository(
        LiveClient(api),
        requests,
        accountScope: () => 'guest',
      );
      final result = await repository.loadViewerCount(
        const RoomId('545068'),
        const UserId('8739477'),
        cancellation: RequestCancellation(),
      );
      expect(result, 19357);
      transport.pending = Completer<ApiHttpResponse>();
      final read = repository.loadViewerCount(
        const RoomId('545068'),
        const UserId('8739477'),
        cancellation: RequestCancellation(),
      );
      final assertion = expectLater(
        read,
        throwsA(
          isA<AppFailure>().having(
            (error) => error.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      await transport.started.future;
      requests.advanceSession();
      expect(transport.signal?.isCancelled, true);
      transport.pending?.complete(_response());
      await assertion;
    },
  );
}

ApiHttpResponse _response() => ApiHttpResponse(
  200,
  Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'code': 0,
        'data': {'onlineNum': 19357, 'onlineNumText': '1万+'},
      }),
    ),
  ),
  const {},
);

final class _Transport implements ApiTransport {
  Completer<ApiHttpResponse>? pending;
  final started = Completer<void>();
  ApiCancellation? signal;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    signal = cancellation;
    final response = pending;
    if (response == null) return _response();
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}
