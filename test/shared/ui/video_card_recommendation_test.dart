import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSummary _video({String? reason, bool? followed, DateTime? publishedAt}) =>
    VideoSummary(
      id: const VideoId('BV1234567890'),
      title: '推荐视频',
      coverUrl: '',
      author: '推荐UP',
      duration: const Duration(minutes: 1),
      recommendationReason: reason,
      isFollowed: followed,
      publishedAt: publishedAt,
    );

Widget _app({
  required VideoSummary video,
  bool showReason = true,
  double width = 300,
  double scale = 1,
  bool dark = false,
}) => MaterialApp(
  theme: dark ? BiliTheme.dark() : BiliTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: VideoCard(
            video: video,
            onTap: () {},
            showRecommendationReason: showReason,
            showUpBadge: true,
            publishText: '10-31',
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('publication times use comment formatting at the bottom right', (
    tester,
  ) async {
    final now = DateTime.now();
    for (final (date, label) in [
      (now.subtract(const Duration(seconds: 10)), '刚刚'),
      (now.subtract(const Duration(minutes: 5, seconds: 10)), '5分钟前'),
      (now.subtract(const Duration(hours: 2, seconds: 10)), '2小时前'),
      (DateTime(2020, 1, 2), '2020-01-02'),
    ]) {
      await tester.pumpWidget(_app(video: _video(publishedAt: date)));
      expect(find.text(label), findsOneWidget);
      expect(find.text('10-31'), findsNothing);
      final card = tester.getRect(find.byType(VideoCard));
      final time = tester.getRect(find.text(label));
      final author = tester.getRect(find.text('推荐UP'));
      expect(time.right, lessThanOrEqualTo(card.right));
      expect(time.left, greaterThan(author.right));
      expect(time.center.dy, closeTo(author.center.dy, 1));
      expect(time.bottom, lessThanOrEqualTo(card.bottom));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('explicit follow metadata supplies the missing badge', (
    tester,
  ) async {
    await tester.pumpWidget(_app(video: _video(followed: true)));
    expect(find.text('已关注'), findsOneWidget);
    expect(find.byTooltip('已关注'), findsOneWidget);

    for (final followed in [null, false]) {
      await tester.pumpWidget(_app(video: _video(followed: followed)));
      expect(find.text('已关注'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'follow text is not duplicated or inferred from arbitrary reasons',
    (tester) async {
      for (final text in ['已关注', '新关注']) {
        await tester.pumpWidget(
          _app(video: _video(reason: text, followed: true)),
        );
        expect(find.text(text), findsOneWidget);
        if (text == '新关注') expect(find.text('已关注'), findsNothing);
      }
      await tester.pumpWidget(_app(video: _video(reason: '关注的人也在看')));
      expect(find.text('关注的人也在看'), findsOneWidget);
      expect(find.text('已关注'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recommendation presentation remains opt-in', (tester) async {
    await tester.pumpWidget(
      _app(video: _video(reason: '3万点赞', followed: true), showReason: false),
    );
    expect(find.text('3万点赞'), findsNothing);
    expect(find.text('已关注'), findsNothing);
    expect(find.text('推荐UP'), findsOneWidget);
  });

  testWidgets('both badges fit compact cards, scaled text and both themes', (
    tester,
  ) async {
    const reason = '因为你关注了相关内容而推荐';
    for (final width in [140.0, 183.0, 300.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            _app(
              video: _video(reason: reason, followed: true),
              width: width,
              scale: scale,
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(reason), findsOneWidget);
          expect(find.text('已关注'), findsOneWidget);
          expect(find.byTooltip(reason), findsOneWidget);
          final card = tester.getRect(find.byType(VideoCard));
          for (final label in [reason, '已关注', '推荐UP', '10-31']) {
            final rect = tester.getRect(find.text(label));
            expect(rect.left, greaterThanOrEqualTo(card.left));
            expect(rect.right, lessThanOrEqualTo(card.right));
            expect(rect.bottom, lessThanOrEqualTo(card.bottom));
          }
          expect(
            tester.takeException(),
            isNull,
            reason: 'width=$width, scale=$scale, dark=$dark',
          );
        }
      }
    }
  });
}
