import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises pointer selection and the platform clipboard through the app host.
Future<String?> selectAndCopyText(
  WidgetTester tester,
  Finder text, {
  bool touch = false,
}) async {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      } else if (call.method == 'Clipboard.hasStrings') {
        return <String, Object>{'value': false};
      }
      return null;
    },
  );
  try {
    await tester.ensureVisible(text);
    await tester.pumpAndSettle();
    if (touch) {
      await tester.longPress(text);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
    } else {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      );
      final mouse = await tester.startGesture(
        paragraph.localToGlobal(
          Offset(
            boxes.first.left + 1,
            (boxes.first.top + boxes.first.bottom) / 2,
          ),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(
        paragraph.localToGlobal(
          Offset(
            boxes.last.right - 1,
            (boxes.last.top + boxes.last.bottom) / 2,
          ),
        ),
      );
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pumpAndSettle();
    return copied;
  } finally {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  }
}
