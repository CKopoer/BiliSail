import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'official OP/ED use seconds, preserve precision and immutable bounds',
    () async {
      final result = await _load([
        {'clipType': 'CLIP_TYPE_OP', 'start': 0, 'end': 16.125},
        {'clipType': 'CLIP_TYPE_ED', 'start': 110, 'end': 120.5},
      ]);
      expect(result.pgcSkipSegments.map((s) => s.type), [
        ApiPgcSkipType.intro,
        ApiPgcSkipType.outro,
      ]);
      expect(result.pgcSkipSegments.first.start, Duration.zero);
      expect(
        result.pgcSkipSegments.first.end,
        const Duration(milliseconds: 16125),
      );
      expect(result.pgcSkipSegments.last.end, result.duration);
      expect(() => result.pgcSkipSegments.clear(), throwsUnsupportedError);
    },
  );

  test(
    'optional malformed clips do not hide valid tracks or valid siblings',
    () async {
      final result = await _load([
        null,
        1,
        'invalid',
        {'clipType': 'UNKNOWN', 'start': 0, 'end': 10},
        {'clipType': 'CLIP_TYPE_OP', 'start': -1, 'end': 10},
        {'clipType': 'CLIP_TYPE_OP', 'start': 10, 'end': 10},
        {'clipType': 'CLIP_TYPE_OP', 'start': 20, 'end': 10},
        {'clipType': 'CLIP_TYPE_OP', 'start': 0, 'end': 121},
        {'clipType': 'CLIP_TYPE_OP', 'start': 0, 'end': 'NaN'},
        {'clipType': 'CLIP_TYPE_OP', 'start': 'Infinity', 'end': 20},
        {'clipType': 'CLIP_TYPE_OP', 'start': 0, 'end': 0.0001},
        {'clipType': 'CLIP_TYPE_ED', 'start': 110, 'end': 120},
      ]);
      expect(result.dashVideo, hasLength(1));
      expect(result.dashAudio, hasLength(1));
      expect(result.pgcSkipSegments, hasLength(1));
      expect(result.pgcSkipSegments.single.type, ApiPgcSkipType.outro);
    },
  );

  for (final malformed in [null, 'invalid', 1, <String, Object?>{}]) {
    test(
      'missing or malformed clip list degrades to no skip: $malformed',
      () async {
        expect((await _load(malformed)).pgcSkipSegments, isEmpty);
      },
    );
  }

  for (final preview in [true, 1, '1']) {
    test('preview cannot use full episode skip intervals: $preview', () async {
      final result = await _load([
        {'clipType': 'CLIP_TYPE_OP', 'start': 0, 'end': 10},
      ], preview: preview);
      expect(result.isPreview, isTrue);
      expect(result.pgcSkipSegments, isEmpty);
    });
  }

  test('clip metadata has a fixed capacity', () async {
    final result = await _load(
      List.generate(
        1000,
        (_) => {'clipType': 'CLIP_TYPE_OP', 'start': 0, 'end': 10},
      ),
    );
    expect(result.pgcSkipSegments, hasLength(64));
  });
}

Future<ApiPlayInfo> _load(Object? clips, {Object? preview = false}) async {
  final api = BiliApiClient(transport: _Transport(clips, preview));
  try {
    return await PgcClient(api).getPlayInfo('317925');
  } finally {
    api.close();
  }
}

final class _Transport implements ApiTransport {
  _Transport(this.clips, this.preview);
  final Object? clips, preview;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'result': {
            'is_preview': preview,
            'clip_info_list': clips,
            'dash': {
              'duration': 120.5,
              'video': [
                {
                  'id': 32,
                  'base_url': 'https://cdn.example/video.m4s',
                  'codecs': 'avc1',
                },
              ],
              'audio': [
                {
                  'id': 30280,
                  'base_url': 'https://cdn.example/audio.m4s',
                  'codecs': 'mp4a.40.2',
                },
              ],
            },
          },
        }),
      ),
    ),
    const {},
  );
}
