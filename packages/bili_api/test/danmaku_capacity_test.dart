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

  test('oversized replies retain the existing byte budget', () {
    expect(
      () => decodeDanmakuSegment(Uint8List(2 * 1024 * 1024 + 1)),
      throwsA(isA<ApiFailure>()),
    );
  });
}

// Handwritten, synthetic wire data; no account or real comment contents.
Uint8List _segment(int count, {int? invalidContentAt}) {
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
