import 'dart:convert';

/// The pinned backend takes User-Agent and Referer separately from header fields.
({String? userAgent, String? referer, Map<String, String> fields})
nativeMediaHeaders(Map<String, String> headers) {
  String? userAgent, referer;
  final fields = <String, String>{};
  for (final entry in headers.entries) {
    switch (entry.key.toLowerCase()) {
      case 'user-agent':
        userAgent = entry.value;
      case 'referer':
        referer = entry.value;
      default:
        fields[entry.key] = entry.value;
    }
  }
  return (
    userAgent: userAgent,
    referer: referer,
    fields: Map.unmodifiable(fields),
  );
}

/// One mpv timeline with independent video/audio streams. Length prefixes are
/// UTF-8 byte counts: signed URLs and local names may contain EDL delimiters.
String nativeMediaUri(Uri video, [Uri? audio]) {
  if (audio == null) return video.toString();
  String entry(Uri uri) {
    final value = uri.toString();
    return '%${utf8.encode(value).length}%$value';
  }

  return 'edl://!no_chapters;${entry(video)};'
      '!new_stream;!no_chapters;${entry(audio)}';
}

/// mpv restores file-local cache options when a reused player unloads a source.
Map<String, String> nativeCacheOptions({
  required bool live,
  required Duration? window,
  required double rate,
}) {
  final seconds = window == null ? null : window.inMicroseconds / 1e6 * rate;
  const mib = 1024 * 1024;
  return {
    'cache': 'yes',
    'cache-on-disk': 'no',
    'demuxer-max-bytes': (live ? 8 * mib : 4 * mib).toString(),
    'demuxer-max-back-bytes': (live ? 0 : 4 * mib).toString(),
    if (seconds != null) ...{
      'cache-secs': seconds.toStringAsFixed(3),
      'demuxer-hysteresis-secs': (seconds / 1.5).toStringAsFixed(3),
    },
  };
}

bool isNativeNetworkError(String message) =>
    message.startsWith('tcp: ffurl_read returned ') ||
    message.startsWith('Failed to open https://') ||
    message.startsWith('Can not open external file https://') ||
    message.startsWith('Failed to open http://') ||
    message.startsWith('Can not open external file http://');
