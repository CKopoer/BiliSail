import 'package:bili_player/src/native_media_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final windows in [true, false]) {
    test(
      'one URL preserves signed components on ${windows ? 'Windows' : 'Unix'}',
      () {
        final uri = Uri.parse(
          'https://cdn.example:4483/a%2Fb.m4s?k=1;2&v=x:y%2Fz',
        );
        final entry = mpvPathListEntry(uri, windows: windows);
        expect(
          entry,
          windows
              ? r'https://cdn.example:4483/a%2Fb.m4s?k=1\;2&v=x:y%2Fz'
              : r'https\://cdn.example\:4483/a%2Fb.m4s?k=1;2&v=x\:y%2Fz',
        );
      },
    );
  }
}
