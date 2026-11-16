import 'package:bilisail/shared/ui/retained_page_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'hidden layout retains constraints but processes dirty content and resize on show',
    (tester) async {
      var visible = true;
      var height = 500.0;
      var revision = 0;
      var layouts = 0;
      Size? lastSize;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  height: height,
                  child: Offstage(
                    offstage: !visible,
                    child: RetainedPageLayout(
                      visible: visible,
                      child: LayoutBuilder(
                        builder: (_, constraints) {
                          layouts++;
                          lastSize = constraints.biggest;
                          return Text('revision $revision');
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(lastSize, const Size(300, 500));
      update(() {
        visible = false;
        height = 600;
      });
      await tester.pump();
      expect(lastSize, const Size(300, 500));
      // Normal provider/configuration updates are still processed while hidden.
      update(() => revision++);
      await tester.pump();
      expect(find.text('revision 1', skipOffstage: false), findsOneWidget);
      expect(layouts, greaterThan(1));
      update(() => visible = true);
      await tester.pump();
      expect(lastSize, const Size(300, 600));
      expect(tester.takeException(), isNull);
    },
  );
}
