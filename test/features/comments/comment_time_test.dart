import 'package:bilisail/features/comments/domain/comment_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 6, 18, 30);
  for (final (date, label) in [
    (now, '刚刚'),
    (now.subtract(const Duration(seconds: 59)), '刚刚'),
    (now.subtract(const Duration(minutes: 1)), '1分钟前'),
    (now.subtract(const Duration(minutes: 59)), '59分钟前'),
    (now.subtract(const Duration(hours: 1)), '1小时前'),
    (now.subtract(const Duration(hours: 23, minutes: 59)), '23小时前'),
    (now.subtract(const Duration(hours: 24)), '昨天 18:30'),
    (DateTime(2026, 11, 4, 23, 59), '2天前'),
    (DateTime(2026, 11, 3), '3天前'),
    (DateTime(2026, 11, 2), '11-02'),
    (DateTime(2026, 1, 2), '01-02'),
    (DateTime(2025, 12, 31), '2025-12-31'),
    (DateTime(2027, 1, 2), '2027-01-02'),
    (now.add(const Duration(minutes: 1)), '11-06'),
    (null, ''),
    (DateTime.fromMillisecondsSinceEpoch(0), ''),
    (DateTime.fromMillisecondsSinceEpoch(-1), ''),
  ]) {
    test('$date displays $label', () {
      expect(commentTimeLabel(date, now: now), label);
    });
  }

  test('UTC timestamps use the same local calendar and elapsed time', () {
    final date = now.subtract(const Duration(minutes: 5));
    expect(commentTimeLabel(date.toUtc(), now: now.toUtc()), '5分钟前');
  });

  test('under 24 hours takes precedence over yesterday and a new year', () {
    expect(
      commentTimeLabel(
        DateTime(2025, 12, 31, 23, 59),
        now: DateTime(2026, 1, 1, 0, 1),
      ),
      '2分钟前',
    );
  });
}
