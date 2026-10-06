import 'dart:async';

import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: '标题旁的菜单',
  coverUrl: '',
  author: '测试作者',
  authorId: UserId('7'),
  duration: Duration(seconds: 60),
);
const _recommended = VideoCardMenu(
  actions: [VideoCardMenuAction.notInterested, VideoCardMenuAction.watchLater],
);
const _remove = VideoCardMenu(actions: [VideoCardMenuAction.removeWatchLater]);
final _button = find.byKey(const ValueKey('video-card-title-menu'));

void main() {
  testWidgets(
    'title addition completes silently when the workspace becomes hidden',
    (tester) async {
      final operations = _Operations()..pending = Completer<WatchLaterResult>();
      final notices = <String>[];
      await tester.pumpWidget(
        _card(
          _recommended,
          platform: TargetPlatform.android,
          operations: operations,
          notices: notices.add,
        ),
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后再看'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(
        _card(
          _recommended,
          platform: TargetPlatform.android,
          operations: operations,
          notices: notices.add,
          active: false,
        ),
      );
      operations.pending?.complete(WatchLaterResult.added);
      await tester.pump();
      expect(notices, isEmpty);
      expect(
        tester.widget<PopupMenuButton<VideoCardMenuAction>>(_button).enabled,
        true,
      );
    },
  );

  testWidgets(
    'watch-later delete updates hidden workspace without showing a notice',
    (tester) async {
      final repository = _Home()..pending = Completer<void>();
      var active = true;
      StateSetter? update;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: AppNoticeHost(
              child: StatefulBuilder(
                builder: (_, setter) {
                  update = setter;
                  return WorkspaceActivity(
                    active: active,
                    child: const HomeContent(
                      channel: HomeChannel.watchLater,
                      section: '全部',
                      isSignedIn: true,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_button.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pump(const Duration(milliseconds: 300));
      update?.call(() => active = false);
      await tester.pump();
      repository.pending?.complete();
      await tester.pumpAndSettle();
      expect(find.text('已失效内容'), findsNothing);
      expect(find.text('已从稍后再看删除'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'desktop title menu stays hidden at narrow widths until hover and remains open outside the card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opens = 0;
      final selected = <VideoCardMenuAction>[];
      await tester.pumpWidget(
        _card(
          VideoCardMenu(
            actions: _recommended.actions,
            onSelected: selected.add,
          ),
          open: () => opens++,
        ),
      );
      expect(_opacity(tester), 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.text(_video.title)));
      await tester.pump();
      expect(_opacity(tester), 1);
      final cover = tester.getRect(
        find.byKey(const ValueKey('video-card-cover-scale')),
      );
      expect(tester.getRect(_button).top, greaterThan(cover.bottom));
      await tester.tap(_button);
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.text('不感兴趣')));
      await tester.pump();
      expect(_opacity(tester), 1);
      expect(find.text('稍后再看'), findsOneWidget);
      await tester.tap(find.text('不感兴趣'));
      await tester.pumpAndSettle();
      expect(selected, [VideoCardMenuAction.notInterested]);
      expect(opens, 0);
      await mouse.removePointer();
    },
  );
  testWidgets(
    'keyboard reaches hidden menu and selecting delete cannot activate card or author',
    (tester) async {
      var opens = 0, authors = 0;
      final selected = <VideoCardMenuAction>[];
      await tester.pumpWidget(
        _card(
          VideoCardMenu(actions: _remove.actions, onSelected: selected.add),
          open: () => opens++,
          author: (_) => authors++,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(_opacity(tester), 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('不感兴趣'), findsNothing);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(selected, [VideoCardMenuAction.removeWatchLater]);
      expect(opens, 0);
      expect(authors, 0);
      await tester.tap(find.text(_video.author));
      await tester.pump();
      expect(authors, 1);
      expect(opens, 0);
    },
  );
  testWidgets(
    'touch fallback exposes menu and shared cards without configuration have none',
    (tester) async {
      await tester.pumpWidget(
        _card(_recommended, platform: TargetPlatform.android),
      );
      expect(_opacity(tester), 1);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(find.text('不感兴趣'), findsOneWidget);
      await tester.pumpWidget(_card(null));
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
    },
  );
  testWidgets(
    'title add uses the same operations as the existing cover entry',
    (tester) async {
      final operations = _Operations();
      final notices = <String>[];
      var opens = 0;
      await tester.pumpWidget(
        _card(
          _recommended,
          platform: TargetPlatform.android,
          open: () => opens++,
          operations: operations,
          notices: notices.add,
        ),
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      expect(operations.writes, 1);
      expect(notices, ['已加入稍后再看']);
      expect(opens, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.text(_video.title)));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('video-card-watch-later')),
        findsOneWidget,
      );
      await mouse.removePointer();
      await tester.pump();
    },
  );
  testWidgets(
    'pending title add clears when the account operations are replaced',
    (tester) async {
      final old = _Operations()..pending = Completer<WatchLaterResult>();
      final next = _Operations();
      final notices = <String>[];
      await tester.pumpWidget(
        _card(
          _recommended,
          platform: TargetPlatform.android,
          operations: old,
          notices: notices.add,
        ),
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后再看'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<PopupMenuButton<VideoCardMenuAction>>(_button).enabled,
        false,
      );
      await tester.pumpWidget(
        _card(
          _recommended,
          platform: TargetPlatform.android,
          operations: next,
          notices: notices.add,
        ),
      );
      expect(
        tester.widget<PopupMenuButton<VideoCardMenuAction>>(_button).enabled,
        true,
      );
      old.pending?.complete(WatchLaterResult.added);
      await tester.pump();
      expect(notices, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'recommendation alone configures title menu in the ordinary video feed',
    (tester) async {
      final repository = _Feed();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: const FeedScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_button, findsOneWidget);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: const FeedScreen(channel: HomeChannel.popular),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
    },
  );
  testWidgets(
    'watch-later includes delete for unavailable videos and favorites have no new menu',
    (tester) async {
      final repository = _Home();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: const AppNoticeHost(
              child: HomeContent(
                channel: HomeChannel.watchLater,
                section: '全部',
                isSignedIn: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_button, findsNWidgets(2));
      await tester.tap(_button.last);
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('不感兴趣'), findsNothing);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(repository.removed?.aid, '43');
      expect(find.text('已失效内容'), findsNothing);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: const HomeContent(
              channel: HomeChannel.favorites,
              section: '我创建的收藏夹',
              isSignedIn: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
    },
  );
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: _button, matching: find.byType(Opacity)).first,
    )
    .opacity;

Widget _card(
  VideoCardMenu? menu, {
  VoidCallback? open,
  ValueChanged<UserId>? author,
  TargetPlatform platform = TargetPlatform.windows,
  _Operations? operations,
  void Function(String)? notices,
  bool active = true,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 280,
        child: WorkspaceActivity(
          active: active,
          child: VideoCardInteractionScope(
            interactions: operations ?? _Operations(),
            onNotice: (_, text) => notices?.call(text),
            child: VideoCard(
              video: _video,
              menu: menu,
              onTap: open ?? () {},
              onOpenUser: author,
            ),
          ),
        ),
      ),
    ),
  ),
);

final class _Operations implements VideoCardOperations {
  int writes = 0;
  Completer<WatchLaterResult>? pending;
  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) async => null;
  @override
  bool isAdded(VideoId id) => writes > 0;
  @override
  bool isUncertain(VideoId id) => false;
  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async {
    writes++;
    return pending?.future ?? WatchLaterResult.added;
  }
}

final class _Feed extends Fake implements FeedRepository {
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [_video], hasMore: false);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [_video], hasMore: false);
}

final class _Home implements HomeRepository, HomeWatchLaterRepository {
  HomeEntry? removed;
  Completer<void>? pending;
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => const HomePage([
    HomeEntry(
      id: 'BV1234567890',
      bvid: 'BV1234567890',
      aid: '42',
      title: '可用视频',
      kind: HomeEntryKind.video,
    ),
    HomeEntry(
      id: 'aid:43',
      aid: '43',
      title: '已失效内容',
      kind: HomeEntryKind.video,
    ),
  ], hasMore: false);
  @override
  Future<void> removeWatchLater(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    removed = entry;
    if (pending case final result?) await result.future;
  }
}
