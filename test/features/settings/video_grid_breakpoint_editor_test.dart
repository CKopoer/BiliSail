import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/features/settings/presentation/video_grid_breakpoint_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dragging changes the chosen threshold without crossing neighbors',
    (tester) async {
      var values = [...ResponsiveLayoutSettings.defaultVideoGridMinWidths];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 560,
                  child: VideoGridBreakpointEditor(
                    values: values,
                    onChanged: (next) => update(() => values = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final track = find.byKey(const ValueKey('video-grid-multi-thumb-track'));
      final bounds = tester.getRect(track);
      double x(int value) =>
          bounds.left + 12 + (value - 200) / 3800 * (bounds.width - 24);
      final y = bounds.top + 43;
      var gesture = await tester.startGesture(Offset(x(1100), y));
      await gesture.moveTo(Offset(x(1200), y));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(values[2], 1200);
      expect(values[1], 492);
      expect(values[3], 1380);
      gesture = await tester.startGesture(Offset(x(1200), y));
      await gesture.moveTo(Offset(bounds.right, y));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(values[2], 1379);
      expect(ResponsiveLayoutSettings.validVideoGridWidths(values), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'column selection supports keyboard and exact numeric adjustment',
    (tester) async {
      var values = [...ResponsiveLayoutSettings.defaultVideoGridMinWidths];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => VideoGridBreakpointEditor(
                values: values,
                onChanged: (next) => update(() => values = next),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('video-grid-column-6')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(values[4], 1661);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(values[4], 1651);
      await tester.enterText(
        find.byKey(const ValueKey('video-grid-exact-width')),
        '1703',
      );
      await tester.pump();
      expect(values[4], 1703);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'narrow editor wraps column chips and supports enlarged text dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BiliTheme.dark() : BiliTheme.light(),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(
                  child: VideoGridBreakpointEditor(
                    values: ResponsiveLayoutSettings.defaultVideoGridMinWidths,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final last = find.byKey(const ValueKey('video-grid-column-12'));
        await tester.ensureVisible(last);
        await tester.tap(last);
        await tester.pump();
        expect(tester.widget<ChoiceChip>(last).selected, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
