import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'home_client_test.dart' show Transport;

Map<String, Object?> previewResponse({int status = 1}) => {
  'code': 0,
  'data': {
    'room_id': '9007199254740993',
    'live_status': status,
    'playurl_info': {
      'playurl': {
        'stream': [
          {
            'protocol_name': 'http_hls',
            'format': [
              {
                'format_name': 'fmp4',
                'codec': [
                  {
                    'codec_name': 'avc',
                    'current_qn': 80,
                    'accept_qn': [80, 150],
                    'base_url': '/live/preview.m3u8',
                    'url_info': [
                      {
                        'host': 'https://live.bilivideo.com',
                        'extra': '?token=a%2Fb&v=1',
                      },
                      {
                        'host': 'https://backup.bilivideo.com',
                        'extra': '?token=c%2Fd&v=2',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    },
  },
};

void main() {
  test(
    'homepage profile preserves room IDs and complete server URLs',
    () async {
      final transport = Transport((_) => previewResponse());
      final api = BiliApiClient(
        transport: transport,
        prepareWebRequests: false,
      );
      addTearDown(api.close);
      final info = await LiveClient(api).getPreviewInfo('9007199254740993');
      final request = transport.requests.single;
      expect(request.host, 'api.live.bilibili.com');
      expect(request.path, '/xlive/web-room/v2/index/getRoomPlayInfo');
      expect(request.queryParameters, {
        'room_id': '9007199254740993',
        'no_playurl': '0',
        'mask': '1',
        'qn': '0',
        'platform': 'web',
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0,1',
        'special_scenario': '2',
      });
      expect(info.roomId, '9007199254740993');
      expect(info.streams.single.format, 'fmp4');
      expect(info.streams.single.codec, 'avc');
      expect(info.streams.single.urls.map((url) => url.toString()), [
        'https://live.bilivideo.com/live/preview.m3u8?token=a%2Fb&v=1',
        'https://backup.bilivideo.com/live/preview.m3u8?token=c%2Fd&v=2',
      ]);
    },
  );

  for (final field in ['is_locked', 'encrypted']) {
    for (final value in [true, 1]) {
      test('$field=$value rejects restricted previews', () async {
        final response = previewResponse();
        (response['data'] as Map<String, Object?>)[field] = value;
        final api = BiliApiClient(
          transport: Transport((_) => response),
          prepareWebRequests: false,
        );
        addTearDown(api.close);
        await expectLater(
          LiveClient(api).getPreviewInfo('12'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.category,
              'category',
              ApiFailureCategory.permission,
            ),
          ),
        );
      });
    }
  }

  test('offline rooms need no media, live rooms require a stream', () async {
    for (final status in [0, 1]) {
      final api = BiliApiClient(
        transport: Transport(
          (_) => {
            'code': 0,
            'data': {'room_id': 12, 'live_status': status},
          },
        ),
        prepareWebRequests: false,
      );
      addTearDown(api.close);
      final pending = LiveClient(api).getPreviewInfo('12');
      if (status == 0) {
        expect((await pending).streams, isEmpty);
      } else {
        await expectLater(pending, throwsA(isA<ApiFailure>()));
      }
    }
  });

  test('invalid room IDs never request the network', () async {
    final transport = Transport((_) => previewResponse());
    final api = BiliApiClient(transport: transport, prepareWebRequests: false);
    addTearDown(api.close);
    for (final id in ['0', '-1', 'x', '1.2']) {
      await expectLater(
        LiveClient(api).getPreviewInfo(id),
        throwsArgumentError,
      );
    }
    expect(transport.requests, isEmpty);
  });
}
