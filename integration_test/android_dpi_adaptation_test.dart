import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrintDone;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bilisail/shared/ui/video_card.dart';

import '../test/support/dpi_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android platform density and text scaling preserve phone layouts', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    for (final page in ['browser', 'search', 'detail']) {
      await tester.pumpWidget(
        page == 'detail'
            ? dpiDetailApp(builder: _nativeView)
            : dpiBrowserApp(
                search: page == 'search',
                sliver: true,
                builder: _nativeView,
              ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      final media = MediaQuery.of(context);
      final cards = find.byType(VideoCard).evaluate().toList();
      final firstCard = cards.isEmpty
          ? null
          : tester.getRect(find.byWidget(cards.first.widget));
      debugPrint(
        'ANDROID_DPI_AUDIT ${jsonEncode({
          'page': page,
          'width': media.size.width,
          'height': media.size.height,
          'density': media.devicePixelRatio,
          'cardWidth': firstCard?.width,
          'columns': firstCard == null ? null : cards.where((element) => (tester.getTopLeft(find.byWidget(element.widget)).dy - firstCard.top).abs() < .1).length,
          'fonts': {
            for (final size in [12, 14, 15, 16, 20, 24, 36, 140, 300]) '$size': media.textScaler.scale(size.toDouble()),
          },
        })}',
      );
      expect(media.size.width, inInclusiveRange(280, 599));
      if (page == 'detail') {
        expectDpiDetail(tester);
      } else {
        expectDpiCards(tester);
        expectDpiBottomNavigation(tester);
        if (media.size.width <= 412 && media.textScaler.scale(15) >= 22.5) {
          expect(firstCard!.width, greaterThan(media.size.width * .8));
        }
        final title = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? widget.textSpan?.toPlainText()) ==
                  dpiVideos[1].title,
        );
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        await tester.longPress(title);
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText() == dpiVideos[1].title,
          ),
          findsNWidgets(2),
        );
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
        final scrolling = tester.state<ScrollableState>(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        scrolling.position.jumpTo(scrolling.position.minScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: page);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('dpi-native-capture')),
      );
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          throw StateError('DPI screenshot encoding failed.');
        }
        debugPrint(
          'ANDROID_DPI_SCREENSHOT $page ${base64Encode(bytes.buffer.asUint8List())}',
          wrapWidth: null,
        );
        await debugPrintDone;
      } finally {
        image.dispose();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}

Widget _nativeView(BuildContext context, Widget? child) => MediaQuery(
  // TestPlatformDispatcher.scaleFontSize is linear. Read the real view so this
  // device test exercises Android's native nonlinear curve, as the app does.
  data: MediaQueryData.fromView(ui.PlatformDispatcher.instance.views.single),
  child: RepaintBoundary(
    key: const ValueKey('dpi-native-capture'),
    child: child ?? const SizedBox.shrink(),
  ),
);
