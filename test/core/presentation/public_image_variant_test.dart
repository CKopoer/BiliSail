import 'package:bilisail/core/presentation/public_image_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('static CDN images use bounded aspect-preserving thumbnails', () {
    for (final host in ['i0.hdslb.com', 'album.biliimg.com']) {
      for (final extension in ['png', 'jpg', 'jpeg', 'webp', 'PNG']) {
        final source = Uri.parse('http://$host/bfs/new_dyn/image.$extension');
        expect(
          publicImageThumbnail(source, width: 960).toString(),
          'https://$host/bfs/new_dyn/image.$extension@960w_1280h_0e.webp',
        );
      }
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
      'https://album.biliimg.com.example.test/image.png',
      'https://other.album.biliimg.com/image.png',
      'https://other.biliimg.com/image.png',
      'https://message.biliimg.com/image.png',
      'https://album.biliimg.com/image.png?signature=example',
      'https://album.biliimg.com/image.png#part',
      'https://album.biliimg.com/image.png@400w.jpg',
      'https://album.biliimg.com/image.gif',
      'https://user@album.biliimg.com/image.png',
      'https://album.biliimg.com:8443/image.png',
      'https://www.bilibili.com/image.png',
      'https://user@i0.hdslb.com/image.png',
      'https://i0.hdslb.com:8443/image.png',
      'file:///image.png',
    ]) {
      final source = Uri.parse(url);
      expect(publicImageThumbnail(source, width: 960), source);
    }
  });

  test('GIF resizing is opt-in and keeps existing URL boundaries', () {
    for (final host in ['i0.hdslb.com', 'album.biliimg.com']) {
      for (final extension in ['gif', 'GIF']) {
        final source = Uri.parse('http://$host/image.$extension');
        expect(
          publicImageThumbnail(
            source,
            width: 264,
            resizeAnimated: true,
          ).toString(),
          'https://$host/image.$extension@264w_1280h_0e.webp',
        );
      }
    }
    for (final url in [
      'https://i0.hdslb.com/image.gif?signature=example',
      'https://i0.hdslb.com/image.gif#part',
      'https://i0.hdslb.com/image.gif@400w.gif',
      'https://example.test/image.gif',
      'https://hdslb.com.example.test/image.gif',
      'https://user@i0.hdslb.com/image.gif',
      'https://i0.hdslb.com:8443/image.gif',
      'file:///image.gif',
    ]) {
      final source = Uri.parse(url);
      expect(
        publicImageThumbnail(source, width: 264, resizeAnimated: true),
        source,
      );
    }
  });
}
