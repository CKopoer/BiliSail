import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _show = ApiRecommendationEvent(
  click: false,
  id: '42',
  cid: '17',
  goto: 'av',
  cardGoto: 'av',
  trackId: 'batch-track',
  freshType: 4,
  position: 3,
  row: 2,
  column: 1,
  timestamp: 1000,
);
const _click = ApiRecommendationEvent(
  click: true,
  id: '42',
  cid: '17',
  goto: 'av',
  cardGoto: 'av',
  trackId: 'batch-track',
  freshType: 4,
  position: 3,
  row: 2,
  column: 1,
  timestamp: 1001,
);

void main() {
  late _Transport transport;
  late BiliApiClient api;
  setUp(() {
    transport = _Transport();
    api = BiliApiClient(
      transport: transport,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1200),
    );
    api.cookieJar.receive(Uri.https('www.bilibili.com'), [
      'SESSDATA=private; Domain=.bilibili.com; Secure',
      'DedeUserID=77; Domain=.bilibili.com; Secure',
      'buvid3=web-device; Domain=.bilibili.com; Secure',
    ]);
  });

  test(
    'HTTP transport sends raw bytes once and does not follow redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final transport = DioApiTransport();
      addTearDown(transport.close);
      final requests = <(String, String, String?, List<int>)>[];
      server.listen((request) async {
        final received = await request.fold(
          <int>[],
          (body, chunk) => body..addAll(chunk),
        );
        requests.add((
          request.method,
          request.uri.path,
          request.headers.contentType?.mimeType,
          received,
        ));
        request.response.statusCode = request.uri.path == '/log' ? 307 : 200;
        request.response.headers.set(HttpHeaders.locationHeader, '/redirected');
        await request.response.close();
      });
      final bytes = Uint8List.fromList([0, 128, 255, 10]);
      final response = await transport.postBytes(
        Uri.http('127.0.0.1:${server.port}', '/log'),
        bytes: bytes,
        contentType: 'text/plain',
        headers: {},
        timeout: const Duration(seconds: 3),
      );
      expect(response.statusCode, 307);
      expect(requests, hasLength(1));
      final (method, path, type, received) = requests.single;
      expect((method, path, type), ('POST', '/log', 'text/plain'));
      expect(received, bytes);
    },
  );

  for (final desktop in [false, true]) {
    test(
      'Web protobuf batches impressions and preserves clicks (desktop=$desktop)',
      () async {
        await api.recommendationReports.send(
          [_show, _show, _click],
          desktop: desktop,
          context: const ApiRequestContext(),
        );
        expect(transport.uri.host, 'data.bilibili.com');
        expect(transport.uri.path, '/v2/log/web');
        expect(transport.uri.queryParameters['content_type'], 'pbrequest');
        expect(transport.contentType, 'text/plain');
        final events = _fields(transport.body)[1]!.cast<Uint8List>();
        expect(events, hasLength(2));
        final show = _fields(events.first);
        expect(_text(show, 1), '021436');
        expect(_text(show, 2), '333.1007.tianma.feed-card.show');
        final body = _nested(show, 3);
        expect(body[9], [2]);
        expect(_nested(body, 1)[4], [77]);
        expect(_text(_nested(body, 1), 3), 'web-device');
        final fields = _map(_nested(body, 11), 1);
        expect(fields['card_num'], '2');
        final shown = jsonDecode(fields['showlist']!) as List;
        expect(shown.first, {
          'id': 42,
          'content_type_id': 42,
          'cid': 17,
          'track_id': 'batch-track',
          'goto': 'av',
          'location': 3,
          'line_location': 2,
          'column_location': 1,
          'feed_version': desktop ? 'V1' : 'V8',
        });
        final click = _fields(events.last);
        expect(_text(click, 2), '333.1007.tianma.feed-card.click');
        final clicked = _map(_nested(_nested(click, 3), 12), 4);
        expect(clicked['track_id'], 'batch-track');
        expect(clicked['content_id'], '42');
        expect(transport.headers.containsKey('Cookie'), isFalse);
        expect(latin1.decode(transport.body), isNot(contains('private')));
      },
    );
  }

  test(
    'Android posts two individually framed AppEvents under the HD feed identity',
    () async {
      await api.recommendationReports.send(
        [_show, _click],
        appBuvid: 'app-device',
        appMid: '13',
        context: const ApiRequestContext(),
      );
      expect(
        transport.uri.toString(),
        'https://dataflow.biliapi.com/log/pbmobile/unrealtime?android',
      );
      expect(transport.contentType, 'application/octet-stream');
      expect(transport.headers['Neuron-Events'], '2');
      final bytes = transport.body;
      final data = ByteData.sublistView(bytes);
      var offset = 0;
      for (final click in [false, true]) {
        expect(ascii.decode(bytes.sublist(offset, offset + 4)), 'RDIO');
        final length = data.getUint32(offset + 4);
        final end = offset + 9 + (length & 0x7fffffff);
        expect(length >> 31, 1);
        // Check bytes from the reference Android RDIO length-checksum table.
        expect(bytes[offset + 8], click ? 18 : 89);
        offset += 9;
        final metadata = <String, String>{};
        int valueLength;
        do {
          final keyLength = bytes[offset++];
          final key = ascii.decode(bytes.sublist(offset, offset + keyLength));
          offset += keyLength;
          valueLength = data.getUint32(offset);
          offset += 4;
          final valueEnd = offset + (valueLength & 0x7fffffff);
          metadata[key] = utf8.decode(bytes.sublist(offset, valueEnd));
          offset = valueEnd;
        } while (valueLength >> 31 == 1);
        final name = click
            ? 'tm.recommend.main-card.0.click'
            : 'tm.recommend.feed-card.0.show';
        expect(metadata, {
          'logId': '001538',
          'eventId': name,
          'appId': '5',
          'appVersionCode': '2001100',
          'platform': '3',
        });
        final event = _fields(bytes.sublist(offset, end));
        expect(_text(event, 1), name);
        expect(_text(_nested(event, 2), 3), 'app-device');
        expect(_text(event, 4), '13');
        expect(event[9], [click ? 2 : 3]);
        expect(_nested(event, click ? 11 : 12), isEmpty);
        expect(_map(event, 13), containsPair('track_id', 'batch-track'));
        expect(_map(event, 13), containsPair('param', '42'));
        offset = end;
      }
      expect(offset, bytes.length);
      expect(transport.headers.containsKey('Cookie'), isFalse);
    },
  );

  test(
    'redirects and server failures stop after one attempt; cancellation sends nothing',
    () async {
      for (final status in [302, 503]) {
        transport.status = status;
        await expectLater(
          api.recommendationReports.send([
            _show,
          ], context: const ApiRequestContext()),
          throwsA(isA<ApiFailure>()),
        );
      }
      final signal = ApiCancellation()..cancel();
      await expectLater(
        api.recommendationReports.send([
          _click,
        ], context: ApiRequestContext(cancellation: signal)),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.attempts, 2);
    },
  );
}

