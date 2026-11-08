import 'dart:typed_data';

import 'package:bili_player/src/mp4_buffer_index.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List box(String name, List<int> body) =>
    Uint8List.fromList([...u32(body.length + 8), ...name.codeUnits, ...body]);
List<int> u32(int n) => [n >> 24 & 255, n >> 16 & 255, n >> 8 & 255, n & 255];
List<int> u64(int n) => [...u32(n >> 32), ...u32(n & 0xffffffff)];

Uint8List indexedMedia({
  int count = 4,
  int segmentSize = 100,
  int version = 0,
}) {
  final index = box('sidx', [
    version,
    0,
    0,
    0,
    ...u32(1),
    ...u32(1000),
    if (version == 0) ...[...u32(0), ...u32(0)] else ...[...u64(0), ...u64(0)],
    0,
    0,
    count >> 8,
    count & 255,
    for (var i = 0; i < count; i++) ...[
      ...u32(segmentSize),
      ...u32(2000),
      ...u32(0x90000000),
    ],
  ]);
  return Uint8List.fromList([
    ...index,
    ...List.generate(count * segmentSize, (i) => i % 251),
  ]);
}

void main() {
  for (final version in [0, 1]) {
    test(
      'sidx v$version uses complete contiguous segments and exact offsets',
      () {
        final bytes = indexedMedia(version: version);
        final index = Mp4BufferIndex.parse(bytes)!;
        final start = bytes.length - 400;
        expect(index.spans.first.offset, start);
        expect(
          index.buffered(
            Duration.zero,
            (offset, size) => offset + size <= start + 299,
          ),
          const Duration(seconds: 4),
        );
        expect(
          index.buffered(
            Duration.zero,
            (offset, size) => offset >= start + 100,
          ),
          Duration.zero,
        );
        expect(
          index.buffered(
            const Duration(seconds: 4),
            (offset, size) => offset >= start + 200,
          ),
          const Duration(seconds: 8),
        );
        expect(
          index.buffered(const Duration(seconds: 8), (offset, size) => true),
          const Duration(seconds: 8),
        );
      },
    );
  }
  test('incomplete and malformed indexes stay unknown', () {
    final media = indexedMedia();
    for (var n = 0; n < 80; n++) {
      expect(Mp4BufferIndex.parse(Uint8List.sublistView(media, 0, n)), isNull);
    }
    final invalid = Uint8List.fromList(media);
    invalid[32] = 0x80; // Hierarchical reference, not a direct media segment.
    expect(Mp4BufferIndex.parse(invalid), isNull);
    final zeroScale = Uint8List.fromList(media)..fillRange(16, 20, 0);
    expect(Mp4BufferIndex.parse(zeroScale), isNull);
  });
  test('ordinary single-track MP4 sample tables map bytes to media time', () {
    final table = box('stbl', [
      ...box('stco', [...u32(0), ...u32(2), ...u32(1000), ...u32(1200)]),
      ...box('stsc', [...u32(0), ...u32(1), ...u32(1), ...u32(2), ...u32(1)]),
      ...box('stsz', [...u32(0), ...u32(100), ...u32(4)]),
      ...box('stts', [...u32(0), ...u32(1), ...u32(4), ...u32(1000)]),
    ]);
    final media = box('moov', [
      ...box('trak', [
        ...box('mdia', [
          ...box('mdhd', [...u32(0), ...u32(0), ...u32(0), ...u32(1000)]),
          ...box('minf', table),
        ]),
      ]),
    ]);
    final index = Mp4BufferIndex.parse(media)!;
    expect(index.spans.map((s) => (s.offset, s.length)), [
      (1000, 200),
      (1200, 200),
    ]);
    expect(
      index.buffered(Duration.zero, (offset, size) => offset < 1200),
      const Duration(seconds: 2),
    );
    expect(
      index.buffered(Duration.zero, (offset, size) => true),
      const Duration(seconds: 4),
    );
  });
}
