import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/comments/data/public_comment_video_link_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = VideoId('BV117BkBsEWw');
  late ApiRequests requests;
  late _Transport transport;
  late BiliApiClient api;
  setUp(() {
    requests = ApiRequests();
    transport = _Transport();
    api = BiliApiClient(transport: transport, sessionProvider: requests);
  });
  Matcher failure(AppFailureKind kind) =>
      isA<AppFailure>().having((error) => error.kind, 'kind', kind);

  test('expands a random short link then resolves its BV path', () async {
    final visited = <Uri>[];
    final repository = PublicCommentVideoLinkRepository(
      api,
      requests,
      expand: (uri, _, _) async {
        visited.add(uri);
        return Uri.parse(
          'https://www.bilibili.com/video/${id.value}?from=share',
        );
      },
    );
    final short = Uri.parse('https://b23.tv/randomToken');
    expect(
      await repository.resolve(short, cancellation: RequestCancellation()),
      id,
    );
    expect(visited, [short]);
    expect(transport.calls, isEmpty);
  });

  test('AV links use aid on the API and return BV identity', () async {
    final repository = PublicCommentVideoLinkRepository(api, requests);
    expect(
      await repository.resolve(
        Uri.parse('https://m.bilibili.com/video/av170001.html'),
        cancellation: RequestCancellation(),
      ),
      id,
    );
    expect(transport.calls.single.path, '/x/web-interface/view');
    expect(transport.calls.single.queryParameters, {'aid': '170001'});
  });

  for (final location in [
    'https://example.com/video/${id.value}',
    'https://b23.tv.example.com/${id.value}',
    'https://www.bilibili.com/read/cv123',
    'https://user:password@b23.tv/${id.value}',
  ]) {
    test('unsupported redirect returns browser fallback: $location', () async {
      var calls = 0;
      final repository = PublicCommentVideoLinkRepository(
        api,
        requests,
        expand: (_, _, _) async {
          calls++;
          return Uri.parse(location);
        },
      );
      expect(
        await repository.resolve(
          Uri.parse('https://b23.tv/randomToken'),
          cancellation: RequestCancellation(),
        ),
        isNull,
      );
      expect(calls, 1);
      expect(transport.calls, isEmpty);
    });
  }

  test('caps redirect chains and rejects cycles', () async {
    var calls = 0;
    final repository = PublicCommentVideoLinkRepository(
      api,
      requests,
      expand: (_, _, _) async => Uri.parse('https://b23.tv/token${++calls}'),
    );
    await expectLater(
      repository.resolve(
        Uri.parse('https://b23.tv/start'),
        cancellation: RequestCancellation(),
      ),
      throwsA(failure(AppFailureKind.protocol)),
    );
    expect(calls, 3);
    calls = 0;
    final cycle = PublicCommentVideoLinkRepository(
      api,
      requests,
      expand: (uri, _, _) async {
        calls++;
        return uri;
      },
    );
    await expectLater(
      cycle.resolve(
        Uri.parse('https://b23.tv/start'),
        cancellation: RequestCancellation(),
      ),
      throwsA(failure(AppFailureKind.protocol)),
    );
    expect(calls, 1);
  });

  test('account transition cancels an unfinished short-link request', () async {
    final pending = Completer<Uri?>();
    final repository = PublicCommentVideoLinkRepository(
      api,
      requests,
      expand: (_, _, _) => pending.future,
    );
    final cancellation = RequestCancellation();
    final operation = repository.resolve(
      Uri.parse('https://b23.tv/start'),
      cancellation: cancellation,
    );
    final assertion = expectLater(
      operation,
      throwsA(failure(AppFailureKind.cancelled)),
    );
    requests.advanceSession();
    expect(cancellation.isCancelled, isTrue);
    pending.complete(Uri.parse('https://b23.tv/${id.value}'));
    await assertion;
  });

  test('total timeout cancels unfinished work without retrying', () async {
    var calls = 0;
    final pending = Completer<Uri?>();
    final cancellation = RequestCancellation();
    final repository = PublicCommentVideoLinkRepository(
      api,
      requests,
      timeout: const Duration(milliseconds: 5),
      expand: (_, _, _) {
        calls++;
        return pending.future;
      },
    );
    await expectLater(
      repository.resolve(
        Uri.parse('https://b23.tv/start'),
        cancellation: cancellation,
      ),
      throwsA(failure(AppFailureKind.timeout)),
    );
    expect(cancellation.isCancelled, isTrue);
    expect(calls, 1);
    pending.complete(null);
  });

  test(
    'native transport reads Location without following or reading HTML',
    () async {
      final response = _Response('/${id.value}');
      final client = _Client(response);
      final cancellation = RequestCancellation();
      final target = await readBilibiliShortLinkLocation(
        Uri.parse('https://b23.tv/start'),
        cancellation,
        const Duration(seconds: 8),
        clientFactory: () => client,
      );
      expect(target, Uri.parse('https://b23.tv/${id.value}'));
      expect(client.uri, Uri.parse('https://b23.tv/start'));
      expect(client.request.followRedirects, isFalse);
      expect(client.request.cookies, isEmpty);
      expect(response.bodyCancelled, isTrue);
      expect(client.closed, isTrue);
    },
  );
}

class _Transport implements ApiTransport {
  final calls = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': {'bvid': 'BV117BkBsEWw'},
          }),
        ),
      ),
      const {},
    );
  }
}

class _Client implements HttpClient {
  _Client(_Response response) : request = _Request(response);
  final _Request request;
  Uri? uri;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    this.uri = uri;
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  bool followRedirects = true;
  @override
  final cookies = <Cookie>[];
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(String location) : headers = _Headers(location);
  @override
  final HttpHeaders headers;
  @override
  int get statusCode => HttpStatus.found;
  bool bodyCancelled = false;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => StreamController<List<int>>(onCancel: () => bodyCancelled = true).stream
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers(this.location);
  final String location;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
