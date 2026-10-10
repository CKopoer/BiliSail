import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const video = VideoId('BV1abc123456');
  late ApiRequests requests;
  setUp(() => requests = ApiRequests());

  ApiPlaybackRepository repository({
    Map<String, Object?> patch = const {},
    Future<({int width, int height})> Function(Uri)? dimensions,
  }) {
    final api = BiliApiClient(
      transport: _Transport({..._shot, ...patch}),
      sessionProvider: requests,
    );
    addTearDown(api.close);
    return ApiPlaybackRepository(api, requests, imageDimensions: dimensions);
  }

  final protocolFailure = throwsA(
    isA<AppFailure>().having((e) => e.kind, 'kind', AppFailureKind.protocol),
  );

  test('known tile dimensions do not download an image for metadata', () async {
    final shot = await repository(
      patch: {'img_x_size': 480, 'img_y_size': 270},
      dimensions: (_) async => throw StateError('Unnecessary image read'),
    ).storyboard(video, '2', cancellation: RequestCancellation());
    expect(shot?.tileWidth, 480);
    expect(shot?.tileHeight, 270);
  });

  for (final dimensions in [(0, 0), (256, 0), (0, 144)]) {
    test(
      'resolves missing PGC dimensions $dimensions across two sheets',
      () async {
        final reads = <Uri>[];
        final shot = await repository(
          patch: {'img_x_size': dimensions.$1, 'img_y_size': dimensions.$2},
          dimensions: (uri) async {
            reads.add(uri);
            return (width: 2560, height: 1440);
          },
        ).storyboard(video, '2', cancellation: RequestCancellation());
        expect(shot?.tileWidth, 256);
        expect(shot?.tileHeight, 144);
        expect(shot?.aspectRatio, 16 / 9);
        expect(shot?.times, hasLength(186));
        expect(reads.single.toString(), 'https://i0.hdslb.com/sheet-1.jpg');
        expect(
          shot?.frameAt(const Duration(seconds: 600))?.image.path,
          '/sheet-2.jpg',
        );
        expect(shot?.frameAt(const Duration(seconds: 1110))?.column, 5);
        expect(shot?.frameAt(const Duration(seconds: 1110))?.row, 8);
      },
    );
  }

  test(
    'derives rectangular grid dimensions rather than assuming 16:9',
    () async {
      final shot = await repository(
        patch: {
          'img_x_len': 4,
          'img_y_len': 2,
          'index': [0, 0, 6],
        },
        dimensions: (_) async => (width: 800, height: 300),
      ).storyboard(video, '2', cancellation: RequestCancellation());
      expect(shot?.tileWidth, 200);
      expect(shot?.tileHeight, 150);
      expect(shot?.aspectRatio, 4 / 3);
    },
  );

  for (final size in [
    (width: 2561, height: 1440),
    (width: 2560, height: 1441),
    (width: 0, height: 1440),
    (width: 2560, height: 0),
    (width: 40970, height: 1440),
    (width: 2560, height: 40970),
  ]) {
    test(
      'rejects invalid or excessive inferred tile dimensions $size',
      () async {
        await expectLater(
          repository(dimensions: (_) async => size)
              .storyboard(video, '2', cancellation: RequestCancellation()),
          protocolFailure,
        );
      },
    );
  }

  test('rejects a supplied dimension that conflicts with the sheet', () async {
    await expectLater(
      repository(
        patch: {'img_x_size': 480},
        dimensions: (_) async => (width: 2560, height: 1440),
      ).storyboard(video, '2', cancellation: RequestCancellation()),
      protocolFailure,
    );
  });

  test('malformed indexes fail before downloading an image', () async {
    await expectLater(
      repository(
        patch: {
          'index': [0, 0, 6, 5],
        },
        dimensions: (_) async => throw StateError('Unnecessary image read'),
      ).storyboard(video, '2', cancellation: RequestCancellation()),
      protocolFailure,
    );
  });

  for (final sample in [
    (error: const SocketException('offline'), kind: AppFailureKind.network),
    (error: const HttpException('rejected'), kind: AppFailureKind.network),
    (error: const ImageQueueFull(), kind: AppFailureKind.network),
    (error: TimeoutException('deadline'), kind: AppFailureKind.timeout),
    (
      error: const FormatException('invalid image'),
      kind: AppFailureKind.protocol,
    ),
    (error: const ImageLoadCancelled(), kind: AppFailureKind.cancelled),
  ]) {
    test(
      'classifies image dimension failure ${sample.error.runtimeType}',
      () async {
        await expectLater(
          repository(dimensions: (_) async => throw sample.error)
              .storyboard(video, '2', cancellation: RequestCancellation()),
          throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', sample.kind)),
        );
      },
    );
  }

  for (final changeAccount in [false, true]) {
    test(
      'cancels a pending image dimension read; account change=$changeAccount',
      () async {
        final started = Completer<void>();
        final pending = Completer<({int width, int height})>();
        final cancellation = RequestCancellation();
        final read = repository(
          dimensions: (_) {
            started.complete();
            return pending.future;
          },
        ).storyboard(video, '2', cancellation: cancellation);
        final assertion = expectLater(
          read,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        await started.future;
        if (changeAccount) {
          requests.advanceSession();
        } else {
          cancellation.cancel();
        }
        await assertion;
        // The cancelled consumer finishes before the shared image-cache task.
        pending.complete((width: 2560, height: 1440));
        await Future<void>.delayed(Duration.zero);
      },
    );
  }
}

final _shot = {
  'img_x_len': 10,
  'img_y_len': 10,
  'img_x_size': 0,
  'img_y_size': 0,
  'image': ['//i0.hdslb.com/sheet-1.jpg', '//i0.hdslb.com/sheet-2.jpg'],
  'index': [0, ...List.generate(186, (i) => i * 6)],
};

final class _Transport implements ApiTransport {
  const _Transport(this.shot);
  final Map<String, Object?> shot;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': shot}))),
    const {},
  );
}
