import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/shared/ui/dynamic_post_card.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';

void main() {
  for (final width in [375.0, 1920.0]) {
    testWidgets('dynamic is a centered single column at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(_Repository())],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: HomeContent(
                channel: HomeChannel.dynamic,
                section: '全部',
                isSignedIn: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(DynamicPostCard).evaluate().length,
        inInclusiveRange(2, 6),
      );
      final first = tester.getRect(find.byType(DynamicPostCard).first);
      final second = tester.getRect(find.byType(DynamicPostCard).at(1));
      expect(first.left, second.left);
      expect(second.top, greaterThan(first.bottom));
      expect(first.width, lessThanOrEqualTo(780));
      expect(first.center.dx, width / 2);
      await tester.scrollUntilVisible(
        find.text('动态内容5'),
        300,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('动态内容5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 800.0, 1920.0]) {
    for (final (channel, section) in [
      (HomeChannel.favorites, '默认收藏夹'),
      (HomeChannel.watchLater, '全部'),
      (HomeChannel.watchLater, '未看完'),
    ]) {
      testWidgets(
        '${channel.name} $section uses common cards at $width with enlarged text',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                homeRepositoryProvider.overrideWithValue(_Repository()),
              ],
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: HomeContent(
                    channel: channel,
                    section: section,
                    isSignedIn: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final mountedCards = find.byType(VideoCard).evaluate().length;
          expect(mountedCards, inInclusiveRange(2, 6));
          expect(find.text('2万'), findsNWidgets(mountedCards));
          expect(find.text('100'), findsNWidgets(mountedCards));
          expect(find.text('02:05'), findsNWidgets(mountedCards));
          expect(find.text('测试UP'), findsNWidgets(mountedCards));
          expect(find.text('今天投稿'), findsNWidgets(mountedCards));
          final first = tester.getRect(find.byType(VideoCard).first);
          expect(first.width, lessThanOrEqualTo(width - 40));
          await tester.scrollUntilVisible(
            find.text('这是第5条视频或直播标题'),
            300,
            scrollable: find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          );
          final lastCard = find.ancestor(
            of: find.text('这是第5条视频或直播标题'),
            matching: find.byType(VideoCard),
          );
          expect(
            find.descendant(of: lastCard, matching: find.text('2万')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: lastCard, matching: find.text('今天投稿')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final channel in [HomeChannel.videoDynamic, HomeChannel.live]) {
      testWidgets('${channel.name} fits $width and preserves metadata', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [homeRepositoryProvider.overrideWithValue(repository)],
            child: MaterialApp(
              home: Scaffold(
                body: HomeContent(
                  channel: channel,
                  section: channel.sections.first,
                  isSignedIn: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (channel == HomeChannel.videoDynamic) {
          expect(find.text('投稿视频'), findsNothing);
          expect(
            find.byType(VideoDynamicCard).evaluate().length,
            inInclusiveRange(2, 6),
          );
          final mountedCards = find.byType(VideoCard).evaluate().length;
          expect(mountedCards, inInclusiveRange(2, 6));
          expect(find.byType(BiliUpBadge), findsNothing);
          expect(find.text('2万'), findsNWidgets(mountedCards));
          expect(find.text('100'), findsNWidgets(mountedCards));
          expect(find.text('今天投稿'), findsNWidgets(mountedCards));
          final a = tester.getTopLeft(find.byType(VideoDynamicCard).at(0));
          final b = tester.getTopLeft(find.byType(VideoDynamicCard).at(1));
          expect(a.dy == b.dy, width >= 800);
        } else {
          expect(
            find.byType(LiveRoomCard).evaluate().length,
            inInclusiveRange(2, 6),
          );
          final a = tester.getTopLeft(find.byType(LiveRoomCard).at(0));
          final b = tester.getTopLeft(
            find.byType(LiveRoomCard).at(width == 1920 ? 4 : 0),
          );
          expect(a.dy, b.dy);
          await tester.tap(find.text('游戏'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ChoiceChip, '单机'));
          await tester.pumpAndSettle();
          expect(repository.calls.last.folderId, '2:21');
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

final class _Repository implements HomeRepository {
  final calls = <HomeQuery>[];
  @override
  String get accountScope => 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add(query);
    if (query.section == '全部分区') {
      return const HomePage([
        HomeEntry(
          id: '2',
          title: '游戏',
          kind: HomeEntryKind.folder,
          children: [
            HomeEntry(id: '2:21', title: '单机', kind: HomeEntryKind.folder),
          ],
        ),
      ], hasMore: false);
    }
    return HomePage(
      List.generate(
        6,
        (i) => HomeEntry(
          id: '$i',
          dynamicPost: query.channel == HomeChannel.dynamic
              ? DynamicPost(id: '$i', authorName: '动态作者', text: '动态内容$i')
              : null,
          title: '这是第$i条视频或直播标题',
          kind: query.channel == HomeChannel.live
              ? HomeEntryKind.live
              : HomeEntryKind.video,
          authorName: '测试UP',
          duration: const Duration(seconds: 125),
          bvid: query.channel == HomeChannel.live
              ? null
              : 'BV${i.toString().padLeft(10, '0')}',
          publishText: '今天投稿',
          playCountText: '2万',
          danmakuCountText: '100',
          popularityText: '8万',
          areaName: '单机',
        ),
      ),
      hasMore: false,
    );
  }
}
