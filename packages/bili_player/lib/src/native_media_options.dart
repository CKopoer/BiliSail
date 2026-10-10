/// mpv path lists use semicolons on Windows and colons on Unix. Escape only
/// that delimiter so one signed URL stays one entry, without rewriting it.
String mpvPathListEntry(Uri uri, {required bool windows}) {
  final separator = windows ? ';' : ':';
  return uri.toString().replaceAll(separator, '\\$separator');
}
