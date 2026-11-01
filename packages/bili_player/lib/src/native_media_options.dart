/// mpv path lists use semicolons on Windows and colons on Unix. Escape only
/// that delimiter so one signed URL stays one entry, without rewriting it.
String mpvPathListEntry(Uri uri, {required bool windows}) {
  final separator = windows ? ';' : ':';
  return uri.toString().replaceAll(separator, '\\$separator');
}

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
