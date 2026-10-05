import 'dart:convert';

import '../models/live_models.dart';

/// Optional rich metadata must not discard an otherwise valid chat message.
Map<String, Object?> liveChatExtra(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is! String || value.length > 64 * 1024) return const {};
  try {
    final decoded = jsonDecode(value);
    return decoded is Map<String, Object?> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

ApiLiveChatImage? liveChatImage(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final rawUrl = value['url'];
  if (rawUrl is! String || rawUrl.isEmpty || rawUrl.length > 2048) return null;
  var url = Uri.tryParse(rawUrl.startsWith('//') ? 'https:$rawUrl' : rawUrl);
  if (url == null || url.host.isEmpty || url.userInfo.isNotEmpty) return null;
  if (url.scheme == 'http' &&
      (url.host == 'hdslb.com' || url.host.endsWith('.hdslb.com'))) {
    url = url.replace(scheme: 'https');
  }
  if (url.scheme != 'https') return null;
  int dimension(Object? value) {
    final number = value is int ? value : int.tryParse('$value');
    return number != null && number > 0 ? number.clamp(1, 4096) : 24;
  }

  return ApiLiveChatImage(
    url: url,
    width: dimension(value['width']),
    height: dimension(value['height']),
  );
}

Map<String, ApiLiveChatImage> liveChatEmotes(Object? value, String text) {
  if (value is! Map<String, Object?>) return const {};
  final result = <String, ApiLiveChatImage>{};
  for (final entry in value.entries.take(50)) {
    if (entry.key.isEmpty ||
        entry.key.length > 100 ||
        !text.contains(entry.key)) {
      continue;
    }
    final image = liveChatImage(entry.value);
    if (image != null) result[entry.key] = image;
  }
  return Map.unmodifiable(result);
}
