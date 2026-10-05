import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/data/api_favorite_folder_repository.dart';
import 'package:bilisail/features/feed/domain/favorite_folder_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = (id: '42', scope: 'user:1');
const _edit = FavoriteFolderEdit(title: '音乐', intro: '原简介', isPrivate: true);
ApiHttpResponse _response(Object? data) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late BiliApiClient api;
  late ApiFavoriteFolderRepository repo;
  var scope = 'user:1';
  setUp(() {
    scope = 'user:1';
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
    repo = ApiFavoriteFolderRepository(
      FavoriteFolderClient(api),
      requests,
      accountScope: () => scope,
    );
  });
  tearDown(() => api.close());
  test('mapped folder is editable only by owner', () async {
    final info = await repo.load(_target, RequestCancellation());
    expect(info.title, '音乐');
    expect(info.intro, '原简介');
    expect(info.isPrivate, true);
    transport.owner = '2';
    await expectLater(
      repo.load(_target, RequestCancellation()),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.permission,
        ),
      ),
    );
    expect(transport.posts, 0);
  });
  test('scope mismatch blocks reads and writes before transport', () async {
    scope = 'user:2';
    await expectLater(
      repo.load(_target, RequestCancellation()),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(
      repo.update(_target, _edit, RequestCancellation()),
      throwsA(isA<AppFailure>()),
    );
    expect(transport.gets, 0);
    expect(transport.posts, 0);
  });
  test('network write becomes uncertain and is never replayed', () async {
    transport.failure = const ApiFailure(ApiFailureCategory.network, 'fixture');
    await expectLater(
      repo.update(_target, _edit, RequestCancellation()),
      throwsA(isA<FavoriteFolderWriteUncertain>()),
    );
    expect(transport.posts, 1);
  });
  test('permission failure stays definitive', () async {
    transport.failure = const ApiFailure(
      ApiFailureCategory.permission,
      'fixture',
    );
    await expectLater(
      repo.update(_target, _edit, RequestCancellation()),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.permission,
        ),
      ),
    );
    expect(transport.posts, 1);
  });
  test(
    'session invalidation rejects late write success without uncertainty',
    () async {
      transport.pending = Completer<ApiHttpResponse>();
      final write = repo.update(_target, _edit, RequestCancellation());
      final assertion = expectLater(
        write,
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
      expect(transport.signal?.isCancelled, true);
      transport.pending?.complete(_response(null));
      await assertion;
      expect(transport.posts, 1);
    },
  );
}

final class _Transport implements ApiTransport, ApiFormTransport {
  String owner = '1';
  int gets = 0, posts = 0;
  Object? failure;
  ApiCancellation? signal;
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
        'title': '音乐',
        'intro': '原简介',
        'attr': 2,
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
    signal = cancellation;
    posts++;
    if (failure case final error?) throw error;
    return pending == null ? _response(null) : await pending!.future;
  }
}
