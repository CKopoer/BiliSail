import 'dart:typed_data';

final class LocalImage {
  LocalImage(Uint8List bytes, this.mimeType)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  static const maxBytes = 10 * 1024 * 1024;
  static const maxCount = 9;
  final Uint8List bytes;
  final String mimeType;
}
