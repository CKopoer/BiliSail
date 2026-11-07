import 'package:bilisail/features/playback/presentation/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('floating player drag and resize stay inside the safe area', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const video = ValueKey('test-mini-video');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FloatingMiniPlayer(
            aspectRatio: 16 / 9,
            child: ColoredBox(key: video, color: Colors.black),
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(video), const Offset(-1000, 1500));
    await tester.pump();
    final dragged = tester.getRect(find.byKey(video));
    expect(dragged.left, greaterThanOrEqualTo(0));
    expect(dragged.bottom, lessThanOrEqualTo(844));
    await tester.drag(find.bySemanticsLabel('调整小窗大小'), const Offset(1000, 0));
    await tester.pump();
    expect(tester.getRect(find.byKey(video)).right, lessThanOrEqualTo(390));
    tester.view.physicalSize = const Size(200, 180);
    await tester.pump();
    final compact = tester.getRect(find.byKey(video));
    expect(compact.right, lessThanOrEqualTo(200));
    expect(compact.bottom, lessThanOrEqualTo(180));
    expect(tester.takeException(), isNull);
  });
}
