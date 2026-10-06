import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/system_font_catalog.dart';

final class NativeSystemFontCatalog implements SystemFontCatalog {
  const NativeSystemFontCatalog();
  static const channel = MethodChannel('bilisail/system_fonts');

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Future<List<String>> loadFamilies() async {
    if (!supported) return const [];
    final result = await channel
        .invokeMethod<Object?>('listFamilies')
        .timeout(const Duration(seconds: 5));
    if (result is! List || result.any((value) => value is! String)) {
      throw const FormatException('Invalid system font catalog');
    }
    final families =
        result
            .cast<String>()
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty && !name.startsWith('@'))
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List.unmodifiable(families);
  }
}
