import 'package:bili_lite/shared/ui/emoticon_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('many series scroll in a narrow dialog with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child ?? const SizedBox(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EmoticonPickerDialog(
                  title: '直播表情包',
                  loading: false,
                  hint: '选择后点击发送；锁定表情按账号权限显示',
                  emptyMessage: '暂无表情',
                  onRetry: () {},
                  packageNames: [for (var i = 0; i < 8; i++) '系列$i'],
                  packageBuilder: (_, index) =>
                      ListView(children: [Text('表情$index')]),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('表情0'), findsOneWidget);
    expect(find.text('表情7'), findsNothing);
    final dialog = tester.getRect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(dialog.left, greaterThanOrEqualTo(16));
    expect(dialog.right, lessThanOrEqualTo(304));
    await tester.drag(find.byType(TabBar), const Offset(-1200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系列7'));
    await tester.pumpAndSettle();
    expect(find.text('表情7'), findsOneWidget);
    expect(find.text('表情0'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
