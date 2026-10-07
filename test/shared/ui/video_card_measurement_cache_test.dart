import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  testWidgets('hover and same-tier resize reuse measured cover widths', (
    tester,
  ) async {
    final measurements = _CoverMeasurements();
    addTearDown(measurements.dispose);
    await tester.pumpWidget(_app(width: 300));
    expect(measurements.labels, ['96.3万', '1.0万', '1:50:56']);
    measurements.clear();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(VideoCard)));
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pumpWidget(_app(width: 280));
    await tester.pumpAndSettle();
    expect(measurements.labels, isEmpty);
    _expectSingleCoverRow(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all three typography tiers are reused within a bounded cache', (
    tester,
  ) async {
    final measurements = _CoverMeasurements();
    addTearDown(measurements.dispose);
    for (final width in [300.0, 220.0, 170.0]) {
      measurements.clear();
      await tester.pumpWidget(_app(width: width));
      expect(measurements.labels, ['96.3万', '1.0万', '1:50:56']);
      _expectSingleCoverRow(tester);
    }
    measurements.clear();
    for (final width in [179.0, 180.0, 239.0, 240.0, 300.0]) {
      await tester.pumpWidget(_app(width: width));
      _expectSingleCoverRow(tester);
    }
    expect(measurements.labels, isEmpty);

    // New labels evict old entries rather than retaining every past statistic.
    for (var value = 1; value <= 12; value++) {
      await tester.pumpWidget(_app(width: 300, playLabel: '播放$value'));
    }
    measurements.clear();
    await tester.pumpWidget(_app(width: 300));
    expect(measurements.labels, contains('96.3万'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached widths still decide wrapping and preserve RTL order', (
    tester,
  ) async {
    final measurements = _CoverMeasurements();
    addTearDown(measurements.dispose);
    await tester.pumpWidget(_app(width: 360, scale: 2));
    _expectSingleCoverRow(tester);
    measurements.clear();
    await tester.pumpWidget(_app(width: 240, scale: 2));
    expect(
      tester.getCenter(find.text('1:50:56')).dy,
      greaterThan(tester.getCenter(find.text('96.3万')).dy),
    );
    expect(measurements.labels, isEmpty);
    await tester.pumpWidget(_app(width: 360, scale: 2));
    _expectSingleCoverRow(tester);
    expect(measurements.labels, isEmpty);

    await tester.pumpWidget(_app(direction: TextDirection.rtl));
    _expectSingleCoverRow(tester);
    expect(
      tester.getCenter(find.text('96.3万')).dx,
      greaterThan(tester.getCenter(find.text('1.0万')).dx),
    );
    expect(
      tester.getCenter(find.text('1.0万')).dx,
      greaterThan(tester.getCenter(find.text('1:50:56')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'measurement follows labels, scale, style, locale and direction',
    (tester) async {
      final measurements = _CoverMeasurements();
      addTearDown(measurements.dispose);
      await tester.pumpWidget(_app());
      measurements.clear();
      await tester.pumpWidget(_app(playLabel: '123456789'));
      expect(measurements.labels, ['1.2亿']);
      measurements.clear();
      await tester.pumpWidget(_app(playLabel: '123456789', danmakuLabel: '32'));
      expect(measurements.labels, ['32']);
      measurements.clear();
      await tester.pumpWidget(
        _app(playLabel: '123456789', danmakuLabel: '32', seconds: 61),
      );
      expect(measurements.labels, ['01:01']);

      for (final (name, app) in [
        ('scale', _app(scale: 2)),
        ('font', _app(fontFamily: 'Ahem')),
        ('spacing', _app(letterSpacing: 2)),
        ('locale', _app(locale: const Locale('zh'))),
        ('direction', _app(direction: TextDirection.rtl)),
        ('bold', _app(bold: true)),
      ]) {
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        measurements.clear();
        await tester.pumpWidget(app);
        await tester.pumpAndSettle();
        expect(measurements.labels.toSet(), {
          '96.3万',
          '1.0万',
          '1:50:56',
        }, reason: name);
        // Material may animate inherited styles; each effective style needs
        // measurement, but the settled environment must then reuse widths.
        measurements.clear();
        await tester.pumpWidget(app);
        await tester.pumpAndSettle();
        expect(measurements.labels, isEmpty, reason: name);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'font changes invalidate widths and disposed cards stop listening',
    (tester) async {
      final measurements = _CoverMeasurements();
      addTearDown(measurements.dispose);
      await tester.pumpWidget(_app(width: 170, scale: 2));
      expect(
        tester.getCenter(find.text('1:50:56')).dy,
        greaterThan(tester.getCenter(find.text('96.3万')).dy),
      );
      measurements.clear();
      await PaintingBinding.instance.handleSystemMessage({
        'type': 'fontsChange',
      });
      await tester.pump();
      expect(measurements.labels, ['96.3万', '1.0万', '1:50:56']);
      await tester.pumpWidget(const SizedBox());
      measurements.clear();
      await PaintingBinding.instance.handleSystemMessage({
        'type': 'fontsChange',
      });
      await tester.pump();
      expect(measurements.labels, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

// Flutter's allocation hook distinguishes temporary metadata measurements from
// rendered paragraphs, which use an ellipsis. No production counter is needed.
final class _CoverMeasurements {
  _CoverMeasurements() {
    FlutterMemoryAllocations.instance.addListener(_created);
  }

  final labels = <String>[];

  void _created(ObjectEvent event) {
    if (event is! ObjectCreated) return;
    final object = event.object;
    if (object is! TextPainter || object.ellipsis != null) return;
    final span = object.text;
    if (span is TextSpan &&
        object.maxLines == 1 &&
        span.style?.color == Colors.white &&
        span.style?.shadows?.contains(
              const Shadow(blurRadius: 2, color: Colors.black),
            ) ==
            true) {
      labels.add(span.toPlainText());
    }
  }

  void clear() => labels.clear();
  void dispose() => FlutterMemoryAllocations.instance.removeListener(_created);
}

void _expectSingleCoverRow(WidgetTester tester) {
  final duration = tester.getCenter(find.text('1:50:56'));
  for (final label in ['96.3万', '1.0万']) {
    expect(tester.getCenter(find.text(label)).dy, closeTo(duration.dy, .01));
  }
}

Widget _app({
  double width = 300,
  double scale = 1,
  String? fontFamily,
  double? letterSpacing,
  Locale locale = const Locale('en'),
  TextDirection direction = TextDirection.ltr,
  bool bold = false,
  String playLabel = '',
  String danmakuLabel = '',
  int seconds = 6656,
}) {
  final theme = BiliTheme.light();
  final textTheme = theme.textTheme.apply(fontFamily: fontFamily);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    themeAnimationDuration: Duration.zero,
    theme: theme.copyWith(
      textTheme: textTheme.copyWith(
        bodyMedium: textTheme.bodyMedium?.copyWith(
          letterSpacing: letterSpacing,
        ),
      ),
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
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: VideoCard(
                    video: VideoSummary(
                      id: const VideoId('BV1234567890'),
                      title: '测试视频',
                      coverUrl: '',
                      author: '测试UP',
                      duration: Duration(seconds: seconds),
                      playCount: 963000,
                      danmakuCount: 10000,
                    ),
                    playCountText: playLabel,
                    danmakuCountText: danmakuLabel,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
