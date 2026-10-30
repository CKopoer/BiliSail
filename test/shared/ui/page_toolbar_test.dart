import 'package:bilisail/shared/ui/page_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('toolbar keeps usable actions and scaled text on $platform', (
      tester,
    ) async {
      final pressed = <String>[];
      final scale = ValueNotifier(1.0);
      final width = ValueNotifier(320.0);
      addTearDown(scale.dispose);
      addTearDown(width.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: scale,
              builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(value)),
                child: ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (_, value, _) => Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: value,
                      child: PageToolbarLeading(
                        leading: IconButton(
                          tooltip: '返回',
                          onPressed: () => pressed.add('back'),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        child: PageToolbar(
                          title: '我的消息',
                          actions: [
                            IconButton(
                              tooltip: '刷新',
                              onPressed: () => pressed.add('refresh'),
                              icon: const Icon(Icons.refresh),
                            ),
                            IconButton(
                              tooltip: '官方消息页',
                              onPressed: () => pressed.add('official'),
                              icon: const Icon(Icons.open_in_new),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final viewport in [390.0, 320.0, 280.0, 240.0, 160.0]) {
        width.value = viewport;
        for (final textScale in [1.0, 2.0, 3.0]) {
          scale.value = textScale;
          await tester.pumpAndSettle();
          final title = tester.getRect(find.text('我的消息'));
          for (final label in ['返回', '刷新', '官方消息页']) {
            final action = find.byTooltip(label);
            final rect = tester.getRect(action);
            expect(rect.center.dy, closeTo(title.center.dy, .01));
            expect(rect.size, const Size.square(48));
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            await tester.tap(action);
          }
          expect(pressed, ['back', 'refresh', 'official']);
          pressed.clear();
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
