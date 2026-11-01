import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSummary _video(int index, {String? title}) => VideoSummary(
  id: VideoId('BV1abc${index.toString().padLeft(6, '0')}'),
  title: title ?? 'Video $index',
  coverUrl: '',
  author: 'Author $index',
  authorId: const UserId('7'),
  duration: const Duration(minutes: 2),
);

void main() {
  testWidgets(
    'same-ID follow changes invalidate cached recommendation content',
    (tester) async {
      final followed = ValueNotifier<bool?>(null);
      addTearDown(followed.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: followed,
              builder: (_, value, _) => SizedBox(
                width: 300,
                child: VideoCard(
                  video: VideoSummary(
                    id: const VideoId('BV1234567890'),
                    title: '推荐视频',
                    coverUrl: '',
                    author: 'UP',
                    duration: const Duration(minutes: 1),
                    isFollowed: value,
                  ),
                  onTap: () {},
                  showRecommendationReason: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('已关注'), findsNothing);
      followed.value = true;
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsOneWidget);
      followed.value = false;
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('content changes and cached undo use current data and actions', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    final undone = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: revision,
            builder: (_, value, _) => SizedBox(
              width: value < 3 ? 300 : 220,
              child: VideoCard(
                video: _video(0, title: value < 1 ? 'Original' : 'Updated'),
                onTap: () {},
                progress: value < 1 ? .1 : .7,
                publishText: value < 1 ? 'Yesterday' : 'Today',
                feedback: value < 2
                    ? null
                    : VideoCardFeedback(onUndo: () => undone.add(value)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    revision.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsNothing);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .7,
    );
    revision.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('内容不感兴趣'), findsOneWidget);
    revision.value = 3;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(VideoCard)).width, 220);
    // Same visual state, a different action after the resize has settled.
    revision.value = 4;
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    expect(undone, [4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('append reuses visible card contents and refreshes callbacks', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: revision,
            builder: (_, value, _) => CustomScrollView(
              slivers: [
                SliverVideoGrid.indexed(
                  // Recreated summaries also occur in watch-later/favorite mappings.
                  items: List.generate(100 + value * 30, _video),
                  onOpen: (index) => calls.add('open $value $index'),
                  onOpenUser: (id) => calls.add('user $value $id'),
                  menuAt: (index) => VideoCardMenu(
                    actions: const [VideoCardMenuAction.removeHistory],
                    onSelected: (_) => calls.add('remove $value $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var titles = 0;
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final extent = position.maxScrollExtent;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget case Text(:final data?)
          when data.startsWith('Video ')) {
        titles++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    revision.value++;
    await tester.pumpAndSettle();
    expect(titles, 0);
    expect(position.maxScrollExtent, greaterThan(extent));
    debugOnRebuildDirtyWidget = null;
    await tester.tap(find.text('Video 0'));
    await tester.tap(find.text('Author 0'));
    await tester.tap(find.byKey(const ValueKey('video-card-title-menu')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    expect(calls, ['open 1 0', 'user 1 7', 'remove 1 0']);
    expect(tester.takeException(), isNull);
  });
}
