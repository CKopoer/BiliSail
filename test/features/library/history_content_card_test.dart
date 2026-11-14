import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/library/presentation/history_content_card.dart';
import 'package:bilisail/shared/ui/highlighted_text.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _liveMenu = ValueKey('history-content-title-menu');
const _videoMenu = ValueKey('video-card-title-menu');

void main() {
  for (final width in [140.0, 220.0, 320.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'live and video history geometry and typography match at $width / $scale',
        (tester) async {
          await tester.pumpWidget(_app(width: width, scale: scale));
          final live = find.byType(HistoryContentCard);
          final video = find.byType(VideoCard);
          expect(tester.getSize(live), tester.getSize(video));
          Finder cover(Finder card) => find
              .descendant(of: card, matching: find.byType(AspectRatio))
              .first;
          expect(tester.getSize(cover(live)), tester.getSize(cover(video)));
          expect(tester.getSize(cover(live)).width, width - 2);
          final liveTitle = tester.widget<HighlightedText>(
            find
                .descendant(of: live, matching: find.byType(HighlightedText))
                .first,
          );
          final videoTitle = tester.widget<HighlightedText>(
            find
                .descendant(of: video, matching: find.byType(HighlightedText))
                .first,
          );
          expect(liveTitle.style, videoTitle.style);
          expect(liveTitle.maxLines, videoTitle.maxLines);
          for (final text in ['历史作者', '昨天']) {
            final a = find.descendant(of: live, matching: find.text(text));
            final b = find.descendant(of: video, matching: find.text(text));
            expect(tester.widget<Text>(a).style, tester.widget<Text>(b).style);
            expect(tester.getRect(a).top, tester.getRect(b).top);
            expect(tester.getSize(a), tester.getSize(b));
          }
          expect(
            tester.getSize(find.byKey(_liveMenu)),
            tester.getSize(find.byKey(_videoMenu)),
          );
          expect(
            tester.getRect(find.byKey(_liveMenu)).top,
            tester.getRect(find.byKey(_videoMenu)).top,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final screen in [320.0, 1280.0]) {
    testWidgets('live history menu uses the shared action flow at $screen', (
      tester,
    ) async {
      tester.view.physicalSize = Size(screen, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var deletes = 0, opens = 0;
      final platform = screen < 600
          ? TargetPlatform.android
          : TargetPlatform.windows;
      await tester.pumpWidget(
        _app(
          width: 140,
          platform: platform,
          onDelete: () => deletes++,
          onOpen: () => opens++,
        ),
      );
      if (platform == TargetPlatform.windows) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(700, 500));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byType(HistoryContentCard)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(_liveMenu));
      await tester.pumpAndSettle();
      expect(find.text('删除记录'), findsOneWidget);
      expect(
        find.byType(BottomSheet),
        screen < 600 ? findsOneWidget : findsNothing,
      );
      expect(opens, 0);
      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(opens, 0);
    });
  }

  testWidgets('busy live action consumes taps without opening the room', (
    tester,
  ) async {
    var opens = 0, deletes = 0;
    await tester.pumpWidget(
      _app(busy: true, onDelete: () => deletes++, onOpen: () => opens++),
    );
    expect(tester.widget<IconButton>(find.byKey(_liveMenu)).onPressed, isNull);
    await tester.tapAt(tester.getCenter(find.byKey(_liveMenu)));
    await tester.pump();
    expect(opens, 0);
    expect(deletes, 0);
    expect(find.text('删除记录'), findsNothing);
  });

  testWidgets('long press opens the same delete action without navigation', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(_app(onOpen: () => opens++));
    await tester.longPress(find.byType(HistoryContentCard));
    await tester.pumpAndSettle();
    expect(find.text('删除记录'), findsOneWidget);
    expect(opens, 0);
  });
}

Widget _app({
  double width = 220,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.android,
  bool busy = false,
  VoidCallback? onDelete,
  VoidCallback? onOpen,
}) => MaterialApp(
  theme: BiliTheme.light().copyWith(platform: platform),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child ?? const SizedBox.shrink(),
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width,
            child: HistoryContentCard(
              entry: WatchHistoryEntry.content(
                type: HistoryContentType.live,
                id: '12',
                title: '直播历史标题较长，需要占用两行并保持与视频标题同样的行高和留白',
                coverUrl: '',
                author: '历史作者',
                watchedAt: DateTime(2026, 11, 14),
                isLive: true,
              ),
              date: '昨天',
              dateTooltip: '观看于昨天',
              busy: busy,
              onOpen: onOpen ?? () {},
              onDelete: onDelete ?? () {},
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: width,
            child: VideoCard(
              video: const VideoSummary(
                id: VideoId('BV1234567890'),
                title: '视频历史',
                coverUrl: '',
                author: '历史作者',
                duration: Duration(seconds: 20),
              ),
              onTap: () {},
              publishText: '昨天',
              publishTooltip: '观看于昨天',
              menu: const VideoCardMenu(
                actions: [VideoCardMenuAction.removeHistory],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
