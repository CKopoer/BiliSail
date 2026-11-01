import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recommendation grid shows follow metadata without a reason', (
    tester,
  ) async {
    for (final channel in [HomeChannel.recommended, HomeChannel.popular]) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  FeedVideoGrid(
                    items: const [
                      VideoSummary(
                        id: VideoId('BV1234567890'),
                        title: '关注视频',
                        coverUrl: '',
                        author: 'UP',
                        duration: Duration(minutes: 1),
                        isFollowed: true,
                      ),
                    ],
                    channel: channel,
                    onReject: (_) {},
                    onUndo: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('已关注'),
        channel == HomeChannel.recommended ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('retained-content marker spans the grid and can be hidden', (
    tester,
  ) async {
    final boundary = ValueNotifier<int?>(1);
    addTearDown(boundary.dispose);
    final items = [
      for (var index = 0; index < 3; index++)
        VideoSummary(
          id: VideoId('video$index'),
          title: '视频 $index',
          coverUrl: '',
          author: 'UP',
          duration: const Duration(minutes: 1),
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: boundary,
              builder: (_, value, _) => CustomScrollView(
                slivers: [
                  FeedVideoGrid(
                    items: items,
                    channel: HomeChannel.recommended,
                    previousStartIndex: value,
                    onReject: (_) {},
                    onUndo: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上次看到这里'), findsOneWidget);
    expect(
      tester.getRect(find.text('视频 0')).bottom,
      lessThan(tester.getRect(find.text('上次看到这里')).top),
    );
    expect(
      tester.getRect(find.text('视频 1')).top,
      greaterThan(tester.getRect(find.text('上次看到这里')).bottom),
    );
    boundary.value = null;
    await tester.pumpAndSettle();
    expect(find.text('上次看到这里'), findsNothing);
    expect(find.text('视频 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
