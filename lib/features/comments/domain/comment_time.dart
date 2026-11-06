String commentTimeLabel(DateTime? publishedAt, {DateTime? now}) {
  if (publishedAt == null || publishedAt.millisecondsSinceEpoch <= 0) {
    return '';
  }
  final current = (now ?? DateTime.now()).toLocal();
  final date = publishedAt.toLocal();
  final elapsed = current.difference(date);
  if (!elapsed.isNegative) {
    if (elapsed.inMinutes == 0) return '刚刚';
    if (elapsed.inHours == 0) return '${elapsed.inMinutes}分钟前';
    if (elapsed.inDays == 0) return '${elapsed.inHours}小时前';
    // Compare calendar days independently of local DST changes.
    final days = DateTime.utc(
      current.year,
      current.month,
      current.day,
    ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
    if (days == 1) return '昨天 ${_two(date.hour)}:${_two(date.minute)}';
    if (days < 4) return '$days天前';
  }
  final monthDay = '${_two(date.month)}-${_two(date.day)}';
  return date.year == current.year ? monthDay : '${date.year}-$monthDay';
}

String _two(int value) => value.toString().padLeft(2, '0');
