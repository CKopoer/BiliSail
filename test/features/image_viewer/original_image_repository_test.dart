import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/data/network_original_image_repository.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Uri.parse('https://i0.hdslb.com/long.png');
  test(
    'private message CDN originals load without rewriting their URL',
    () async {
      final bytes = _png(4, 6);
      final sources = <Uri>[];
      final repository = NetworkOriginalImageRepository(
        loader: (uri, _) async {
          sources.add(uri);
          return bytes;
        },
      );
      for (final scheme in ['https', 'http']) {
        final source = Uri.parse(
          '$scheme://message.biliimg.com/bfs/im/fixture.jpg?fixture=original',
        );
        final image = await repository.load(source, RequestCancellation());
        expect(sources.last, source.replace(scheme: 'https'));
        expect(image.bytes, bytes);
        expect((image.width, image.height), (4, 6));
      }
    },
  );

  test('message CDN support still rejects untrusted original URLs', () async {
    var loads = 0;
    final repository = NetworkOriginalImageRepository(
      loader: (_, _) async {
        loads++;
        return _png(4, 6);
      },
    );
    for (final url in [
      'https://message.biliimg.com.example.com/image.jpg',
      'https://other.biliimg.com/image.jpg',
      'https://biliimg.com/image.jpg',
      'https://user:password@message.biliimg.com/image.jpg',
      'file:///message.biliimg.com/image.jpg',
    ]) {
      await expectLater(
        repository.load(Uri.parse(url), RequestCancellation()),
        throwsFormatException,
        reason: url,
      );
    }
    expect(loads, 0);
  });

  test(
    'long and wide originals over 16384 load and decode a bounded preview',
    () async {
      for (final (width, height) in [(128, 24000), (24000, 128)]) {
        final bytes = _png(width, height);
        final repository = NetworkOriginalImageRepository(
          loader: (_, _) async => bytes,
        );
        final image = await repository.load(source, RequestCancellation());
        expect(image.bytes, bytes);
        expect((image.width, image.height), (width, height));
        expect(image.scaledPreview, isTrue);
        expect(image.previewWidth, lessThanOrEqualTo(8192));
        expect(image.previewHeight, lessThanOrEqualTo(8192));
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final codec = await descriptor.instantiateCodec(
          targetWidth: image.previewWidth,
          targetHeight: image.previewHeight,
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, image.previewWidth);
        expect(frame.image.height, image.previewHeight);
        frame.image.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    },
  );

  test(
    'source dimensions, pixel and encoded byte budgets stay bounded',
    () async {
      for (final (width, height) in [(8192, 8193), (1, 262145)]) {
        final repository = NetworkOriginalImageRepository(
          loader: (_, _) async => _png(width, height, headerOnly: true),
        );
        await expectLater(
          repository.load(source, RequestCancellation()),
          throwsA(isA<OriginalImageLimit>()),
        );
      }
      final oversized = NetworkOriginalImageRepository(
        loader: (_, _) async =>
            Uint8List(NetworkOriginalImageRepository.maxBytes + 1),
      );
      await expectLater(
        oversized.load(source, RequestCancellation()),
        throwsA(isA<OriginalImageLimit>()),
      );
      final image = OriginalImage(
        bytes: Uint8List(1),
        width: 8192,
        height: 8192,
      );
      expect(
        image.previewWidth * image.previewHeight,
        lessThanOrEqualTo(16 * 1024 * 1024),
      );
    },
  );

  test('cancellation during transport rejects late original bytes', () async {
    final cancellation = RequestCancellation();
    final repository = NetworkOriginalImageRepository(
      loader: (_, _) async {
        cancellation.cancel();
        return _png(4, 4);
      },
    );
    await expectLater(repository.load(source, cancellation), throwsException);
  });
}

// A generated RGBA PNG avoids external fixtures and real CDN requests. Header
// tests intentionally do not allocate the rejected source's pixel buffer.
Uint8List _png(int width, int height, {bool headerOnly = false}) {
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String kind, List<int> data) {
    final content = Uint8List.fromList([...kind.codeUnits, ...data]);
    var crc = 0xffffffff;
    for (final byte in content) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    output.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    output.add(content);
    output.add(
      (ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List(),
    );
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk(
    'IDAT',
    zlib.encode(Uint8List(headerOnly ? 0 : (width * 4 + 1) * height)),
  );
  chunk('IEND', []);
  return output.takeBytes();
}
