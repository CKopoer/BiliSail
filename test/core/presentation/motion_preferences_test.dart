import 'package:bilisail/core/presentation/motion_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'observes both animation accessibility preferences independently',
    (tester) async {
      var disableAnimations = false;
      var reduceMotion = false;
      late StateSetter update;
      bool? reduced;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQueryData(
                disableAnimations: disableAnimations,
                reduceMotion: reduceMotion,
              ),
              child: Builder(
                builder: (context) {
                  reduced = shouldReduceMotion(context);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      );
      expect(reduced, isFalse);
      update(() => reduceMotion = true);
      await tester.pump();
      expect(reduced, isTrue);
      update(() => disableAnimations = true);
      await tester.pump();
      expect(reduced, isTrue);
      update(() => reduceMotion = false);
      await tester.pump();
      expect(reduced, isTrue);
      update(() => disableAnimations = false);
      await tester.pump();
      expect(reduced, isFalse);
    },
  );
}
