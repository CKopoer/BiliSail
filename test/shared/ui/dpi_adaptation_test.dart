import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dpi_test_app.dart';

const _ratios = [.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
const _scales = [.8, 1.0, 1.5, 2.0];

void main() {
  setUpAll(loadDpiTestFonts);

  testWidgets('equal logical geometry survives live density changes', (
    tester,
  ) async {
    _resetViewAfterTest(tester);
    Rect? previousCard;
    double? previousFontSize;
    Element? previousGrid;
    for (final ratio in [..._ratios, 4.0, 1.0]) {
      _configure(tester, const Size(1200, 800) * ratio, ratio, 1);
      await tester.pumpWidget(dpiBrowserApp());
      await tester.pumpAndSettle();
      final grid = tester.element(find.byType(VideoGrid));
      final card = tester.getRect(find.byType(VideoCard).first);
      final paragraph = dpiParagraph(tester, find.text(dpiVideos.first.title));
      final fontSize = paragraph.textScaler.scale(
        paragraph.text.style!.fontSize!,
      );
      if (previousCard != null) {
        expect(card, previousCard, reason: 'ratio=$ratio');
        expect(fontSize, previousFontSize, reason: 'ratio=$ratio');
        expect(grid, same(previousGrid), reason: 'ratio=$ratio');
      }
      previousCard = card;
      previousFontSize = fontSize;
      previousGrid = grid;
      expect(
        MediaQuery.devicePixelRatioOf(tester.element(find.byType(VideoGrid))),
        ratio,
      );
      expectDpiCards(tester);
      expect(tester.takeException(), isNull, reason: 'ratio=$ratio');
    }
  });

  for (final physicalSize in const [Size(1280, 720), Size(1920, 1080)]) {
    for (final ratio in _ratios) {
      for (final scale in _scales) {
        testWidgets('browser ${physicalSize.width}x${physicalSize.height} '
            'density=$ratio text=$scale', (tester) async {
          _resetViewAfterTest(tester);
          _configure(tester, physicalSize, ratio, scale);
          await tester.pumpWidget(dpiBrowserApp());
          await tester.pumpAndSettle();
          expectDpiCards(tester);
          expect(tester.takeException(), isNull);
        }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
      }
    }
  }

  for (final ratio in _ratios) {
    for (final scale in _scales) {
      testWidgets('detail density=$ratio text=$scale', (tester) async {
        _resetViewAfterTest(tester);
        _configure(tester, const Size(1920, 1080), ratio, scale);
        await tester.pumpWidget(dpiDetailApp());
        await tester.pumpAndSettle();
        final title = find.text(dpiDetailTitle);
        expect(title, findsOneWidget);
        final paragraph = dpiParagraph(tester, title);
        expect(paragraph.didExceedMaxLines, isFalse);
        expectDpiParagraphHeight(paragraph);
        expect(find.byKey(const ValueKey('audit-player')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _resetViewAfterTest(WidgetTester tester) {
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.display.resetSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void _configure(
  WidgetTester tester,
  Size physicalSize,
  double ratio,
  double textScale,
) {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = physicalSize;
  // Keep display and viewport consistent when changing density. A fixed mock
  // display can otherwise become smaller than this test's physical window.
  tester.view.display.size = physicalSize;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
}
