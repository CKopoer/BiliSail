import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'warm primary switches keep both lazy lists and scroll positions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feed = _Feed();
      final home = _Home();
      final selected = ValueNotifier(HomeChannel.recommended);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_app(feed, home, selected, signedIn: true));
      await tester.pumpAndSettle();
      ScrollPosition listPosition() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final recommendationPosition = listPosition()..jumpTo(400);
      await tester.pumpAndSettle();
      selected.value = HomeChannel.videoDynamic;
      await tester.pumpAndSettle();
      // Video dynamics must have only their own list, including hidden trees.
      expect(
        find.byType(CustomScrollView, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(HomeContent),
          matching: find.byType(CustomScrollView, skipOffstage: false),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      final dynamicPosition = listPosition()..jumpTo(600);
      await tester.pumpAndSettle();
      final retained = tester.widget<HomeContent>(find.byType(HomeContent));
      final cards = find.byType(VideoCard).evaluate().length;
      expect(cards, inInclusiveRange(2, 20));
      selected.value = HomeChannel.recommended;
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        final positions = {
          for (final state in tester.stateList<ScrollableState>(
            find.byType(Scrollable, skipOffstage: false),
          ))
            state: state.position,
        };
        selected.value = HomeChannel.videoDynamic;
        await tester.pumpAndSettle();
        expect(listPosition(), same(dynamicPosition));
        expect(listPosition().pixels, 600);
        expect(tester.widget(find.byType(HomeContent)), same(retained));
        for (final entry in positions.entries) {
          expect(entry.key.position, same(entry.value));
        }
        selected.value = HomeChannel.recommended;
        await tester.pumpAndSettle();
        expect(listPosition(), same(recommendationPosition));
        expect(listPosition().pixels, 400);
        expect(
          find.byType(VideoCard).evaluate().length,
          inInclusiveRange(2, 20),
        );
      }
      expect(feed.reads, 1);
      expect(home.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained channel uses latest login action and account state', (
    tester,
  ) async {
    final feed = _Feed();
    final home = _Home();
    final selected = ValueNotifier(HomeChannel.videoDynamic);
    addTearDown(selected.dispose);
    var first = 0;
    var latest = 0;
    await tester.pumpWidget(_app(feed, home, selected, onLogin: () => first++));
    await tester.pumpAndSettle();
    final retained = tester.widget<HomeContent>(find.byType(HomeContent));
    await tester.pumpWidget(
      _app(feed, home, selected, onLogin: () => latest++),
    );
    await tester.pumpAndSettle();
    expect(tester.widget(find.byType(HomeContent)), same(retained));
    await tester.tap(find.text('登录账号'));
    expect(first, 0);
    expect(latest, 1);
    await tester.pumpWidget(_app(feed, home, selected));
    await tester.pumpAndSettle();
    expect(find.text('登录账号'), findsNothing);
    expect(latest, 1);
    await tester.pumpWidget(_app(feed, home, selected, signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('登录后可查看视频动态'), findsNothing);
    expect(find.byType(VideoCard), findsWidgets);
    selected.value = HomeChannel.recommended;
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(feed, home, selected));
    await tester.pumpAndSettle();
    selected.value = HomeChannel.videoDynamic;
    await tester.pumpAndSettle();
    expect(find.text('登录后可查看视频动态'), findsOneWidget);
    expect(find.byType(VideoCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  _Feed feed,
  _Home home,
  ValueNotifier<HomeChannel> selected, {
  bool signedIn = false,
  VoidCallback? onLogin,
}) => ProviderScope(
  overrides: [
    feedRepositoryProvider.overrideWithValue(feed),
    homeRepositoryProvider.overrideWithValue(home),
  ],
  child: MaterialApp(
    theme: ThemeData(platform: TargetPlatform.android),
    home: Scaffold(
      body: ValueListenableBuilder(
        valueListenable: selected,
        builder: (_, channel, _) => FeedScreen(
          channel: channel,
          isSignedIn: signedIn,
          onLogin: onLogin,
          onChannelChanged: (value) => selected.value = value,
          channelGroups: const [
            [HomeChannel.recommended, HomeChannel.popular],
            [HomeChannel.dynamic, HomeChannel.videoDynamic],
          ],
        ),
      ),
    ),
  ),
);

final class _Feed implements FeedRepository {
  int reads = 0;
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    return PageResult(
      items: List.generate(
        500,
        (i) => VideoSummary(
          id: VideoId('BV1abc${i.toString().padLeft(6, '0')}'),
          title: '推荐 $i',
          author: '测试作者',
          coverUrl: '',
          duration: const Duration(minutes: 1),
        ),
      ),
      hasMore: false,
    );
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
}

final class _Home implements HomeRepository {
  int reads = 0;
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    return HomePage([
      for (var i = 0; i < 500; i++)
        HomeEntry(
          id: '$i',
          title: '动态 $i',
          kind: HomeEntryKind.video,
          bvid: 'BV1abc${i.toString().padLeft(6, '0')}',
        ),
    ], hasMore: false);
  }
}
