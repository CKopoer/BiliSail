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
