/// Resume a seekable HTTP response once per failed native read at its byte
/// offset before discarding decoded/buffered media. Source refresh and CDN
/// fallback still belong to the application. EOF and non-seekable live streams
/// must never restart at zero.
Map<String, String> fvpHttpOptions(Uri uri, {required bool isLive}) {
  final resumable = !isLive && {'http', 'https'}.contains(uri.scheme);
  return {
    'avio.rw_timeout': resumable ? '5000000' : '30000000',
    'avio.reconnect': resumable ? '1' : '0',
    'avio.reconnect_at_eof': '0',
    'avio.reconnect_streamed': '0',
    'avio.reconnect_on_network_error': '0',
    'avio.reconnect_max_retries': '1',
    'avio.reconnect_delay_max': '1',
    'avio.reconnect_delay_total_max': '1',
  };
}
