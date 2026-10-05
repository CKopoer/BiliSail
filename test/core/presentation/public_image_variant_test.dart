import 'package:bilisail/core/presentation/public_image_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('static CDN images use bounded aspect-preserving thumbnails', () {
    for (final extension in ['png', 'jpg', 'jpeg', 'webp', 'PNG']) {
      final source = Uri.parse(
        'http://i0.hdslb.com/bfs/new_dyn/image.$extension',
      );
      expect(
        publicImageThumbnail(source, width: 960).toString(),
        'https://i0.hdslb.com/bfs/new_dyn/image.$extension@960w_1280h_0e.webp',
      );
    }
    final source = Uri.parse('https://i0.hdslb.com/image.png');
    expect(
      publicImageThumbnail(source, width: 1600, height: 2000).path,
      '/image.png@1280w_1280h_0e.webp',
    );
  });

  test('signed, animated, transformed and unrelated URLs remain intact', () {
    for (final url in [
      'https://i0.hdslb.com/image.png?signature=example',
      'https://i0.hdslb.com/image.png#part',
      'https://i0.hdslb.com/image.gif',
      'https://i0.hdslb.com/image.png@400w.jpg',
      'https://example.test/image.png',
      'https://hdslb.com.example.test/image.png',
      'https://www.bilibili.com/image.png',
      'https://user@i0.hdslb.com/image.png',
      'https://i0.hdslb.com:8443/image.png',
      'file:///image.png',
    ]) {
      final source = Uri.parse(url);
      expect(publicImageThumbnail(source, width: 960), source);
    }
  });
}
