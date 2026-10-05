import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notice is compact, below center and dismissed after 1.5s', (
    tester,
  ) async {
    await _pumpHost(tester);
    await tester.tap(find.text('显示提示'));
    await tester.pump();

    final notice = find.text('操作成功');
    final surface = find.ancestor(of: notice, matching: find.byType(Material));
    final rect = tester.getRect(surface);
    expect(rect.width, lessThan(200));
    expect(rect.height, lessThan(60));
    expect(rect.center.dx, closeTo(400, 1));
    expect(rect.center.dy, inExclusiveRange(360, 450));
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(milliseconds: 1499));
    expect(notice, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(notice, findsNothing);
  });

  testWidgets('new notice replaces the previous one and restarts its timer', (
    tester,
  ) async {
    await _pumpHost(tester);
    await tester.tap(find.text('显示提示'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('另一个提示'));
    await tester.pump();
    expect(find.text('操作成功'), findsNothing);
    expect(find.text('视频链接已复制'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('视频链接已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('视频链接已复制'), findsNothing);
  });

  testWidgets('notice does not intercept taps and disposes its timer', (
    tester,
  ) async {
    var taps = 0;
    await _pumpHost(tester, onTap: () => taps++);
    await tester.tap(find.text('显示提示'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('操作成功')));
    expect(taps, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 800.0, 1920.0]) {
    testWidgets('long notice fits width $width with large text and keyboard', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const message = '最多打开 16 个标签页，请先关闭不用的标签';
      await _pumpHost(
        tester,
        message: message,
        textScale: 2,
        keyboardHeight: 300,
      );
      await tester.tap(find.text('显示提示'));
      await tester.pump();

      final rect = tester.getRect(find.text(message));
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(width - 16));
      expect(rect.bottom, lessThan(600));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  String message = '操作成功',
  VoidCallback? onTap,
  double textScale = 1,
  double keyboardHeight = 0,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboardHeight),
      ),
      child: AppNoticeHost.builder(context, child),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.expand(
            child: Column(
              children: [
                TextButton(
                  onPressed: () => showAppNotice(context, message),
                  child: const Text('显示提示'),
                ),
                TextButton(
                  onPressed: () => showAppNotice(context, '视频链接已复制'),
                  child: const Text('另一个提示'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
