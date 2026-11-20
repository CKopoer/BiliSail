/// Some Web responses use compact 万/亿 strings for display counts.
int? parseWebCount(Object? value) {
  final count = switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };
  if (count != null) return count >= 0 ? count : null;
  if (value is String && value.length < 32) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)(万|亿)$').firstMatch(value);
    if (match != null) {
      return ((double.tryParse(match[1] ?? '') ?? 0) *
              (match[2] == '万' ? 10000 : 100000000))
          .round();
    }
  }
  return null;
}
