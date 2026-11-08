import 'dart:convert';

import '../models/live_models.dart';

ApiLiveFanMedal? liveChatMedal(Object? value) {
  Object? name, level, color, textColor, light;
  if (value is Map<String, Object?>) {
    name = value['name'] ?? value['medal_name'];
    level = value['level'] ?? value['medal_level'];
    color = value['v2_medal_color_start'] ?? value['medal_color'];
    textColor = value['v2_medal_color_text'];
    light = value['is_light'];
  } else if (value is List<Object?> && value.length >= 2) {
    level = value[0];
    name = value[1];
    color = value.length > 4 ? value[4] : null;
    light = value.length > 11 ? value[11] : null;
  }
  final parsedLevel = liveChatUserLevel(level);
  if (name is! String ||
      name.trim().isEmpty ||
      parsedLevel == null ||
      parsedLevel == 0 ||
      _integer(light) == 0) {
    return null;
  }
  final label = name.trim();
  return ApiLiveFanMedal(
    name: label.substring(0, label.length.clamp(0, 30)),
    level: parsedLevel,
    color: _medalColor(color),
    textColor: _medalColor(textColor),
  );
}

int? liveChatUserLevel(Object? value) {
  final level = _integer(value is List<Object?> ? value.firstOrNull : value);
  return level != null && level >= 0 && level <= 1000 ? level : null;
}

int? _integer(Object? value) => value is int
    ? value
    : value is String
    ? int.tryParse(value)
    : null;

int? _medalColor(Object? value) {
  if (value is String &&
      RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)) {
    final rgb = int.parse(value.substring(1, 7), radix: 16);
    final alpha = value.length == 9
        ? int.parse(value.substring(7), radix: 16)
        : 255;
    // The v2 medal field is RGBA; domain colors use ARGB.
    return (alpha << 24) | rgb;
  }
  final rgb = _integer(value);
  return rgb != null && rgb >= 0 && rgb <= 0xffffff ? 0xff000000 | rgb : null;
}

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
