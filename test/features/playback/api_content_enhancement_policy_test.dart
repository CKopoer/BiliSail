import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/data/api_content_playback_repository.dart';
import 'package:bilisail/features/playback/data/playback_enhancement_policy.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final highest in [false, true]) {
    test(
      'PGC highest=$highest preserves or overrides request and selection',
      () async {
        final transport = _Transport();
        final repository = _repository(transport, highest: highest);

        final media = await repository.resolve(
          const PgcPlaybackTarget('123'),
          quality: 80,
          cancellation: RequestCancellation(),
        );

        final query = transport.requests.single.queryParameters;
        expect(query['qn'], highest ? '127' : '80');
        expect(query['fnval'], '4048');
        expect(query['fourk'], '1');
        expect(media.quality, highest ? 112 : 80);
      },
    );
  }

  test('PGC is_preview=true cannot be selected as full media', () async {
    final transport = _Transport(preview: true);
    final repository = _repository(transport, highest: true);

    await expectLater(
      repository.resolve(
        const PgcPlaybackTarget('123'),
        quality: 80,
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          AppFailureKind.playback,
        ),
      ),
    );
    expect(transport.requests.single.queryParameters['qn'], '127');
  });
}

ApiContentPlaybackRepository _repository(
  _Transport transport, {
  required bool highest,
}) {
  final requests = ApiRequests();
  final api = BiliApiClient(transport: transport, sessionProvider: requests);
  addTearDown(api.close);
  return ApiContentPlaybackRepository(
    PgcClient(api),
    LiveClient(api),
    requests,
    enhancementPolicy: () async =>
        PlaybackEnhancementPolicy(unlockHighestBitrate: highest),
  );
}

final class _Transport implements ApiTransport {
  _Transport({this.preview = false});

  final bool preview;
  final requests = <Uri>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path != '/pgc/player/web/playurl') {
      throw StateError('Unexpected request ${uri.path}');
    }
    requests.add(uri);
    final data = <String, Object?>{
      'accept_quality': [116, 112, 80],
      'is_preview': preview,
      'dash': {
        'duration': 60,
        'video': [
          for (final quality in [116, 112, 80])
            {
              'id': quality,
              'base_url': 'https://cdn.example/$quality.m4s',
              'codecs': 'avc1.640028',
              'bandwidth': quality * 1000,
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
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
