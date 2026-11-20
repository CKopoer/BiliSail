import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/data/network_original_image_repository.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/storage/public_image_test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Uri.parse('https://i0.hdslb.com/long.png');
  test('auto only downloads a confirmed small original and manual load still works', () async {
    final server = await PublicImageTestServer.start();
    addTearDown(server.close);
    final png = _png(4, 6);
    final oversizedLength =
        NetworkOriginalImageRepository.automaticMaxBytes + 1;
    final largePng = Uint8List(oversizedLength)..setAll(0, png);
    server.onRequest = (request) {
      final response = request.response;
      if (request.method == 'HEAD') {
        switch (request.uri.path) {
          case '/large':
            response.contentLength = oversizedLength;
          case '/no-head':
            response.statusCode = HttpStatus.methodNotAllowed;
          case '/small':
          case '/changed':
            response.contentLength = png.length;
        }
      } else if (['/large', '/changed'].contains(request.uri.path)) {
        response.contentLength = largePng.length;
        response.add(largePng);
      } else {
        response.add(png);
      }
      unawaited(response.close());
    };
    await HttpOverrides.runWithHttpOverrides(() async {
      final repository = NetworkOriginalImageRepository();
      final loaded = await repository.loadAutomatically(
        server.uri('/small'),
        RequestCancellation(),
      );
      expect(loaded?.bytes, png);
      expect(server.connections, 1);
      for (final path in ['/large', '/unknown', '/no-head']) {
        expect(
          await repository.loadAutomatically(
            server.uri(path),
            RequestCancellation(),
          ),
          isNull,
        );
      }
      expect(
        await repository.loadAutomatically(
          server.uri('/changed'),
          RequestCancellation(),
        ),
        isNull,
      );
      expect(
        server.requests.map((request) => (request.method, request.uri.path)),
        [
          ('HEAD', '/small'),
          ('GET', '/small'),
          ('HEAD', '/large'),
          ('HEAD', '/unknown'),
          ('HEAD', '/no-head'),
          ('HEAD', '/changed'),
          ('GET', '/changed'),
        ],
      );
      expect(
        (await repository.load(
          server.uri('/no-head'),
          RequestCancellation(),
        )).bytes,
        png,
      );
      expect(server.requests.last.method, 'GET');
      final large = await repository.load(
        server.uri('/large'),
        RequestCancellation(),
      );
      expect(large.bytes.length, oversizedLength);
    }, server);
  });

  test('cancelling the size probe prevents a late original download', () async {
    final server = await PublicImageTestServer.start();
    addTearDown(server.close);
    final received = Completer<HttpRequest>();
    server.onRequest = received.complete;
    await HttpOverrides.runWithHttpOverrides(() async {
      final cancellation = RequestCancellation();
      final result = NetworkOriginalImageRepository().loadAutomatically(
        server.uri('/cancelled'),
        cancellation,
      );
      final failure = expectLater(result, throwsException);
      final head = await received.future;
      cancellation.cancel();
      head.response.contentLength = 42;
      await head.response.close();
      await failure;
      expect(server.requests.map((request) => request.method), ['HEAD']);
    }, server);
  });
  test(
    'album and private message CDN originals keep their URL and bytes',
    () async {
      final bytes = _png(4, 6);
      final sources = <Uri>[];
      final repository = NetworkOriginalImageRepository(
        loader: (uri, _) async {
          sources.add(uri);
          return bytes;
        },
      );
      for (final host in ['album.biliimg.com', 'message.biliimg.com']) {
        for (final scheme in ['https', 'http']) {
          final source = Uri.parse(
            '$scheme://$host/bfs/fixture.jpg?fixture=original',
          );
          final image = await repository.load(source, RequestCancellation());
          expect(sources.last, source.replace(scheme: 'https'));
          expect(image.bytes, bytes);
          expect((image.width, image.height), (4, 6));
        }
      }
    },
  );

  test('biliimg CDN support still rejects untrusted original URLs', () async {
    var loads = 0;
    final repository = NetworkOriginalImageRepository(
      loader: (_, _) async {
        loads++;
        return _png(4, 6);
      },
    );
    for (final url in [
      'https://message.biliimg.com.example.com/image.jpg',
      'https://album.biliimg.com.example.com/image.jpg',
      'https://other.album.biliimg.com/image.jpg',
      'https://other.biliimg.com/image.jpg',
      'https://biliimg.com/image.jpg',
      'https://user:password@message.biliimg.com/image.jpg',
      'https://user:password@album.biliimg.com/image.jpg',
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
