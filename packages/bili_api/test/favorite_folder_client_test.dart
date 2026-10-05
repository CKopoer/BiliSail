import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _id = '9007199254740993123';
const _info = <String, Object?>{
  'id': _id,
  'upper': {'mid': '7'},
  'title': '音乐',
  'intro': '保留原简介 & + %',
  'attr': 6,
};

ApiHttpResponse _response(Object? data, {int status = 200, int code = 0}) =>
    ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );

void main() {
  late _Transport transport;
  late BiliApiClient api;
  late FavoriteFolderClient client;
  setUp(() {
    transport = _Transport();
    api = BiliApiClient(
      transport: transport,
      cookieJar:
          ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Path=/; Secure',
            'bili_jct=fixture-csrf; Path=/; Secure',
          ]),
    );
    client = FavoriteFolderClient(api);
  });
  tearDown(() => api.close());
  Future<void> save({bool isPrivate = true}) => client.update(
    _id,
    title: '音乐 & + %',
    intro: '第一行\n第二行 +&%',
    isPrivate: isPrivate,
  );
  test(
    'complete metadata preserves large IDs, intro and privacy flags',
    () async {
      final result = await client.load(_id);
      expect(result.id, _id);
      expect(result.ownerMid, '7');
      expect(result.title, '音乐');
      expect(result.intro, _info['intro']);
      expect(result.isPrivate, true);
      expect(transport.uri?.queryParameters, {
        'media_id': _id,
        'pn': '1',
        'ps': '1',
        'platform': 'web',
      });
    },
  );
  for (final field in ['id', 'intro', 'attr', 'upper']) {
    test('missing $field cannot become an editable empty value', () async {
      transport.info = {..._info}..remove(field);
      await expectLater(
        client.load(_id),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
      expect(transport.posts, 0);
    });
  }
  test('response must belong to requested folder', () async {
    transport.info = {..._info, 'id': '5'};
    await expectLater(client.load(_id), throwsA(isA<ApiFailure>()));
  });
  test(
    'form retains raw text and CSRF and uses correct privacy values',
    () async {
      await save();
      expect(transport.uri?.path, '/x/v3/fav/folder/edit');
      expect(transport.fields, {
        'media_id': _id,
        'title': '音乐 & + %',
        'intro': '第一行\n第二行 +&%',
        'privacy': '1',
        'csrf': 'fixture-csrf',
      });
      await save(isPrivate: false);
      expect(transport.fields['privacy'], '0');
    },
  );
  test('missing Cookie/CSRF prevents transmission', () async {
    final guest = BiliApiClient(transport: transport);
    addTearDown(guest.close);
    await expectLater(
      FavoriteFolderClient(
        guest,
      ).update(_id, title: '音乐', intro: '', isPrivate: false),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.authentication,
        ),
      ),
    );
    expect(transport.posts, 0);
  });
  test('a server error is sent once without replay', () async {
    transport.result = _response(null, status: 503);
    await expectLater(save(), throwsA(isA<ApiFailure>()));
    expect(transport.posts, 1);
  });
  test('cancelled context and invalid IDs never transmit', () async {
    final cancellation = ApiCancellation()..cancel();
    await expectLater(
      client.update(
        _id,
        title: '音乐',
        intro: '',
        isPrivate: false,
        context: ApiRequestContext(cancellation: cancellation),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    await expectLater(
      client.update('ugc:42', title: '音乐', intro: '', isPrivate: false),
      throwsArgumentError,
    );
    expect(transport.posts, 0);
  });
}

final class _Transport implements ApiTransport, ApiFormTransport {
  Map<String, Object?> info = _info;
  ApiHttpResponse result = _response(null);
  Uri? uri;
  Map<String, String> fields = {};
  int posts = 0;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    return _response({'info': info, 'medias': null});
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.fields = fields;
    posts++;
    return result;
  }
}
