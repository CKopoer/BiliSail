import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/interaction_icon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget icon({
    required bool selected,
    bool disableAnimations = false,
    bool active = true,
    Key? key,
  }) => MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: WorkspaceActivity(
      active: active,
      child: Center(
        child: InteractionIcon(
          InteractionGlyph.like,
          key: key,
          size: 22,
          selected: selected,
        ),
      ),
    ),
  );

  final transition = find.byType(ScaleTransition);

  testWidgets('selection animates the glyph without resizing its layout', (
    tester,
  ) async {
    await tester.pumpWidget(icon(selected: false));
    expect(transition, findsNothing);
    await tester.pumpWidget(icon(selected: true));
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      tester.widget<ScaleTransition>(transition).scale.value,
      greaterThan(1),
    );
    expect(tester.getSize(find.byType(InteractionIcon)), const Size.square(22));

    await tester.pumpAndSettle();
    expect(tester.widget<ScaleTransition>(transition).scale.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(icon(selected: false));
    expect(tester.widget<ScaleTransition>(transition).scale.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'loaded, reduced motion, and hidden selections render statically',
    (tester) async {
      await tester.pumpWidget(icon(selected: true));
      expect(transition, findsNothing);
      await tester.pumpWidget(icon(selected: false, disableAnimations: true));
      await tester.pumpWidget(icon(selected: true, disableAnimations: true));
      expect(transition, findsNothing);

      await tester.pumpWidget(icon(selected: false, active: false));
      await tester.pumpWidget(icon(selected: true, active: false));
      await tester.pumpWidget(icon(selected: true));
      expect(transition, findsNothing);

      await tester.pumpWidget(icon(selected: false));
      await tester.pumpWidget(icon(selected: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<ScaleTransition>(transition).scale.value,
        greaterThan(1),
      );
      await tester.pumpWidget(icon(selected: true, active: false));
      expect(tester.widget<ScaleTransition>(transition).scale.value, 1);
      await tester.pumpWidget(
        icon(selected: true, key: const ValueKey('new video')),
      );
      expect(transition, findsNothing);
    },
  );
}
