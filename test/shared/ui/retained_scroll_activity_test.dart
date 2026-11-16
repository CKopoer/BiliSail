import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leaving a retained page stops its fling at the saved offset', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    final controller = ScrollController(initialScrollOffset: 10000);
    addTearDown(active.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        scrollBehavior: const SmoothScrollBehavior(),
        home: ValueListenableBuilder(
          valueListenable: active,
          builder: (_, value, child) => WorkspaceActivity(
            active: value,
            child: Offstage(offstage: !value, child: child),
          ),
          child: ListView.builder(
            controller: controller,
            itemExtent: 100,
            itemCount: 1000,
            itemBuilder: (_, index) => Text('Card $index'),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -400), 5000);
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    active.value = false;
    await tester.pump();
    final saved = controller.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, saved);
    expect(controller.position.isScrollingNotifier.value, isFalse);
    active.value = true;
    await tester.pump();
    expect(controller.offset, saved);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(saved));
    expect(tester.takeException(), isNull);
  });
}
