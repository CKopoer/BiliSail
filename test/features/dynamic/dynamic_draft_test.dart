import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editing before tokens shifts UTF-16 offsets and editing inside drops identity', () {
    const text = '😀@用户[doge]';
    const spans = [
      DynamicTextSpan(2, 5, DynamicTextKind.mention, id: '7'),
      DynamicTextSpan(5, 11, DynamicTextKind.emote),
    ];
    final shifted = reconcileDynamicText(text, '前$text', spans);
    expect(shifted.map((s) => (s.start, s.end, s.id)), [
      (3, 6, '7'),
      (6, 12, ''),
    ]);
    final edited = reconcileDynamicText(text, '😀@新人[doge]', spans);
    expect(edited.single.kind, DynamicTextKind.emote);
    expect(reconcileDynamicText(text, '', spans), isEmpty);
  });
  test(
    'schedule rejects private posts, expired times and more than seven days',
    () {
      final now = DateTime(2026, 11, 11, 12);
      expect(
        DynamicPublishOptions(publishAt: now.add(const Duration(minutes: 6)))
            .validAt(now),
        isTrue,
      );
      expect(
        DynamicPublishOptions(publishAt: now.add(const Duration(minutes: 5)))
            .validAt(now),
        isFalse,
      );
      expect(
        DynamicPublishOptions(
          onlySelf: true,
          publishAt: now.add(const Duration(hours: 1)),
        ).validAt(now),
        isFalse,
      );
      expect(
        DynamicPublishOptions(publishAt: now.add(const Duration(days: 8)))
            .validAt(now),
        isFalse,
      );
    },
  );
}
