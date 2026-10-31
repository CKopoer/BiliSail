import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:bilisail/shared/ui/text_measurement_cache.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
  });

  for (final width in [430.0, 1800.0]) {
    testWidgets('recycled $width grid cards reuse metrics, not elements', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final measurements = _Measurements();
      addTearDown(measurements.dispose);
      await tester.pumpWidget(_app(scroll));
      await tester.pumpAndSettle();
      final initial = find.byType(VideoCard).evaluate().toList();
      expect(initial.length, lessThan(80));
      expect(measurements.titles, isNotEmpty);
      expect(measurements.widths, isNotEmpty);
      final titleCount = measurements.titles.length;
      if (width == 1800) {
        expect(
          initial
              .map(
                (e) => (e.renderObject! as RenderBox)
                    .localToGlobal(Offset.zero)
                    .dx,
              )
              .toSet()
              .length,
          6,
        );
      }

      scroll.jumpTo(5000);
      await tester.pumpAndSettle();
      expect(initial.every((e) => !e.mounted), isTrue);
      expect(find.byType(VideoCard).evaluate().length, lessThan(80));
      measurements.clear();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byType(VideoCard).evaluate().length, initial.length);
      expect(measurements.titles, isEmpty);
      expect(measurements.widths, isEmpty);
      _expectCorrectTooltips(tester);

      // Font loading must invalidate both the local and recycled results.
      await PaintingBinding.instance.handleSystemMessage({
        'type': 'fontsChange',
      });
      await tester.pumpAndSettle();
      expect(measurements.titles.length, titleCount);
      expect(measurements.widths, isNotEmpty);
      _expectCorrectTooltips(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('recycled metrics respect resize, text scale and grid lifetime', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final measurements = _Measurements();
    addTearDown(measurements.dispose);
    await tester.pumpWidget(_app(scroll));
    await tester.pumpAndSettle();
    measurements.clear();
    await tester.pumpWidget(_app(scroll, scale: 2));
    await tester.pumpAndSettle();
    expect(measurements.titles, isNotEmpty);
    expect(measurements.widths, isNotEmpty);
    _expectCorrectTooltips(tester);
    measurements.clear();
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    expect(measurements.titles, isNotEmpty);
    _expectCorrectTooltips(tester);

    await tester.pumpWidget(const SizedBox());
    measurements.clear();
    await tester.pumpWidget(_app(scroll));
    await tester.pumpAndSettle();
    expect(measurements.titles, isNotEmpty);
    expect(measurements.widths, isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'measurement LRU limits retention and refreshes recently used entries',
    () {
      final cache = TextMeasurementCache();
      var reads = 0;
      double width(int key) => cache.width(key, () {
        reads++;
        return key.toDouble();
      });
      bool overflows(int key) => cache.overflows(key, () {
        reads++;
        return key.isEven;
      });
      for (var i = 0; i < TextMeasurementCache.maximumEntries; i++) {
        width(i);
        overflows(i);
      }
      reads = 0;
      expect(width(0), 0);
      expect(overflows(0), isTrue);
      expect(reads, 0);
      width(TextMeasurementCache.maximumEntries);
      overflows(TextMeasurementCache.maximumEntries);
      reads = 0;
      width(0);
      overflows(0);
      expect(reads, 0);
      width(1);
      overflows(1);
      expect(reads, 2);
      cache.clear();
      width(0);
      overflows(0);
      expect(reads, 4);
    },
  );
}

Widget _app(ScrollController scroll, {double scale = 1}) => MaterialApp(
  theme: BiliTheme.light(),
  themeAnimationDuration: Duration.zero,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverCardGridPadding(
              sliver: SliverResponsiveCardGrid(
                itemCount: 300,
                itemBuilder: (_, i) => VideoCard(
                  video: VideoSummary(
                    id: VideoId('BV1abc${i.toString().padLeft(6, '0')}'),
                    title: '视频标题 $i：滚动回收后仍要正确显示两行文字和完整的溢出提示',
                    author: '作者 $i',
                    coverUrl: '',
                    playCount: 123000,
                    danmakuCount: 1200,
                    duration: const Duration(minutes: 3),
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

void _expectCorrectTooltips(WidgetTester tester) {
  for (final element in find.byType(VideoCard).evaluate()) {
    final texts = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byType(RichText),
    );
    final paragraph = texts
        .evaluate()
        .map((e) => e.renderObject)
        .whereType<RenderParagraph>()
        .firstWhere((p) => p.maxLines == 2);
    final video = (element.widget as VideoCard).video;
    final tooltip = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byTooltip(video.title),
    );
    expect(
      tooltip,
      paragraph.didExceedMaxLines ? findsOneWidget : findsNothing,
    );
  }
}

final class _Measurements {
  _Measurements() {
    FlutterMemoryAllocations.instance.addListener(_created);
  }
  final titles = <String>[];
  final widths = <String>[];
  void _created(ObjectEvent event) {
    if (event is! ObjectCreated || event.object is! TextPainter) return;
    final painter = event.object as TextPainter;
    final stack = StackTrace.current.toString();
    if (stack.contains('highlighted_text.dart')) {
      titles.add(painter.text!.toPlainText());
    }
    if (stack.contains('video_card.dart')) {
      widths.add(painter.text!.toPlainText());
    }
  }

  void clear() {
    titles.clear();
    widths.clear();
  }

  void dispose() => FlutterMemoryAllocations.instance.removeListener(_created);
}
