import 'package:bili_player/src/fvp_http_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seekable HTTP VOD can resume once with a bounded read deadline', () {
    for (final scheme in ['http', 'https']) {
      final options = fvpHttpOptions(
        Uri.parse('$scheme://example.com/media?token=private'),
        isLive: false,
      );
      expect(options['avio.reconnect'], '1');
      expect(options['avio.reconnect_max_retries'], '1');
      expect(options['avio.rw_timeout'], '5000000');
      expect(options['avio.reconnect_delay_max'], '1');
      expect(options['avio.reconnect_delay_total_max'], '1');
      expect(options['avio.reconnect_streamed'], '0');
      expect(options['avio.reconnect_at_eof'], '0');
      expect(options['avio.reconnect_on_network_error'], '0');
      expect(options.toString(), isNot(contains('private')));
    }
  });

  test('live and local media retain their existing read policy', () {
    for (final sample in [
      (uri: 'https://example.com/live.flv', live: true),
      (uri: 'file:///local/audio.m4a', live: false),
      (uri: 'content://local/audio', live: false),
    ]) {
      final options = fvpHttpOptions(
        Uri.parse(sample.uri),
        isLive: sample.live,
      );
      expect(options['avio.reconnect'], '0');
      expect(options['avio.rw_timeout'], '30000000');
    }
  });
}
