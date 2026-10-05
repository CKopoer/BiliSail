import 'package:bili_lite/app/theme.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/shared/ui/video_card.dart';
import 'package:bili_lite/shared/ui/video_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop grid fills the width with five larger cards', (
    tester,
  ) async {
    _setViewport(tester, 1920);
    await tester.pumpWidget(_gridApp(width: 1880));

    final cards = find.byType(VideoCard);
    final first = tester.getRect(cards.at(0));
    final fifth = tester.getRect(cards.at(4));
    final sixth = tester.getRect(cards.at(5));
    expect(fifth.top, first.top);
    expect(sixth.top, greaterThan(first.bottom));
    expect(first.width, closeTo(360, 1));
    expect(fifth.right, closeTo(1880, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards fit narrow windows and double text scale in both themes', (
    tester,
  ) async {
    _setViewport(tester, 1920);
    for (final width in [280.0, 400.0, 720.0, 1880.0]) {
      for (final dark in [false, true]) {
        await tester.pumpWidget(_gridApp(width: width, scale: 2, dark: dark));
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byType(VideoCard).first);
        final author = tester.getRect(find.text('长名称的测试 UP 主').first);
        expect(author.bottom, lessThanOrEqualTo(card.bottom));
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width, dark=$dark',
        );
      }
    }
  });

  testWidgets('card supports pointer feedback and keyboard activation', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 250,
              child: VideoCard(video: _videos.first, onTap: () => opened++),
            ),
          ),
        ),
      ),
    );
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(500, 500));
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(VideoCard)));
    await tester.pumpAndSettle();
    expect(_borderColor(tester), BiliTheme.accent.withValues(alpha: 0.5));

    await pointer.moveTo(const Offset(500, 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_borderColor(tester), BiliTheme.accent);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed cover keeps the card available to open', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: VideoCard(
              video: const VideoSummary(
                id: VideoId('BV1abc123456'),
                title: '封面加载失败的视频',
                coverUrl: 'https://example.invalid/cover.jpg',
                author: '测试 UP',
                duration: Duration(minutes: 3),
              ),
              onTap: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    await tester.tap(find.text('封面加载失败的视频'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Color _borderColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(VideoCard),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return ((container.decoration as BoxDecoration).border as Border).top.color;
}

void _setViewport(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _gridApp({required double width, double scale = 1, bool dark = false}) =>
    MaterialApp(
      theme: dark ? BiliTheme.dark() : BiliTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: VideoGrid(items: _videos, onOpen: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );

final _videos = List.generate(
  12,
  (index) => VideoSummary(
    id: VideoId('BV1abc1234$index'),
    title: '这是一段需要换行并且在较大文字比例下仍然显示两行的视频标题 $index',
    coverUrl: '',
    author: '长名称的测试 UP 主',
    duration: const Duration(hours: 100, minutes: 28, seconds: 32),
    playCount: 192800000,
    danmakuCount: 32000,
  ),
);
