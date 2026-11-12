import 'dart:convert';

import 'package:bili_player/src/native_media_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native headers split special fields without changing signed values',
    () {
      final headers = nativeMediaHeaders({
        'uSeR-AgEnT': 'BiliSail test',
        'REFERER': 'https://example.test/a?x=1%2F2',
        'Range': 'bytes=0-',
        'X-Test': 'a,b;c',
      });
      expect(headers.userAgent, 'BiliSail test');
      expect(headers.referer, 'https://example.test/a?x=1%2F2');
      expect(headers.fields, {'Range': 'bytes=0-', 'X-Test': 'a,b;c'});
      expect(() => headers.fields.clear(), throwsUnsupportedError);
      expect(nativeMediaHeaders({}).userAgent, isNull);
    },
  );

  test(
    'EDL entries preserve signed URL delimiters and local Unicode paths',
    () {
      for (final (video, audio) in [
        (
          Uri.parse('https://cdn.example:4483/a%2Fb.m4s?k=1;2&v=x:y%2Fz'),
          Uri.parse('https://cdn.example/a.m4s?sig=a,b;%25'),
        ),
        (Uri.file('/媒体/视频;1.mp4'), Uri.file('/媒体/音频,2.m4a')),
        (Uri.parse('fd://12'), Uri.parse('fd://13')),
      ]) {
        final edl = nativeMediaUri(video, audio);
        final bytes = utf8.encode(edl);
        var offset = utf8.encode('edl://!no_chapters;').length;
        String entry() {
          expect(bytes[offset++], 37);
          final start = offset;
          while (bytes[offset] != 37) {
            offset++;
          }
          final length = int.parse(utf8.decode(bytes.sublist(start, offset++)));
          final value = utf8.decode(bytes.sublist(offset, offset + length));
          offset += length;
          return value;
        }

        expect(entry(), video.toString());
        const separator = ';!new_stream;!no_chapters;';
        expect(
          utf8.decode(bytes.sublist(offset, offset + separator.length)),
          separator,
        );
        offset += separator.length;
        expect(entry(), audio.toString());
        expect(offset, bytes.length);
      }
    },
  );
  test('single-track, live and audio-only inputs keep the original URI', () {
    for (final uri in [
      Uri.parse('https://example.test/live.m3u8?a=1;2'),
      Uri.file('/媒体/音频.m4a'),
    ]) {
      expect(nativeMediaUri(uri), uri.toString());
    }
  });
}
