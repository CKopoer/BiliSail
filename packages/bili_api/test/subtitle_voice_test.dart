import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test('subtitle identity and AI fields survive both metadata paths', () async {
    final transport = _Transport({
      'subtitle': {
        'subtitles': [
          {
            'id_str': '9007199254740993',
            'lan': 'ai-zh',
            'lan_doc': '中文',
            'type': 1,
            'ai_type': 0,
            'ai_status': 2,
            'subtitle_url': 'https://aisubtitle.hdslb.com/subtitle.json',
          },
          {
            'id_str': '2',
            'lan': 'unknown',
            'lan_doc': 'Unknown',
            'type': 77,
            'ai_type': 8,
            'ai_status': 9,
            'subtitle_url': 'https://aisubtitle.hdslb.com/unknown.json',
          },
        ],
      },
    });
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    for (final tracks in [
      await api.getSubtitleTracks('1', '2'),
      (await PlaybackMetadataClient(api).load('1', '2')).subtitles,
    ]) {
      expect(tracks.first.id, '9007199254740993');
      expect(tracks.first.languageCode, 'ai-zh');
      expect(tracks.first.type, 1);
      expect(tracks.first.aiType, 0);
      expect(tracks.first.aiStatus, 2);
      expect(tracks.last.type, 77);
      expect(tracks.last.aiType, 8);
    }
  });

  test(
    'valid empty subtitle cues do not discard neighboring dialogue',
    () async {
      final api = BiliApiClient(
        transport: _Transport({
          'body': [
            {'from': 1, 'to': 2, 'content': 'Before'},
            {'from': 153.03, 'to': 153.43, 'content': ''},
            {'from': 154, 'to': 155, 'content': '  '},
            {'from': 156, 'to': 157, 'content': 'After'},
          ],
        }),
      );
      addTearDown(api.close);
      final cues = await api.getSubtitleCues(
        Uri.https('aisubtitle.hdslb.com', '/s.json'),
      );
      expect(cues.map((cue) => cue.text), ['Before', 'After']);
      expect(cues.last.start, const Duration(seconds: 156));
    },
  );

  for (final row in [
    {'from': 1, 'to': 2, 'content': null},
    {'from': -1, 'to': 2, 'content': ''},
    {'from': 2, 'to': 1, 'content': ''},
    {'from': 'bad', 'to': 2, 'content': ''},
  ]) {
    test('malformed cue remains a protocol failure: $row', () async {
      final api = BiliApiClient(
        transport: _Transport({
          'body': [row],
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.getSubtitleCues(Uri.https('aisubtitle.hdslb.com', '/s.json')),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }

  test(
    'voice capability and selection parameters are mapped and WBI signed',
    () async {
      final transport = _Transport(_playData);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final info = await api.getPlayInfo(
        'BV1xx411c7mD',
        '2',
        language: 'en',
        productionType: 2,
      );
      expect(info.voices, hasLength(2));
      expect(info.voices.first.languageCode, 'en');
      expect(info.voices.first.subtitleLanguage, 'ai-en');
      expect(info.voices.first.videoDetext, isTrue);
      expect(info.voices.first.videoMouthShapeChange, isFalse);
      expect(info.voices.last.productionType, 1);
      expect(info.currentLanguage, 'en');
      expect(info.productionType, 2);
      final query = transport.uris.last.queryParameters;
      expect(query['cur_language'], 'en');
      expect(query['cur_production_type'], '2');
      expect(query['client_attr'], '1');
      expect(query['w_rid'], isNotEmpty);
      await api.getPlayInfo('BV1xx411c7mD', '2');
      expect(transport.uris.last.queryParameters['cur_language'], '');
      expect(transport.uris.last.queryParameters['cur_production_type'], '0');
    },
  );

  test(
    'absent or disabled voice capability does not expose translated subtitles as voice',
    () async {
      for (final language in [
        null,
        {'support': false, 'items': (_playData['language'] as Map)['items']},
      ]) {
        final api = BiliApiClient(
          transport: _Transport({..._playData, 'language': language}),
        );
        expect((await api.getPlayInfo('BV1xx411c7mD', '2')).voices, isEmpty);
        api.close();
      }
    },
  );
}

final _playData = <String, Object?>{
  'cur_language': 'en',
  'cur_production_type': 2,
  'language': {
    'support': true,
    'items': [
      {
        'lang': 'en',
        'title': 'English',
        'subtitle_lang': 'ai-en',
        'production_type': 2,
        'video_detext': true,
        'video_mouth_shape_change': false,
      },
      {'lang': 'en', 'title': 'Duplicate', 'production_type': 2},
      {'lang': 'fr', 'title': 'Français', 'production_type': 1},
      {'lang': 'xx', 'production_type': 99},
    ],
  },
  'accept_quality': [80],
  'dash': {
    'duration': 180,
    'video': [
      {'id': 80, 'base_url': 'https://cdn.example/video', 'codecs': 'avc1'},
    ],
    'audio': [
      {
        'id': 30280,
        'base_url': 'https://cdn.example/audio',
        'codecs': 'mp4a.40.2',
      },
    ],
  },
};

final class _Transport implements ApiTransport {
  _Transport(this.data);
  final Map<String, Object?> data;
  final uris = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            uri.host == 'aisubtitle.hdslb.com'
                ? data
                : {
                    'code': 0,
                    'data': uri.path == '/x/web-interface/nav'
                        ? {
                            'wbi_img': {
                              'img_url': 'https://i0.hdslb.com/${'a' * 32}.png',
                              'sub_url': 'https://i0.hdslb.com/${'b' * 32}.png',
                            },
                          }
                        : data,
                  },
          ),
        ),
      ),
      const {},
    );
  }
}
