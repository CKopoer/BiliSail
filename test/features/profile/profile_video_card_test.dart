import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/features/profile/presentation/profile_video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final video = VideoSummary(
    id: const VideoId('BV1234567890'),
    title: '这是一个很长的投稿标题，用来验证窄窗口与文字放大时依然只有两行并且不会溢出',
    coverUrl: '',
    author: '投稿作者',
    duration: const Duration(minutes: 12, seconds: 34),
    playCount: 23456,
    danmakuCount: 123,
    publishedAt: DateTime(2026, 10, 5),
  );

  for (final width in [343.0, 560.0, 630.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('submission card at width $width and text scale $scale', (
        tester,
      ) async {
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: ProfileVideoCard(
                      video: video,
                      onTap: () => opened = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('12:34'), findsOneWidget);
        expect(find.text('2.3万'), findsOneWidget);
        expect(find.text('123'), findsOneWidget);
        expect(find.text('发表于 2026-10-05'), findsOneWidget);
        final title = tester.widget<Text>(find.text(video.title));
        expect(title.maxLines, 2);
        final cover = tester.getSize(find.byType(ClipRRect));
        expect(cover.width, lessThanOrEqualTo(200));
        expect(cover.height, closeTo(cover.width * .6, .01));
        await tester.tap(find.text(video.title));
        expect(opened, isTrue);
      });
    }
  }
}
