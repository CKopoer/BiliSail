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
import 'package:bilisail/features/profile/presentation/profile_video_card.dart';
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
  for (final menu in [
    null,
    _recommended,
    const VideoCardMenu(actions: [VideoCardMenuAction.removeHistory]),
  ]) {
    testWidgets(
      'shared long press toggles existing membership with menu $menu',
      (tester) async {
        _setWindow(tester, const Size(390, 700));
        final operations = _ToggleOperations()..added = true;
        var opens = 0;
        final notices = <String>[];
        await tester.pumpWidget(
          _card(
            menu,
            operations: operations,
            open: () => opens++,
            notices: notices.add,
          ),
        );
        await tester.longPress(find.byType(AspectRatio));
        await tester.pumpAndSettle();
        expect(find.text('取消稍后再看'), findsOneWidget);
        expect(find.text('稍后再看'), findsNothing);
        await tester.tap(find.text('取消稍后再看'));
        await tester.pumpAndSettle();
        expect(operations.removals, 1);
        expect(operations.writes, 0);
        expect(opens, 0);
        expect(notices, ['已取消稍后再看']);
        await tester.longPress(find.byType(AspectRatio));
        await tester.pumpAndSettle();
        expect(find.text('稍后再看'), findsOneWidget);
        await tester.tap(find.text('稍后再看'));
        await tester.pumpAndSettle();
        expect(operations.writes, 1);
        expect(opens, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'hover check cancels without opening the video and returns to add',
    (tester) async {
      final operations = _ToggleOperations()..added = true;
      var opens = 0;
      await tester.pumpWidget(
        _card(null, operations: operations, open: () => opens++),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.byType(AspectRatio)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byTooltip('取消稍后再看'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
      await tester.pumpAndSettle();
      expect(operations.removals, 1);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
      await tester.pumpAndSettle();
      expect(operations.writes, 1);
      expect(opens, 0);
      await mouse.removePointer();
    },
  );

  testWidgets('horizontal profile card shares the narrow cancel sheet', (
    tester,
  ) async {
    _setWindow(tester, const Size(390, 700));
    final operations = _ToggleOperations()..added = true;
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCardInteractionScope(
            interactions: operations,
            onNotice: (_, _) {},
            child: ProfileVideoCard(video: _video, onTap: () => opens++),
          ),
        ),
      ),
    );
    await tester.longPress(find.text(_video.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消稍后再看'));
    await tester.pumpAndSettle();
    expect(operations.removals, 1);
    expect(opens, 0);
  });

  testWidgets(
    'membership read failure opens no misleading action and writes nothing',
    (tester) async {
      _setWindow(tester, const Size(390, 700));
      final operations = _ToggleOperations()..loaded = false;
      final notices = <String>[];
      await tester.pumpWidget(
        _card(null, operations: operations, notices: notices.add),
      );
      await tester.longPress(find.byType(AspectRatio));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(operations.writes, 0);
      expect(operations.removals, 0);
      expect(notices.single, contains('无法读取稍后再看状态'));
    },
  );

  for (final width in [390.0, 599.0, 600.0, 1000.0]) {
    for (final longPress in [true, false]) {
      testWidgets(
        '${longPress ? 'long press' : 'button'} at $width uses the same actions and one selection',
        (tester) async {
          _setWindow(tester, Size(width, 700));
          final selected = <VideoCardMenuAction>[];
          final operations = _Operations();
          var opens = 0;
          await tester.pumpWidget(
            _card(
              VideoCardMenu(
                actions: _recommended.actions,
                onSelected: selected.add,
              ),
              platform: TargetPlatform.android,
              operations: operations,
              open: () => opens++,
            ),
          );
          final anchor = tester.getRect(_button);
          if (longPress) {
            await tester.longPress(find.byType(AspectRatio));
          } else {
            await tester.tap(_button);
          }
          await tester.pumpAndSettle();
          expect(find.text('不感兴趣'), findsOneWidget);
          expect(find.text('稍后再看'), findsOneWidget);
          expect(find.text('取消稍后再看'), findsNothing);
          expect(find.text('收藏'), findsNothing);
          expect(operations.writes, 0);
          expect(selected, isEmpty);
          expect(opens, 0);
          if (width < 600) {
            expect(find.byType(BottomSheet), findsOneWidget);
            expect(
              find.byType(PopupMenuItem<VideoCardMenuAction>),
              findsNothing,
            );
            expect(tester.getRect(find.byType(BottomSheet)).bottom, 700);
            // A second tap during reverse animation cannot pop the page.
            final position = tester.getCenter(find.text('不感兴趣'));
            await tester.tapAt(position);
            await tester.tapAt(position);
          } else {
            expect(find.byType(BottomSheet), findsNothing);
            final item = tester.getRect(
              find.byType(PopupMenuItem<VideoCardMenuAction>).first,
            );
            expect(item.top, closeTo(anchor.bottom + 8, 1));
            expect(item.right, closeTo(anchor.right, 1));
            await tester.tap(find.text('不感兴趣'));
          }
          await tester.pumpAndSettle();
          expect(selected, [VideoCardMenuAction.notInterested]);
          expect(opens, 0);
          expect(find.byType(VideoCard), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'long press on overflowing title and author opens only the menu',
    (tester) async {
      _setWindow(tester, const Size(390, 700));
      final operations = _Operations();
      var opens = 0, authors = 0;
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title:
            '很长的视频标题'
            '很长的视频标题'
            '很长的视频标题'
            '很长的视频标题',
        coverUrl: '',
        author: '测试作者',
        authorId: UserId('7'),
        duration: Duration(seconds: 60),
      );
      await tester.pumpWidget(
        _card(
          _recommended,
          video: video,
          platform: TargetPlatform.iOS,
          operations: operations,
          open: () => opens++,
          author: (_) => authors++,
        ),
      );
      for (final text in [video.title, video.author]) {
        await tester.longPress(find.text(text));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('不感兴趣'), findsOneWidget);
        expect(opens, 0);
        expect(authors, 0);
        expect(operations.writes, 0);
        await tester.tapAt(const Offset(5, 400));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      }
      await tester.tap(find.text(video.title));
      expect(opens, 1);
    },
  );

  testWidgets('scrolling and cancelled holds never open a menu or video', (
    tester,
  ) async {
    var opens = 0;
    final operations = _Operations();
    await tester.pumpWidget(
      _card(_recommended, open: () => opens++, operations: operations),
    );
    final position = tester.getCenter(find.byType(AspectRatio));
    final cancelled = await tester.startGesture(position);
    await tester.pump(const Duration(milliseconds: 200));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    final scrolling = await tester.startGesture(position);
    await scrolling.moveBy(const Offset(0, 70));
    await tester.pump(const Duration(seconds: 1));
    await scrolling.up();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PopupMenuItem<VideoCardMenuAction>), findsNothing);
    expect(opens, 0);
    expect(operations.writes, 0);
  });

  testWidgets('busy, empty and feedback cards do not show menus or navigate', (
    tester,
  ) async {
    var opens = 0;
    for (final (menu, feedback) in [
      (null, null),
      (const VideoCardMenu(actions: [], busy: false), null),
      (VideoCardMenu(actions: _recommended.actions, busy: true), null),
      (_recommended, const VideoCardFeedback()),
    ]) {
      await tester.pumpWidget(
        _card(
          menu,
          feedback: feedback,
          platform: TargetPlatform.android,
          open: () => opens++,
        ),
      );
      await tester.longPress(find.byType(AspectRatio));
      await tester.pump();
      if (_button.evaluate().isNotEmpty) await tester.tap(_button);
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PopupMenuItem<VideoCardMenuAction>), findsNothing);
      expect(opens, 0);
    }
    // Dispose the busy spinner instead of waiting for it to settle.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow history menu keeps its action set, theme and safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final selected = <VideoCardMenuAction>[];
    await tester.pumpWidget(
      _card(
        VideoCardMenu(
          actions: const [VideoCardMenuAction.removeHistory],
          onSelected: selected.add,
        ),
        platform: TargetPlatform.android,
        theme: ThemeData.dark().copyWith(platform: TargetPlatform.android),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.longPress(find.byType(AspectRatio));
    await tester.pumpAndSettle();
    expect(find.text('删除记录'), findsOneWidget);
    expect(find.text('稍后再看'), findsNothing);
    final tile = find.widgetWithText(ListTile, '删除记录');
    expect(tester.getRect(tile).bottom, lessThanOrEqualTo(700 - 34));
    final context = tester.element(tile);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(MediaQuery.textScalerOf(context).scale(15), 30);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(selected, [VideoCardMenuAction.removeHistory]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selection is ignored after operations, activity or menu changes',
    (tester) async {
      final original = _Operations();
      final replacement = _Operations();
      for (final change in ['account', 'hidden', 'busy', 'actions']) {
        final selected = <VideoCardMenuAction>[];
        final initial = VideoCardMenu(
          actions: _recommended.actions,
          onSelected: selected.add,
        );
        await tester.pumpWidget(_card(initial, operations: original));
        await tester.longPress(find.byType(AspectRatio));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _card(
            VideoCardMenu(
              actions: change == 'actions' ? _remove.actions : initial.actions,
              onSelected: selected.add,
              busy: change == 'busy',
            ),
            operations: change == 'account' ? replacement : original,
            active: change != 'hidden',
          ),
        );
        await tester.tap(find.text('不感兴趣'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(selected, isEmpty);
        expect(original.writes, 0);
        expect(replacement.writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

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
      expect(tester.widget<IconButton>(_button).onPressed, isNotNull);
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
      await tester.tap(find.text('取消稍后再看'));
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
      _setWindow(tester, const Size(320, 500));
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
      expect(find.text('取消稍后再看'), findsOneWidget);
      expect(find.text('不感兴趣'), findsNothing);
      await tester.tap(find.text('取消稍后再看'));
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
      expect(tester.widget<IconButton>(_button).onPressed, isNull);
      await tester.pumpWidget(
        _card(
          _recommended,
          platform: TargetPlatform.android,
          operations: next,
          notices: notices.add,
        ),
      );
      expect(tester.widget<IconButton>(_button).onPressed, isNotNull);
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
      expect(find.text('取消稍后再看'), findsOneWidget);
      expect(find.text('不感兴趣'), findsNothing);
      await tester.tap(find.text('取消稍后再看'));
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

void _setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _card(
  VideoCardMenu? menu, {
  VideoSummary video = _video,
  VideoCardFeedback? feedback,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  VoidCallback? open,
  ValueChanged<UserId>? author,
  TargetPlatform platform = TargetPlatform.windows,
  VideoCardOperations? operations,
  void Function(String)? notices,
  bool active = true,
}) => MaterialApp(
  theme: theme ?? ThemeData(platform: platform),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child ?? const SizedBox(),
  ),
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
              video: video,
              menu: menu,
              feedback: feedback,
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

final class _ToggleOperations
    implements VideoCardOperations, VideoCardWatchLaterToggle {
  bool added = false;
  bool loaded = true;
  int writes = 0, removals = 0;
  @override
  Stream<VideoId> get watchLaterChanges => const Stream.empty();
  @override
  bool isWatchLaterBusy(VideoId id) => false;
  @override
  Future<bool> refreshWatchLater() async => loaded;
  @override
  bool isAdded(VideoId id) => added;
  @override
  bool isUncertain(VideoId id) => false;
  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async {
    writes++;
    added = true;
    return WatchLaterResult.added;
  }

  @override
  Future<WatchLaterResult> removeWatchLater(VideoId id) async {
    removals++;
    added = false;
    return WatchLaterResult.removed;
  }

  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) async => null;
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
