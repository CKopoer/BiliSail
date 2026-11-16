import 'package:bilisail/shared/ui/video_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dpi_test_app.dart';
import '../../support/android_large_text_scaler.dart';

const _widths = [280.0, 320.0, 360.0, 375.0, 393.0, 412.0, 480.0, 599.0];
const _fontScales = [.85, 1.0, 1.3, 1.5, 2.0];
final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  setUpAll(loadDpiTestFonts);

  for (final search in [false, true]) {
    testWidgets('Android nonlinear large text makes narrow '
        '${search ? 'search' : 'home'} cards readable', (tester) async {
      _resetView(tester);
      for (final (width, columns) in [
        (320.0, 1),
        (360.0, 1),
        (393.0, 1),
        (412.0, 1),
        (447.0, 1),
        (448.0, 2),
      ]) {
        _configure(tester, Size(width, 800), 3, 1);
        await tester.pumpWidget(
          dpiBrowserApp(
            search: search,
            sliver: true,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const AndroidLargeTextScaler()),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cards = find.byType(VideoCard);
        final first = tester.getRect(cards.at(0));
        final next = tester.getRect(cards.at(columns));
        expect(next.top, greaterThan(first.bottom));
        expectDpiCards(tester);
        expectDpiBottomNavigation(tester);
        expect(tester.takeException(), isNull, reason: 'width=$width');
      }
    }, variant: _android);
  }

  for (final query in ['', '标题']) {
    testWidgets('Android overflowing title long press exposes full text '
        'without opening video query=$query', (tester) async {
      _resetView(tester);
      _configure(tester, const Size(360, 800), 3, 1);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'HarmonyOS Sans'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: VideoCard(
                  video: dpiVideos[1],
                  highlightQuery: query,
                  onTap: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? widget.textSpan?.toPlainText()) ==
                dpiVideos[1].title,
      );
      await tester.longPress(title);
      await tester.pumpAndSettle();
      expect(opened, 0);
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
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    }, variant: _android);
  }

  testWidgets('phone geometry is independent of density at equal dp size', (
    tester,
  ) async {
    _resetView(tester);
    Rect? reference;
    for (final ratio in [1.0, 1.5, 2.0, 2.625, 3.0, 3.5, 4.0]) {
      _configure(tester, const Size(360, 800), ratio, 1);
      await tester.pumpWidget(dpiBrowserApp(sliver: true));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(VideoCard).first);
      if (reference != null) expect(card, reference);
      reference = card;
      expectDpiCards(tester);
      expectDpiBottomNavigation(tester);
      expect(tester.takeException(), isNull, reason: 'density=$ratio');
    }
  }, variant: _android);

  for (final search in [false, true]) {
    for (final width in _widths) {
      for (final fontScale in _fontScales) {
        testWidgets('Android ${search ? 'search' : 'browser'} '
            'width=$width text=$fontScale', (tester) async {
          _resetView(tester);
          for (final ratio in [1.0, 2.625, 4.0]) {
            _configure(tester, Size(width, 800), ratio, fontScale);
            await tester.pumpWidget(
              dpiBrowserApp(search: search, sliver: true),
            );
            await tester.pumpAndSettle();
            expectDpiCards(tester);
            expectDpiBottomNavigation(tester);
            expect(tester.takeException(), isNull, reason: 'density=$ratio');
          }
        }, variant: _android);
      }
    }
  }

  for (final width in _widths) {
    for (final fontScale in _fontScales) {
      testWidgets('Android detail width=$width text=$fontScale', (
        tester,
      ) async {
        _resetView(tester);
        for (final ratio in [2.0, 3.5]) {
          _configure(tester, Size(width, 800), ratio, fontScale);
          await tester.pumpWidget(dpiDetailApp());
          await tester.pumpAndSettle();
          expectDpiDetail(tester);
          expect(tester.takeException(), isNull, reason: 'density=$ratio');
        }
      }, variant: _android);
    }
  }

  for (final fontScale in [1.0, 2.0]) {
    testWidgets(
      'Android fixed physical display density changes text=$fontScale',
      (tester) async {
        _resetView(tester);
        for (final ratio in [2.0, 2.625, 3.0, 3.375, 4.0]) {
          _configure(tester, const Size(1080, 2400) / ratio, ratio, fontScale);
          await tester.pumpWidget(dpiBrowserApp(sliver: true));
          await tester.pumpAndSettle();
          expectDpiCards(tester);
          expectDpiBottomNavigation(tester);
          expect(tester.takeException(), isNull, reason: 'density=$ratio');
        }
      },
      variant: _android,
    );
  }

  for (final search in [false, true]) {
    testWidgets(
      'Android keyboard retains narrow ${search ? 'search' : 'grid'}',
      (tester) async {
        _resetView(tester);
        const ratio = 3.0;
        _configure(tester, const Size(320, 720), ratio, 2);
        await tester.pumpWidget(dpiBrowserApp(search: search, sliver: true));
        await tester.pumpAndSettle();
        final card = tester.element(find.byType(VideoCard).first);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * ratio);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-bottom-navigation')),
          findsNothing,
        );
        expect(tester.element(find.byType(VideoCard).first), same(card));
        expectDpiCards(tester);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expectDpiBottomNavigation(tester);
        expect(tester.takeException(), isNull);
      },
      variant: _android,
    );
  }
}

void _resetView(WidgetTester tester) {
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void _configure(
  WidgetTester tester,
  Size logicalSize,
  double ratio,
  double fontScale,
) {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = logicalSize * ratio;
  final insets = FakeViewPadding(top: 24 * ratio, bottom: 24 * ratio);
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  tester.platformDispatcher.textScaleFactorTestValue = fontScale;
}
