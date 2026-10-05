import 'package:bili_lite/app/theme.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/shared/ui/bili_badges.dart';
import 'package:bili_lite/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search highlights titles with UP badge and hides feed reasons', (
    tester,
  ) async {
    await tester.pumpWidget(_app(showUpBadge: true, query: '视频'));
    expect(find.byType(BiliUpBadge), findsOneWidget);
    expect(find.text('3万点赞'), findsNothing);
    expect(find.text('测试视频', findRichText: true), findsOneWidget);
    final title = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan?.toPlainText() == '测试视频',
      ),
    );
    final span = title.textSpan as TextSpan;
    expect((span.children?.last as TextSpan).style?.color, BiliTheme.accent);
    final cover = tester.getSize(find.byType(AspectRatio));
    expect(cover.width / cover.height, closeTo(16 / 9, .001));
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, .4);
  });

  testWidgets(
    'recommendation badges fit narrow windows and large text in both themes',
    (tester) async {
      for (final width in [220.0, 300.0, 360.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final dark in [false, true]) {
            await tester.pumpWidget(
              _app(width: width, scale: scale, dark: dark, showReason: true),
            );
            await tester.pumpAndSettle();
            expect(find.text('3万点赞'), findsOneWidget);
            expect(find.byType(BiliUpBadge), findsNothing);
            final card = tester.getRect(find.byType(VideoCard));
            for (final label in ['3万点赞', '测试UP', '今天投稿']) {
              final rect = tester.getRect(find.text(label));
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
    },
  );

  testWidgets('missing or blank recommendation reasons create no label', (
    tester,
  ) async {
    for (final reason in [null, '', ' ']) {
      await tester.pumpWidget(_app(showReason: true, reason: reason));
      expect(find.text('已关注'), findsNothing);
      expect(find.text('3万点赞'), findsNothing);
      expect(find.text('测试UP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _app({
  double width = 360,
  double scale = 1,
  bool dark = false,
  bool showUpBadge = false,
  bool showReason = false,
  String query = '',
  String? reason = '3万点赞',
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
            video: VideoSummary(
              id: const VideoId('BV1234567890'),
              title: '测试视频',
              coverUrl: '',
              author: '测试UP',
              duration: const Duration(minutes: 3),
              recommendationReason: reason,
            ),
            showUpBadge: showUpBadge,
            showRecommendationReason: showReason,
            highlightQuery: query,
            publishText: '今天投稿',
            progress: .4,
            onTap: () {},
          ),
        ),
      ),
    ),
  ),
);
