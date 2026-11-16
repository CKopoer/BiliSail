import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final count in [6000, 6001, 12801]) {
    test('dense $count-element reply keeps a bounded spread of comments', () {
      final items = decodeDanmakuSegment(_segment(count));
      expect(items.length, 6000);
      expect(items.first.id, '1');
      expect(items.last.id, '$count');
      expect(items.map((item) => item.id).toSet(), hasLength(6000));
      for (var minute = 0; minute < 6; minute++) {
        expect(
          items.where((item) => item.progress.inMinutes == minute).length,
          greaterThan(950),
        );
      }
    });
  }

  test('overflow sampling still rejects malformed unretained elements', () {
    final bytes = _segment(6001, invalidContentAt: 1);
    expect(() => decodeDanmakuSegment(bytes), throwsA(isA<ApiFailure>()));
    expect(
      () => decodeDanmakuSegment(
        Uint8List.fromList([..._segment(6001), 10, 8, 58]),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });

  for (final count in [9669, 16001]) {
    test('multi-MiB $count-element reply retains a bounded spread', () {
      final bytes = _segment(count, metadataBytes: 320);
      expect(bytes.length, greaterThan((count == 9669 ? 2 : 4) * 1024 * 1024));
      expect(bytes.length, lessThan(8 * 1024 * 1024));
      final items = decodeDanmakuSegment(bytes);
      expect(items, hasLength(6000));
      expect(items.first.id, '1');
      expect(items.last.id, '$count');
      expect(items.map((item) => item.id).toSet(), hasLength(6000));
      for (var minute = 0; minute < 6; minute++) {
        expect(
          items.where((item) => item.progress.inMinutes == minute).length,
          greaterThan(950),
        );
      }
    });
  }

  for (final bounded in [false, true]) {
    for (final count in [9669, 16001]) {
      test(
        'multi-MiB $count-element API read decodes with bounded=$bounded',
        () async {
          final bytes = _segment(count, metadataBytes: 320);
          final transport = bounded
              ? _BoundedSegmentTransport(bytes)
              : _SegmentTransport(bytes);
          final client = BiliApiClient(transport: transport);
          addTearDown(client.close);
          final items = await client.getDanmakuSegment('42560392051', 1);
          expect(items, hasLength(6000));
          expect(items.first.id, '1');
          expect(items.last.id, '$count');
          expect(transport.calls, 1);
          if (transport is _BoundedSegmentTransport) {
            expect(transport.byteLimit, 8 * 1024 * 1024);
          }
        },
      );
    }

    test(
      'oversized API read fails before decode with bounded=$bounded',
      () async {
        final bytes = Uint8List(8 * 1024 * 1024 + 1);
        final transport = bounded
            ? _BoundedSegmentTransport(bytes)
            : _SegmentTransport(bytes);
        final client = BiliApiClient(
          transport: transport,
          danmakuDecoder: (_) async => fail('Oversized reply must not decode'),
        );
        addTearDown(client.close);
        await expectLater(
          client.getDanmakuSegment('42560392051', 1),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (e) => e.category,
                  'category',
                  ApiFailureCategory.protocol,
                )
                .having((e) => e.endpointId, 'endpoint', 'danmaku_segment'),
          ),
        );
        expect(transport.calls, 1);
      },
    );
  }

  test('multi-MiB reply still validates malformed unretained elements', () {
    expect(
      () => decodeDanmakuSegment(
        _segment(9669, metadataBytes: 320, invalidContentAt: 9666),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('element and string budgets remain bounded', () {
    for (final size in [1025, 4097]) {
      expect(
        () => decodeDanmakuSegment(_segment(2, metadataBytes: size)),
        throwsA(isA<ApiFailure>()),
      );
    }
  });

  test('oversized replies fail at the eight-MiB byte budget', () {
    expect(
      () => decodeDanmakuSegment(Uint8List(8 * 1024 * 1024 + 1)),
      throwsA(isA<ApiFailure>()),
    );
  });
}

// Handwritten, synthetic wire data; no account or real comment contents.
Uint8List _segment(int count, {int? invalidContentAt, int metadataBytes = 0}) {
  final bytes = BytesBuilder(copy: false);
  for (var index = 0; index < count; index++) {
    final element = [
      8,
      ..._varint(index + 1),
      16,
      ..._varint(index * 359999 ~/ (count - 1)),
      24,
      1,
      58,
      1,
      index == invalidContentAt ? 255 : 65,
      if (metadataBytes > 0) ...[
        ..._varint((22 << 3) | 2),
        ..._varint(metadataBytes),
        ...List.filled(metadataBytes, 65),
      ],
    ];
    bytes.add([10, ..._varint(element.length), ...element]);
  }
  return bytes.takeBytes();
}

List<int> _varint(int value) {
  final bytes = <int>[];
  while (value >= 128) {
    bytes.add((value & 127) | 128);
    value >>= 7;
  }
  return [...bytes, value];
}

class _SegmentTransport implements ApiTransport {
  _SegmentTransport(this.bytes);
  final Uint8List bytes;
  var calls = 0;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls++;
    return ApiHttpResponse(200, bytes, const {});
  }
}

final class _BoundedSegmentTransport extends _SegmentTransport
    implements ApiBoundedTransport {
  _BoundedSegmentTransport(super.bytes);
  int? byteLimit;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => fail('Danmaku must use the bounded transport when available');

  @override
  Future<ApiHttpResponse> getBounded(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required int maxBytes,
    ApiCancellation? cancellation,
  }) async {
    calls++;
    byteLimit = maxBytes;
    if (bytes.length > maxBytes) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'transport');
    }
    return ApiHttpResponse(200, bytes, const {});
  }
}