typedef _Fields = Map<int, List<Object>>;
_Fields _fields(Uint8List bytes) {
  int offset = 0;
  int varint() {
    int value = 0, shift = 0;
    while (true) {
      final byte = bytes[offset++];
      value |= (byte & 127) << shift;
      if (byte < 128) return value;
      shift += 7;
    }
  }

  final fields = <int, List<Object>>{};
  while (offset < bytes.length) {
    final tag = varint();
    final field = fields.putIfAbsent(tag >> 3, () => []);
    if ((tag & 7) == 0) {
      field.add(varint());
    } else {
      expect(tag & 7, 2);
      final size = varint();
      field.add(bytes.sublist(offset, offset + size));
      offset += size;
    }
  }
  return fields;
}

_Fields _nested(_Fields message, int key) =>
    _fields(message[key]!.single as Uint8List);
String _text(_Fields message, int key) =>
    utf8.decode(message[key]!.single as Uint8List);
Map<String, String> _map(_Fields message, int key) => {
  for (final entry in message[key]!.cast<Uint8List>().map(_fields))
    _text(entry, 1): _text(entry, 2),
};

class _Transport implements ApiTransport, ApiBytesTransport {
  int attempts = 0, status = 200;
  late Uri uri;
  late String contentType;
  late Uint8List body;
  late Map<String, String> headers;
  @override
  Future<ApiHttpResponse> postBytes(
    Uri uri, {
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    attempts++;
    this.uri = uri;
    body = bytes;
    this.headers = headers;
    this.contentType = contentType;
    return ApiHttpResponse(status, Uint8List(0), {});
  }

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => throw UnsupportedError('GET');
}
