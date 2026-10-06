import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:bilisail/shared/ui/video_card.dart';
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

  testWidgets('numeric and decimal text counts share units and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const cases = <({int? count, String label})>[
      (count: null, label: '—'),
      (count: 0, label: '0'),
      (count: 9999, label: '9999'),
      (count: 10000, label: '1.0万'),
      (count: 12345, label: '1.2万'),
      (count: 100000000, label: '1.0亿'),
      (count: 123456789, label: '1.2亿'),
    ];
    try {
      for (final asText in [false, true]) {
        for (final item in cases) {
          await tester.pumpWidget(
            _app(
              video: VideoSummary(
                id: const VideoId('BV1234567890'),
                title: '测试视频',
                coverUrl: '',
                author: '测试UP',
                duration: const Duration(minutes: 3),
                playCount: asText ? null : item.count,
                danmakuCount: asText ? null : item.count,
              ),
              playCountText: asText ? item.count?.toString() ?? '' : '',
              danmakuCountText: asText ? item.count?.toString() ?? '' : '',
            ),
          );
          expect(find.text(item.label), findsNWidgets(2));
          expect(
            find.bySemanticsLabel(
              RegExp(
                RegExp.escape('观看 ${item.label}，弹幕 ${item.label}，时长 03:00'),
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'server count text takes precedence and preserves abbreviations',
    (tester) async {
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title: '测试视频',
        coverUrl: '',
        author: '测试UP',
        duration: Duration(minutes: 3),
        playCount: 9,
        danmakuCount: 8,
      );
      for (final labels in [
        ('12345', '100000000', '1.2万', '1.0亿'),
        ('1.23万', '2.34亿', '1.23万', '2.34亿'),
        ('—', '未知', '—', '未知'),
      ]) {
        await tester.pumpWidget(
          _app(
            video: video,
            playCountText: labels.$1,
            danmakuCountText: labels.$2,
          ),
        );
        expect(find.text(labels.$3), findsOneWidget);
        expect(find.text(labels.$4), findsOneWidget);
        expect(find.text('9'), findsNothing);
        expect(find.text('8'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('blank count text falls back without replacing zero or missing', (
    tester,
  ) async {
    const video = VideoSummary(
      id: VideoId('BV1234567890'),
      title: '测试视频',
      coverUrl: '',
      author: '测试UP',
      duration: Duration(minutes: 3),
      playCount: 12345,
    );
    await tester.pumpWidget(
      _app(video: video, playCountText: ' ', danmakuCountText: ''),
    );
    expect(find.text('1.2万'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await tester.pumpWidget(
      _app(video: video, playCountText: '0', danmakuCountText: '0'),
    );
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('1.2万'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact cards keep fitting cover and author metadata on one row',
    (tester) async {
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title: '只要双腿跑得快，没有打骂只有爱',
        coverUrl: '',
        author: 'QQ漫画社',
        duration: Duration(minutes: 2, seconds: 11),
        playCount: 5396,
        danmakuCount: 7,
      );
      for (final width in [140.0, 183.0, 220.0]) {
        await tester.pumpWidget(
          _app(width: width, video: video, publishText: '9-29'),
        );
        await tester.pumpAndSettle();
        final play = tester.getRect(find.text('5396'));
        final danmaku = tester.getRect(find.text('7'));
        final duration = tester.getRect(find.text('02:11'));
        expect(play.center.dy, closeTo(duration.center.dy, .01));
        expect(danmaku.center.dy, closeTo(duration.center.dy, .01));
        expect(play.right, lessThan(danmaku.left));
        expect(danmaku.right, lessThan(duration.left));
        expect(
          tester.getCenter(find.text(video.author)).dy,
          closeTo(tester.getCenter(find.text('9-29')).dy, .01),
        );
        for (final label in ['5396', '7', '02:11', video.author, '9-29']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$width: $label',
          );
        }
        expect(tester.takeException(), isNull, reason: 'width=$width');
      }
    },
  );

  testWidgets('long titles and authors ellipsize as card width changes', (
    tester,
  ) async {
    const video = VideoSummary(
      id: VideoId('BV1234567890'),
      title:
          '这是一个很长的视频标题，用来验证卡片宽度改变后最多展示两行，剩余的所有内容都应该以省略号结束，'
          '即使在较宽的卡片中也不能出现第三行，更不能直接裁掉文本而不展示省略号',
      coverUrl: '',
      author: '这是一个很长很长很长很长很长很长很长的UP主名称',
      duration: Duration(hours: 100, minutes: 28, seconds: 32),
      playCount: 192800000,
      danmakuCount: 32000,
      recommendationReason: '3万点赞',
    );
    for (final scale in [1.0, 2.0]) {
      double? previousAuthorWidth;
      for (final width in [140.0, 183.0, 360.0]) {
        await tester.pumpWidget(
          _app(
            width: width,
            scale: scale,
            showUpBadge: true,
            showReason: true,
            query: '视频',
            video: video,
            publishText: '2025-09-29',
          ),
        );
        await tester.pumpAndSettle();
        final title = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.textSpan?.toPlainText() == video.title,
        );
        final author = find.text(video.author);
        final titleParagraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: title, matching: find.byType(RichText)),
        );
        final authorParagraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: author, matching: find.byType(RichText)),
        );
        expect(
          titleParagraph.didExceedMaxLines,
          isTrue,
          reason: '$width, $scale',
        );
        expect(titleParagraph.maxLines, 2);
        expect(titleParagraph.overflow, TextOverflow.ellipsis);
        expect(authorParagraph.didExceedMaxLines, isTrue);
        expect(authorParagraph.maxLines, 1);
        expect(authorParagraph.overflow, TextOverflow.ellipsis);
        final authorWidth = tester.getSize(author).width;
        if (previousAuthorWidth != null) {
          expect(authorWidth, greaterThan(previousAuthorWidth));
        }
        previousAuthorWidth = authorWidth;
        expect(
          tester.getCenter(author).dy,
          closeTo(tester.getCenter(find.text('2025-09-29')).dy, .01),
        );
        expect(tester.takeException(), isNull, reason: '$width, scale=$scale');
      }
    }
  });

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
  VideoSummary? video,
  String playCountText = '',
  String danmakuCountText = '',
  String publishText = '今天投稿',
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
            video:
                video ??
                VideoSummary(
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
            publishText: publishText,
            playCountText: playCountText,
            danmakuCountText: danmakuCountText,
            progress: .4,
            onTap: () {},
          ),
        ),
      ),
    ),
  ),
);
