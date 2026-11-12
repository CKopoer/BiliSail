import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/data/api_home_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final deleteFolder in [false, true]) {
    late _Transport transport;
    late ApiRequests requests;
    late BiliApiClient api;
    late ApiHomeRepository repo;
    var scope = 'user:7';
    setUp(() {
      scope = 'user:7';
      transport = _Transport();
      requests = ApiRequests();
      api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
        cookieJar: ApiCookieJar()
          ..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Path=/; Secure',
            'bili_jct=fixture-csrf; Path=/; Secure',
          ]),
      );
      repo = ApiHomeRepository(
        HomeClient(api),
        requests,
        accountScope: () => scope,
      );
    });
    tearDown(() => api.close());
    Future<void> write() => deleteFolder
        ? repo.deleteFavoriteFolder(
            const HomeEntry(id: '42', title: '收藏夹', kind: HomeEntryKind.folder),
            scope: 'user:7',
            cancellation: RequestCancellation(),
          )
        : repo.removeFavorite(
            const HomeEntry(
              id: 'BV1234567890',
              aid: '123',
              title: '视频',
              kind: HomeEntryKind.video,
            ),
            folderId: '42',
            scope: 'user:7',
            cancellation: RequestCancellation(),
          );

    test('folder=$deleteFolder checks ownership before posting', () async {
      transport.owner = '8';
      await expectLater(
        write(),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.permission,
          ),
        ),
      );
      expect(transport.posts, 0);
      transport.owner = '7';
      await write();
      expect(transport.posts, 1);
    });
    test(
      'folder=$deleteFolder scope mismatch never reaches transport',
      () async {
        scope = 'user:8';
        await expectLater(
          write(),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        expect(transport.gets, 0);
        expect(transport.posts, 0);
      },
    );
    test(
      'folder=$deleteFolder lost write response is uncertain without replay',
      () async {
        transport.error = const ApiFailure(
          ApiFailureCategory.network,
          'fixture',
        );
        await expectLater(write(), throwsA(isA<UnknownWriteOutcome>()));
        expect(transport.posts, 1);
      },
    );
    test(
      'folder=$deleteFolder rejects late success after session changes',
      () async {
        transport.pending = Completer<ApiHttpResponse>();
        final assertion = expectLater(
          write(),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        requests.advanceSession();
        transport.pending!.complete(_response(null));
        await assertion;
        expect(transport.posts, 1);
      },
    );
  }
}

ApiHttpResponse _response(Object? data) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

final class _Transport implements ApiTransport, ApiFormTransport {
  String owner = '7';
  int gets = 0, posts = 0;
  Object? error;
  Completer<ApiHttpResponse>? pending;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    gets++;
    return _response({
      'info': {
        'id': '42',
        'title': '收藏夹',
        'intro': '',
        'attr': 0,
        'upper': {'mid': owner},
      },
    });
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    if (error case final failure?) throw failure;
    return pending == null ? _response(null) : pending!.future;
  }
}
