import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'danmaku protobuf field nine supplies weight without breaking older elements',
    () {
      for (final weight in [null, 0, 5, 10, 20]) {
        final element = [
          8,
          1,
          16,
          0,
          24,
          1,
          58,
          1,
          65,
          if (weight != null) ...[72, weight],
        ];
        final bytes = Uint8List.fromList([10, element.length, ...element]);
        final event = decodeDanmakuSegment(bytes).single;
        expect(event.content, 'A');
        expect(event.weight, (weight ?? 0).clamp(0, 10));
      }
    },
  );
}
