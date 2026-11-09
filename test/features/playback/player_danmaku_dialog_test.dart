import 'package:bilisail/features/playback/presentation/player_danmaku_dialog.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 800), const Size(844, 390)]) {
    testWidgets(
      'send dialog follows every keyboard frame at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final text = TextEditingController(text: '弹幕草稿');
        addTearDown(text.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      builder: (_) => PlayerDanmakuDialog(
                        composer: Row(
                          children: [
                            Expanded(child: TextField(controller: text)),
                            TextButton(
                              onPressed: () {},
                              child: const Text('发送'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('打开'),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        final focus = FocusManager.instance.primaryFocus;
        for (final inset in [60.0, 120.0, 180.0, 220.0, 180.0, 80.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.getRect(find.byType(TextField)).bottom,
            lessThanOrEqualTo(size.height - inset),
          );
          expect(
            tester.getRect(find.text('发送')).bottom,
            lessThanOrEqualTo(size.height - inset),
          );
          expect(find.text('发送').hitTestable(), findsOneWidget);
          expect(FocusManager.instance.primaryFocus, same(focus));
          expect(text.text, '弹幕草稿');
          expect(tester.takeException(), isNull);
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
