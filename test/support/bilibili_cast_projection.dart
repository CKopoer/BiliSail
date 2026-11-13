import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// Receiver-side decoding, independent of the sender's encoding implementation.
Map<String, Object?> decodeCastProjection(String value) {
  final key = Uint8List.fromList(utf8.encode('1pzhA828t4i.6Oq@'));
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), key),
        null,
      ),
    );
  final decoded = cipher.process(base64Url.decode(base64Url.normalize(value)));
  return (jsonDecode(
    utf8.decode(ZLibDecoder(raw: true).convert(decoded)),
  ) as Map).cast<String, Object?>();
}
