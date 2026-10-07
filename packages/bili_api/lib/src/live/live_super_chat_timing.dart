/// HTTP `time` is remaining seconds at `ts`; socket `time` is total seconds.
/// Both sources prefer the authoritative Unix-seconds `end_time`.
({
  DateTime? startedAt,
  DateTime? expiresAt,
  Duration? displayDuration,
  Duration? remainingDuration,
})
parseLiveSuperChatTiming(Map<String, Object?> data, {bool snapshot = false}) {
  var start = _timestamp(data['start_time']);
  var end = _timestamp(data['end_time']);
  final seconds = _integer(data['time']);
  final supplied = seconds != null && seconds > 0 && seconds <= 86400
      ? Duration(seconds: seconds)
      : null;
  final remaining =
      snapshot && seconds != null && seconds >= -86400 && seconds <= 86400
      ? Duration(seconds: seconds < 0 ? 0 : seconds)
      : null;
  if (end == null) {
    final base = snapshot ? _timestamp(data['ts']) : start;
    final fallback = snapshot ? remaining : supplied;
    if (base != null && fallback != null) end = base.add(fallback);
  }
  if (!snapshot && start == null && end != null && supplied != null) {
    start = end.subtract(supplied);
  }
  final interval = start != null && end != null && end.isAfter(start)
      ? end.difference(start)
      : null;
  return (
    startedAt: start,
    expiresAt: end,
    displayDuration: interval ?? (snapshot ? null : supplied),
    remainingDuration: end == null ? remaining : null,
  );
}

int? _integer(Object? value) => value is int
    ? value
    : value is String
    ? int.tryParse(value)
    : null;

DateTime? _timestamp(Object? value) {
  final seconds = _integer(value);
  return seconds == null || seconds <= 0 || seconds > 253402300799
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}
