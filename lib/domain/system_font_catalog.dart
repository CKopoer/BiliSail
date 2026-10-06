/// Fonts available to the platform text renderer. Names are family names,
/// never font file paths; selecting one does not copy or redistribute it.
abstract interface class SystemFontCatalog {
  bool get supported;
  Future<List<String>> loadFamilies();
}

final class UnavailableSystemFontCatalog implements SystemFontCatalog {
  const UnavailableSystemFontCatalog();
  @override
  bool get supported => false;
  @override
  Future<List<String>> loadFamilies() async => const [];
}
