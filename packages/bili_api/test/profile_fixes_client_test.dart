import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show Transport, cookies, response;

void main() {
  late Transport transport;
  late ProfileClient client;
  setUp(() {
    transport = Transport();
    client = ProfileClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
  });
  test('extended details prefer the current top photo image', () async {
    transport.handler = (uri) => uri.path.endsWith('/nav')
        ? {
            'wbi_img': {
              'img_url':
                  'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
              'sub_url':
                  'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
            },
          }
        : {
            'mid': '7',
            'top_photo': 'https://i0.hdslb.com/old.png',
            'top_photo_v2': {'l_img': 'https://i0.hdslb.com/current.png'},
          };
    expect(
      (await client.loadDetails('7')).bannerUrl.toString(),
      'https://i0.hdslb.com/current.png',
    );
  });
  test(
    'public card requests real space image and maps user decorations',
    () async {
      transport.handler = (uri) {
        expect(uri.queryParameters, {'mid': '7', 'photo': 'true'});
        return {
          'card': {
            'mid': '7',
            'name': '用户',
            'pendant': {'image': '//i0.hdslb.com/pendant.png'},
            'vip': {
              'status': 1,
              'type': 2,
              'label': {
                'text': '年度大会员',
                'use_img_label': true,
                'img_label_uri_hans_static': '//i0.hdslb.com/vip.png',
              },
            },
          },
          'space': {'l_img': '//i0.hdslb.com/banner.png'},
        };
      };
      final result = await client.loadProfile('7');
      expect(result.bannerUrl.toString(), 'https://i0.hdslb.com/banner.png');
      expect(result.pendantUrl.toString(), 'https://i0.hdslb.com/pendant.png');
      expect(
        result.vipLabelImageUrl.toString(),
        'https://i0.hdslb.com/vip.png',
      );
      expect(result.vipStatus, 1);
      expect(result.vipType, 2);
    },
  );
  test('unsafe and absent decoration urls remain absent', () async {
    transport.handler = (_) => {
      'card': {
        'mid': '7',
        'name': '用户',
        'pendant': {'image': 'javascript:bad'},
        'vip': {'status': 0},
      },
      'space': {'l_img': 'https://name:pass@example.com/img'},
    };
    final result = await client.loadProfile('7');
    expect(result.bannerUrl, isNull);
    expect(result.pendantUrl, isNull);
    expect(result.vipLabelImageUrl, isNull);
  });
  for (final flag in [0, 1]) {
    test('space content flags use public-one private-zero $flag', () async {
      transport.handler = (uri) {
        expect(uri.path, '/x/space/setting');
        return {
          'privacy': {'fav_video': flag, 'bangumi': 1 - flag},
        };
      };
      final result = await client.loadContentPrivacy('7');
      expect(result.foldersHidden, flag == 0);
      expect(result.seasonsHidden, flag == 1);
    });
  }
  test('missing privacy is a protocol error', () async {
    transport.handler = (_) => {
      'privacy': {'fav_video': 1},
    };
    await expectLater(
      client.loadContentPrivacy('7'),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'relationship reads preserve blacklist bit and explicit writes use CSRF once',
    () async {
      transport.handler = (uri) {
        expect(uri.path, '/x/relation');
        return {'attribute': 130};
      };
      expect(await client.loadBlocked('7'), isTrue);
      for (final blocked in [true, false]) {
        await client.setBlocked('7', blocked);
        expect(transport.uri?.path, '/x/relation/modify');
        expect(transport.fields, {
          'fid': '7',
          'act': blocked ? '5' : '6',
          're_src': '11',
          'csrf': 'csrf-fixture',
        });
      }
      transport.postResult = response(null, status: 500);
      await expectLater(
        client.setBlocked('7', true),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 3);
    },
  );
}
