import 'package:bilisail/shared/ui/highlighted_text.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = '视频标题测量：不同宽度、字体和缩放需要重新检查溢出';

void main() {
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
  });

  for (final query in ['', '标题']) {
    testWidgets('rebuilds and paint-only colors reuse title measurement '
        '(query=$query)', (tester) async {
      final measurements = _Measurements();
      addTearDown(measurements.dispose);
      await tester.pumpWidget(_app(query: query));
      expect(measurements.count, 1);
      _expectCorrectTooltip(tester);
      measurements.count = 0;
      for (final color in [Colors.red, Colors.green, Colors.black]) {
        await tester.pumpWidget(_app(query: query, color: color));
        _expectCorrectTooltip(tester);
      }
      expect(measurements.count, 0);
      await tester.pumpWidget(_app(query: query, highlight: Colors.orange));
      expect(measurements.count, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('geometry and typography changes invalidate the cached result', (
    tester,
  ) async {
    final measurements = _Measurements();
    addTearDown(measurements.dispose);
    final cases = [
      _app(),
      _app(width: 120),
      _app(scale: 2),
      _app(bold: true),
      _app(fontSize: 24),
      _app(letterSpacing: 2),
      _app(font: 'monospace'),
      _app(direction: TextDirection.rtl),
      _app(locale: const Locale('zh')),
      _app(align: TextAlign.center),
      _app(basis: TextWidthBasis.longestLine),
      _app(
        heightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
        ),
      ),
      _app(lines: 1),
      _app(text: '另一段视频标题'),
      _app(query: '标题'),
    ];
    for (final app in cases) {
      measurements.count = 0;
      await tester.pumpWidget(app);
      expect(measurements.count, 1);
      _expectCorrectTooltip(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loaded fonts invalidate once and disposal removes the listener',
    (tester) async {
      final measurements = _Measurements();
      addTearDown(measurements.dispose);
      await tester.pumpWidget(_app());
      measurements.count = 0;
      await PaintingBinding.instance.handleSystemMessage({
        'type': 'fontsChange',
      });
      await tester.pump();
      expect(measurements.count, 1);
      _expectCorrectTooltip(tester);
      await tester.pumpWidget(const SizedBox());
      measurements.count = 0;
      await PaintingBinding.instance.handleSystemMessage({
        'type': 'fontsChange',
      });
      await tester.pump();
      expect(measurements.count, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('titles without overflow tooltips do no extra measurement', (
    tester,
  ) async {
    final measurements = _Measurements();
    addTearDown(measurements.dispose);
    await tester.pumpWidget(_app(tooltip: false));
    expect(measurements.count, 0);
    expect(find.byType(Tooltip), findsNothing);
  });
}

final class _Measurements {
  _Measurements() {
    FlutterMemoryAllocations.instance.addListener(_created);
  }
  int count = 0;
  void _created(ObjectEvent event) {
    if (event is ObjectCreated &&
        event.object is TextPainter &&
        StackTrace.current.toString().contains('highlighted_text.dart')) {
      count++;
    }
  }

  void dispose() => FlutterMemoryAllocations.instance.removeListener(_created);
}

void _expectCorrectTooltip(WidgetTester tester) {
  final text = find.descendant(
    of: find.byType(HighlightedText),
    matching: find.byType(Text),
  );
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
  final title = tester
      .widget<HighlightedText>(find.byType(HighlightedText))
      .text;
  expect(tooltip.message, paragraph.didExceedMaxLines ? title : '');
}

Widget _app({
  String text = _title,
  String query = '',
  double width = 240,
  double scale = 1,
  bool bold = false,
  double fontSize = 15,
  String font = 'HarmonyOS Sans',
  double letterSpacing = 0,
  TextDirection direction = TextDirection.ltr,
  Locale locale = const Locale('en'),
  TextAlign align = TextAlign.start,
  TextWidthBasis basis = TextWidthBasis.parent,
  TextHeightBehavior? heightBehavior,
  int lines = 2,
  Color color = Colors.black,
  Color highlight = Colors.pink,
  bool tooltip = true,
}) => MaterialApp(
  themeAnimationDuration: Duration.zero,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: highlight)
        .copyWith(primary: highlight),
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Localizations.override(
        context: context,
        locale: locale,
        child: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              boldText: bold,
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: font,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                color: color,
              ),
              textAlign: align,
              textWidthBasis: basis,
              textHeightBehavior: heightBehavior,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: HighlightedText(
                    text,
                    query: query,
                    maxLines: lines,
                    showOverflowTooltip: tooltip,
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
