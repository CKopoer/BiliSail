import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/system_font_catalog.dart';

final systemFontCatalogProvider = Provider<SystemFontCatalog>(
  (ref) => const UnavailableSystemFontCatalog(),
);

// Enumerate only on opening the picker; cache until the user requests refresh.
final systemFontFamiliesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(systemFontCatalogProvider).loadFamilies(),
);
