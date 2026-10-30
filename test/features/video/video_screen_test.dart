import '../../support/input_test_app.dart';
import '../../support/text_selection.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/application/watch_later_removal_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';
import 'package:bilisail/features/video/presentation/video_author_header.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/video/presentation/video_collection_panel.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/video/presentation/watch_later_queue_panel.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/shared/ui/playback_page_commands.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:bilisail/shared/ui/paging_tab_strip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';

void main() {
  for (final (width, complete, folderId) in [
    for (final folderId in [null, '42'])
      for (final width in [360.0, 1200.0])
        for (final complete in [false, true]) (width, complete, folderId),
  ]) {
    testWidgets(
      '${folderId == null ? 'UP' : 'favorite'} playlist loads the next page at EOF once and retains player at $width continuous=$complete',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const current = VideoId('BV1abc123456');
        const next = VideoId('BV2abc123456');
        final detail = await const _VideoRepository().loadDetail(
          current,
          cancellation: RequestCancellation(),
        );
        final session = _ProfilePagingSession(detail);
        addTearDown(session.snapshots.dispose);
        final repository = _ProfilePagingRepository(expectedFolderId: folderId);
        final registry = WatchLaterQueueRegistry();
        final queue = registry.capture(
          scope: 'user:7',
          sessionEpoch: 0,
          items: [WatchLaterQueueItem(video: detail.summary)],
          profileSource: ProfileVideoQueueSource(
            userId: const UserId('7'),
            name: '测试UP',
            order: 'pubdate',
            folderId: folderId,
          ),
          favoriteTitle: folderId == null ? null : '测试收藏夹',
          hasMore: true,
          nextPage: 2,
        )!;
        final opened = <VideoId>[];
        var created = 0, disposed = 0;
        PlaybackPageCommands? commands;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackSessionProvider.overrideWithValue(session),
              profileRepositoryProvider.overrideWithValue(repository),
              watchLaterQueueRegistryProvider.overrideWithValue(registry),
              authControllerProvider.overrideWith(_QueueSignedInAuth.new),
              videoRepositoryProvider.overrideWithValue(
                const _VideoRepository(includeCollection: false),
              ),
              videoExtrasRepositoryProvider.overrideWithValue(
                _ExtrasRepository(),
              ),
            ],
            child: InputTestApp(
              home: Scaffold(
                body: VideoScreen(
                  id: current,
                  queue: queue,
                  initialCid: detail.parts.last.cid,
                  onOpenQueueVideo: opened.add,
                  playerBuilder: (context, _, _) {
                    commands = PlaybackPageCommands.maybeOf(context);
                    return _TrackedPlayer(
                      onCreate: () => created++,
                      onDispose: () => disposed++,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        // The pending page displays a spinner; settling would run its timeout.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        final title = folderId == null ? '测试UP的投稿' : '测试收藏夹';
        expect(find.text(title), findsOneWidget);
        expect(repository.reads, 0);
        expect(commands?.hasNext, true);
        if (complete) {
          commands?.onCompleted?.call();
          commands?.onCompleted?.call();
        } else {
          tester
              .widget<WatchLaterQueuePanel>(find.byType(WatchLaterQueuePanel))
              .onLoadMore
              ?.call();
        }
        await tester.pump();
        expect(repository.reads, 1);
        repository.pending.complete(
          ProfilePage(
            items: [
              ProfileEntry(
                id: next.value,
                kind: ProfileEntryKind.video,
                title: '下一条投稿',
                video: VideoSummary(
                  id: next,
                  title: '下一条投稿',
                  coverUrl: '',
                  author: 'UP',
                  duration: const Duration(minutes: 1),
                ),
              ),
            ],
            hasMore: false,
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(opened, complete ? [next] : isEmpty);
        expect(
          session.advances,
          complete ? [(id: next, completed: true)] : isEmpty,
        );
        final panel = tester.widget<WatchLaterQueuePanel>(
          find.byType(WatchLaterQueuePanel),
        );
        expect(panel.queue.items, hasLength(2));
        expect(panel.onRemove, isNull);
        expect(panel.queue.withoutRemoved({next.value}), same(panel.queue));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(created, 1);
        expect(disposed, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (cached, comments, width) in [
    for (final cached in [false, true])
      for (final comments in [false, true])
        for (final width in [390.0, 1200.0]) (cached, comments, width),
  ]) {
    testWidgets(
      'reused video page default comments=$comments cached=$cached width=$width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const first = VideoId('BV1abc123456');
        const second = VideoId('BV1xyz123456');
        final next = Completer<VideoDetail>();
        final detail = await const _VideoRepository().loadDetail(
          second,
          cancellation: RequestCancellation(),
        );
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(_GuestAuthController.new),
            videoRepositoryProvider.overrideWithValue(const _VideoRepository()),
            videoExtrasRepositoryProvider.overrideWithValue(
              _ExtrasRepository(),
            ),
            videoDetailProvider(second).overrideWith((ref) => next.future),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          videoDetailProvider(second),
          (_, _) {},
        );
        addTearDown(subscription.close);
        if (cached) {
          next.complete(detail);
          await container.read(videoDetailProvider(second).future);
        }
        var id = first;
        String? cid;
        late StateSetter update;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: InputTestApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return VideoScreen(
                      key: const PageStorageKey('reused-video-slot'),
                      id: id,
                      defaultShowComments: comments,
                      initialCid: cid,
                      playerBuilder: (_, _, _) => const SizedBox(),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final screen = tester.state(find.byType(VideoScreen));
        expect(
          tester
              .widget<PagingTabStrip<int>>(find.byType(PagingTabStrip<int>))
              .value,
          comments ? 1 : 0,
        );
        await tester.tap(find.text(comments ? '简介' : '评论'));
        await tester.pumpAndSettle();
        update(() => cid = '2');
        await tester.pumpAndSettle();
        expect(
          find.text('暂无评论信息').hitTestable(),
          comments ? findsNothing : findsOneWidget,
        );
        update(() {
          id = second;
          cid = null;
        });
        await tester.pump();
        if (!cached) {
          expect(find.text('正在加载视频详情…'), findsOneWidget);
          next.complete(detail);
        }
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(VideoScreen)), same(screen));
        final strip = tester.widget<PagingTabStrip<int>>(
          find.byType(PagingTabStrip<int>),
        );
        expect(strip.value, comments ? 1 : 0);
        expect(strip.progress?.value, comments ? 1 : 0);
        expect(
          find.text('暂无评论信息').hitTestable(),
          comments ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'part drag reaches the real intro top and retains player at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var created = 0;
        var disposed = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_GuestAuthController.new),
              videoRepositoryProvider.overrideWithValue(
                _VideoRepository(
                  parts: [
                    for (var i = 0; i < 100; i++)
                      VideoPart(
                        cid: '${i + 1}',
                        page: i + 1,
                        title: '第 $i P',
                        duration: const Duration(minutes: 1),
                      ),
                  ],
                ),
              ),
              videoExtrasRepositoryProvider.overrideWithValue(
                _ExtrasRepository(related: _manyRelated()),
              ),
            ],
            child: InputTestApp(
              home: Scaffold(
                body: VideoScreen(
                  id: const VideoId('BV1abc123456'),
                  onOpenVideo: (_) {},
                  playerBuilder: (_, _, _) => _TrackedPlayer(
                    onCreate: () => created++,
                    onDispose: () => disposed++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (find.byTooltip('展开视频信息').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('展开视频信息'));
          await tester.pumpAndSettle();
        }
        final player = tester.state(find.byType(_TrackedPlayer));
        final outer = tester
            .state<ScrollableState>(_introScrollable())
            .position;
        final list = find
            .descendant(
              of: find.byType(VideoCollectionPanel),
              matching: find.byType(ListView),
            )
            .first;
        final inner = tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        outer.jumpTo(150);
        inner.jumpTo(35);
        await tester.pump();
        await tester.drag(list, const Offset(0, 450));
        await tester.pumpAndSettle();
        expect(outer.pixels, 0);
        expect(inner.pixels, 0);
        expect(tester.state(find.byType(_TrackedPlayer)), same(player));
        expect(created, 1);
        expect(disposed, 0);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  testWidgets(
    'charging video retains detail and player with an official access action',
    (tester) async {
      final opened = <Uri>[];
      var players = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_GuestAuthController.new),
            videoRepositoryProvider.overrideWithValue(
              const _VideoRepository(
                access: VideoAccess(
                  kind: VideoAccessKind.chargingExclusive,
                  canWatch: false,
                  canPreview: true,
                ),
              ),
            ),
            videoExtrasRepositoryProvider.overrideWithValue(
              _ExtrasRepository(),
            ),
            externalLinkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: VideoScreen(
                id: const VideoId('BV1abc123456'),
                playerBuilder: (_, _, _) {
                  players++;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试视频'), findsOneWidget);
      expect(find.text('充电专属'), findsOneWidget);
      expect(players, greaterThan(0));
      expect(opened, isEmpty);
      final action = find.byKey(const ValueKey('video-access-official'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(
        opened.single.toString(),
        'https://www.bilibili.com/video/BV1abc123456',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1100.0]) {
    testWidgets('video info swipes retain scroll and player at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var created = 0;
      var disposed = 0;
      final extras = _ExtrasRepository();
      await tester.pumpWidget(
        _relatedCardApp(
          _RelatedCardOperations(),
          onOpen: () {},
          extras: extras,
          playerBuilder: (_, _, _) => _TrackedPlayer(
            onCreate: () => created++,
            onDispose: () => disposed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pager = find.byKey(const ValueKey('video-info-swipe'));
      final player = tester.state(find.byType(_TrackedPlayer));
      final playerRect = tester.getRect(find.byType(_TrackedPlayer));
      final intro = tester.state<ScrollableState>(_introScrollable()).position;
      intro.jumpTo(intro.maxScrollExtent);
      await tester.pumpAndSettle();
      final offset = intro.pixels;
      final pageWidth = tester.getSize(pager).width;
      final drag = await tester.startGesture(tester.getCenter(pager));
      await drag.moveBy(Offset(-pageWidth * .3, 0));
      await tester.pump();
      await tester.pump();
      final strip = tester.widget<PagingTabStrip<int>>(
        find.byType(PagingTabStrip<int>),
      );
      expect(strip.value, 0);
      expect(strip.progress?.value, inExclusiveRange(0, 1));
      expect(extras.commentPages, isEmpty);
      expect(tester.getRect(find.byType(_TrackedPlayer)), playerRect);
      await drag.moveBy(Offset(-pageWidth * .35, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('暂无评论信息').hitTestable(), findsOneWidget);
      await tester.drag(pager, Offset(pageWidth * .7, 0));
      await tester.pumpAndSettle();
      expect(intro.pixels, offset);
      expect(tester.state(find.byType(_TrackedPlayer)), same(player));
      expect(created, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('video title and expanded description support drag copy', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var created = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
        ],
        child: InputTestApp(
          theme: BiliTheme.light().copyWith(platform: TargetPlatform.windows),
          home: Scaffold(
            body: VideoScreen(
              id: const VideoId('BV1abc123456'),
              playerBuilder: (_, _, _) =>
                  _TrackedPlayer(onCreate: () => created++, onDispose: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await selectAndCopyText(tester, find.text('测试视频')), '测试视频');
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(await selectAndCopyText(tester, find.text('测试简介')), '测试简介');
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('测试简介'), findsNothing);
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });

  setUpAll(() async {
    if (!const bool.fromEnvironment('VIDEO_TAGS_PREVIEW') &&
        const String.fromEnvironment('WATCH_LATER_PAGE_PREVIEW_CASE').isEmpty) {
      return;
    }
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'BiliIcons',
    )..addFont(rootBundle.load('assets/fonts/biliicon.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('queue toggles retain author state and player at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final authors = _QueueAuthors();
      final session = PlaybackSession(
        engine: CardFakeEngine(),
        repository: _UnusedPlaybackRepository(),
        progress: _UnusedProgressStore(),
        accountScope: () => 'user:7',
      );
      addTearDown(session.close);
      var playerCreates = 0;
      var playerBuilds = 0;
      var playerDisposes = 0;
      final queue = WatchLaterQueue(
        id: 'author-retention',
        scope: 'user:7',
        sessionEpoch: 0,
        items: [
          WatchLaterQueueItem(
            video: VideoSummary(
              id: const VideoId('BV1abc123456'),
              title: '队列视频',
              coverUrl: '',
              author: 'UP',
              duration: const Duration(minutes: 1),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackSessionProvider.overrideWithValue(session),
            authControllerProvider.overrideWith(_QueueSignedInAuth.new),
            videoRepositoryProvider.overrideWithValue(
              const _VideoRepository(authorMid: '42', includeCollection: false),
            ),
            videoAuthorRepositoryProvider.overrideWithValue(authors),
            videoExtrasRepositoryProvider.overrideWithValue(
              _ExtrasRepository(related: _manyRelated()),
            ),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: VideoScreen(
                id: const VideoId('BV1abc123456'),
                queue: queue,
                playerBuilder: (_, _, _) {
                  playerBuilds++;
                  return _TrackedPlayer(
                    onCreate: () => playerCreates++,
                    onDispose: () => playerDisposes++,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(authors.reads, 0, reason: 'Details load on first viewing');
      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      expect(authors.reads, 1);
      expect(find.text('7.1万粉丝 · 1.2万获赞'), findsOneWidget);
      expect(find.text('已关注'), findsOneWidget);
      final header = tester.element(find.byType(VideoAuthorHeader));
      final container = ProviderScope.containerOf(header);
      final provider = videoAuthorControllerProvider(const VideoAuthorId('42'));
      final controller = container.read(provider.notifier);
      final scroll = tester.state<ScrollableState>(_introScrollable()).position;
      expect(scroll.maxScrollExtent, greaterThan(50));
      scroll.jumpTo(50);
      await tester.pump();
      final offset = scroll.pixels;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('稍后再看'));
        await tester.pump();
        final builds = playerBuilds;
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(
            playerBuilds,
            builds,
            reason: 'Animation must not rebuild player',
          );
        }
        await tester.pumpAndSettle();
        expect(header.mounted, isTrue);
        expect(container.read(provider.notifier), same(controller));
        expect(authors.reads, 1);
        expect(find.text('已关注'), findsNothing);
        await tester.tap(find.text('稍后再看'));
        await tester.pumpAndSettle();
        expect(authors.reads, 1);
        expect(find.text('7.1万粉丝 · 1.2万获赞'), findsOneWidget);
        expect(find.text('已关注'), findsOneWidget);
        expect(
          tester.state<ScrollableState>(_introScrollable()).position.pixels,
          offset,
        );
      }
      expect(playerCreates, 1);
      expect(playerDisposes, 0);
      expect(authors.cancellation?.isCancelled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(authors.cancellation?.isCancelled, isTrue);
      expect(playerDisposes, 1);
    });
  }

  testWidgets('watch-later queue occupies sidebar and folds above intro', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final session = PlaybackSession(
      engine: CardFakeEngine(),
      repository: _UnusedPlaybackRepository(),
      progress: _UnusedProgressStore(),
      accountScope: () => 'user:7',
    );
    addTearDown(session.close);
    final queue = WatchLaterQueue(
      id: 'page-preview',
      scope: 'user:7',
      sessionEpoch: 0,
      items: [
        for (var i = 0; i < 58; i++)
          WatchLaterQueueItem(
            video: VideoSummary(
              id: i == 0
                  ? const VideoId('BV1abc123456')
                  : VideoId('BV${i.toString().padLeft(10, '0')}'),
              title: '第 ${i + 1} 条稍后再看视频，标题用于验证两行省略',
              coverUrl: '',
              author: '测试 UP 主',
              duration: const Duration(minutes: 4, seconds: 33),
            ),
            playCountText: '64.5万',
            danmakuCountText: '539',
          ),
      ],
    );
    for (final (name, dark, folded, width, scale) in [
      ('light-expanded', false, false, 1100.0, 1.0),
      ('light-folded', false, true, 1100.0, 1.0),
      ('dark-expanded', true, false, 1100.0, 1.0),
      ('narrow-large', false, false, 360.0, 2.0),
    ]) {
      const previewCase = String.fromEnvironment(
        'WATCH_LATER_PAGE_PREVIEW_CASE',
      );
      if (previewCase.isNotEmpty && previewCase != name) continue;
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackSessionProvider.overrideWithValue(session),
            authControllerProvider.overrideWith(_GuestAuthController.new),
            videoRepositoryProvider.overrideWithValue(_VideoRepository()),
            videoExtrasRepositoryProvider.overrideWithValue(
              _ExtrasRepository(),
            ),
          ],
          child: InputTestApp(
            theme: dark ? BiliTheme.dark() : BiliTheme.light(),
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('watch-later-page-preview'),
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: VideoScreen(
                    key: ValueKey('queue-page-$name'),
                    id: const VideoId('BV1abc123456'),
                    queue: queue,
                    playerBuilder: (_, _, _) =>
                        const ColoredBox(color: Colors.black),
                    onOpenQueueVideo: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('收起视频信息'),
        width >= 1000 ? findsOneWidget : findsNothing,
      );
      if (folded) {
        await tester.tap(find.text('稍后再看'));
        await tester.pumpAndSettle();
        expect(find.text('简介'), findsOneWidget);
      } else {
        expect(
          find.byKey(const ValueKey('watch-later-queue-list')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull, reason: name);
      if (previewCase == name) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('watch-later-page-preview')),
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final result = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return result;
        });
        final directory = Directory('build/watch-later-page-preview')
          ..createSync(recursive: true);
        File('${directory.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    }
  });
  testWidgets(
    'favorite queue retains removed watch-later videos and has no delete action',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final home = _QueueHomeRepository();
      final session = PlaybackSession(
        engine: CardFakeEngine(),
        repository: _UnusedPlaybackRepository(),
        progress: _UnusedProgressStore(),
        accountScope: () => home.accountScope,
        sessionEpoch: () => 0,
      );
      addTearDown(session.close);
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(home),
          playbackSessionProvider.overrideWithValue(session),
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
        ],
      );
      addTearDown(container.dispose);
      final queue = WatchLaterQueue(
        id: 'favorites',
        scope: 'user:7',
        sessionEpoch: 0,
        favoriteTitle: '测试收藏夹',
        items: [
          for (final entry in home.entries)
            WatchLaterQueueItem(
              entryId: entry.id,
              aid: entry.aid,
              video: VideoSummary(
                id: VideoId(entry.bvid!),
                title: entry.title,
                coverUrl: '',
                author: 'UP',
                duration: Duration.zero,
              ),
            ),
        ],
      );
      final opened = <VideoId>[];
      var created = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: InputTestApp(
            builder: AppNoticeHost.builder,
            home: Scaffold(
              body: VideoScreen(
                id: const VideoId('BV1abc123456'),
                queue: queue,
                onOpenQueueVideo: opened.add,
                playerBuilder: (_, _, _) =>
                    _TrackedPlayer(onCreate: () => created++, onDispose: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试收藏夹'), findsOneWidget);
      expect(find.text('删除'), findsNothing);
      final removal = container
          .read(watchLaterRemovalProvider('user:7').notifier)
          .remove(home.entries[1]);
      home.writes.single.complete();
      await removal;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('watch-later-queue-BV2abc123456')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('watch-later-queue-BV2abc123456')),
      );
      await tester.pumpAndSettle();
      expect(opened, [const VideoId('BV2abc123456')]);
      await tester.tap(find.text('测试收藏夹'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('watch-later-queue-list')),
        findsNothing,
      );
      expect(created, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in ['success', 'failure', 'uncertain', 'session-change']) {
    testWidgets(
      'watch-later queue deletion handles $outcome without changing player',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final home = _QueueHomeRepository();
        var epoch = 0;
        final session = PlaybackSession(
          engine: CardFakeEngine(),
          repository: _UnusedPlaybackRepository(),
          progress: _UnusedProgressStore(),
          accountScope: () => home.accountScope,
          sessionEpoch: () => epoch,
        );
        addTearDown(session.close);
        final container = ProviderContainer(
          overrides: [
            homeRepositoryProvider.overrideWithValue(home),
            playbackSessionProvider.overrideWithValue(session),
            sessionEpochProvider.overrideWithValue(() => epoch),
            authControllerProvider.overrideWith(_GuestAuthController.new),
            videoRepositoryProvider.overrideWithValue(_VideoRepository()),
            videoExtrasRepositoryProvider.overrideWithValue(
              _ExtrasRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);
        final queries = [
          for (final section in HomeChannel.watchLater.sections)
            (
              channel: HomeChannel.watchLater,
              section: section,
              scope: 'user:7',
              folderId: null,
            ),
        ];
        for (final query in queries) {
          container.listen(homeControllerProvider(query), (_, _) {});
          await container
              .read(homeControllerProvider(query).notifier)
              .refresh();
        }
        final queue = WatchLaterQueue(
          id: 'remove-test',
          scope: 'user:7',
          sessionEpoch: 0,
          items: [
            for (final entry in home.entries)
              WatchLaterQueueItem(
                entryId: entry.id,
                aid: entry.aid,
                video: VideoSummary(
                  id: VideoId(entry.bvid ?? ''),
                  title: entry.title,
                  coverUrl: '',
                  author: '测试 UP',
                  duration: const Duration(minutes: 1),
                ),
              ),
          ],
        );
        final opened = <VideoId>[];
        var created = 0, disposed = 0;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: InputTestApp(
              builder: AppNoticeHost.builder,
              home: Scaffold(
                body: VideoScreen(
                  id: const VideoId('BV1abc123456'),
                  queue: queue,
                  onOpenQueueVideo: opened.add,
                  playerBuilder: (_, _, _) => _TrackedPlayer(
                    onCreate: () => created++,
                    onDispose: () => disposed++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final player = tester.state(find.byType(_TrackedPlayer));
        final currentDelete = find.byKey(
          const ValueKey('watch-later-queue-remove-BV1abc123456'),
        );
        final targetDelete = find.byKey(
          const ValueKey('watch-later-queue-remove-BV2abc123456'),
        );
        final targetRow = find.byKey(
          const ValueKey('watch-later-queue-BV2abc123456'),
        );
        expect(currentDelete, findsNothing);
        await tester.tap(targetDelete);
        await tester.pump();
        expect(home.writes, hasLength(1));
        expect(home.removed.single.id, 'original-entry-2');
        expect(home.removed.single.aid, '9007199254740993');
        expect(tester.widget<TextButton>(targetDelete).onPressed, isNull);
        expect(targetRow, findsOneWidget);
        expect(opened, isEmpty);
        switch (outcome) {
          case 'success':
            home.writes.single.complete();
          case 'failure':
            home.writes.single.completeError(
              const AppFailure(AppFailureKind.network, '删除失败'),
            );
          case 'uncertain':
            home.writes.single.completeError(const UnknownWriteOutcome());
          case 'session-change':
            epoch++;
            container.invalidate(watchLaterRemovalProvider);
            expect(home.tokens.single.isCancelled, isTrue);
            home.writes.single.complete();
        }
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(_TrackedPlayer)), same(player));
        expect(created, 1);
        expect(disposed, 0);
        expect(opened, isEmpty);
        for (final query in queries) {
          expect(
            container
                .read(homeControllerProvider(query))
                .items
                .requireValue
                .length,
            outcome == 'success' ? 2 : 3,
          );
        }
        if (outcome == 'success') {
          expect(targetRow, findsNothing);
          expect(find.text('1/2'), findsOneWidget);
          expect(find.text('已从稍后再看删除'), findsOneWidget);
          // Selection uses the latest filtered queue, even before the route changes.
          final panel = tester.widget<WatchLaterQueuePanel>(
            find.byType(WatchLaterQueuePanel),
          );
          panel.onSelect(const VideoId('BV2abc123456'));
          expect(opened, isEmpty);
          await tester.tap(
            find.byKey(const ValueKey('watch-later-queue-BV3abc123456')),
          );
          expect(opened, [const VideoId('BV3abc123456')]);
        } else if (outcome != 'session-change') {
          expect(targetRow, findsOneWidget);
          expect(
            find.text(outcome == 'failure' ? '删除失败' : '删除结果暂时无法确认，请刷新稍后再看列表核对'),
            findsOneWidget,
          );
          if (outcome == 'uncertain') {
            await tester.tap(targetDelete);
            await tester.pumpAndSettle();
            expect(home.writes, hasLength(1));
          }
        } else {
          expect(find.text('已从稍后再看删除'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final width in [360.0, 1100.0]) {
    testWidgets(
      'description and tags default to collapsed and toggle together at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const tag = 'Flutter & Dart/中文+测试';
        String? searched;
        var created = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_GuestAuthController.new),
              videoRepositoryProvider.overrideWithValue(_VideoRepository()),
              videoExtrasRepositoryProvider.overrideWithValue(
                _ExtrasRepository(tags: const [tag, '编程', '教程', '跨平台开发']),
              ),
            ],
            child: InputTestApp(
              theme: BiliTheme.light(),
              builder: (context, child) => RepaintBoundary(
                key: const ValueKey('video-tags-preview'),
                child: child ?? const SizedBox.shrink(),
              ),
              home: Scaffold(
                body: VideoScreen(
                  id: const VideoId('BV1abc123456'),
                  onSearchTag: (value) => searched = value,
                  playerBuilder: (_, _, _) => _TrackedPlayer(
                    onCreate: () => created++,
                    onDispose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('测试简介'), findsNothing);
        expect(find.text('标签'), findsNothing);
        expect(find.widgetWithText(ActionChip, tag), findsNothing);
        expect(find.text('展开'), findsOneWidget);
        await tester.tap(find.text('展开'));
        await tester.pumpAndSettle();
        expect(find.text('测试简介'), findsOneWidget);
        expect(find.text('标签'), findsOneWidget);
        await tester.ensureVisible(find.widgetWithText(ActionChip, tag));
        await tester.tap(find.widgetWithText(ActionChip, tag));
        expect(searched, tag);
        await _tagsSnapshot(tester, width >= 1000 ? 'wide' : 'narrow');
        await tester.ensureVisible(find.text('收起'));
        await tester.tap(find.text('收起'));
        await tester.pumpAndSettle();
        expect(find.text('测试简介'), findsNothing);
        expect(find.text('标签'), findsNothing);
        expect(find.widgetWithText(ActionChip, tag), findsNothing);
        tester.view.physicalSize = Size(width >= 1000 ? 360 : 1100, 800);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('收起视频信息'),
          width >= 1000 ? findsNothing : findsOneWidget,
        );
        expect(find.text('测试简介'), findsNothing);
        expect(find.text('标签'), findsNothing);
        await tester.tap(find.text('展开'));
        await tester.pumpAndSettle();
        expect(find.text('测试简介'), findsOneWidget);
        expect(find.text('标签'), findsOneWidget);
        expect(created, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [360.0, 1100.0]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
        'description transition at $width reducedMotion=$reducedMotion',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const id = VideoId('BV1abc123456');
          final container = ProviderContainer(
            overrides: [
              authControllerProvider.overrideWith(_GuestAuthController.new),
              videoRepositoryProvider.overrideWithValue(_VideoRepository()),
              videoExtrasRepositoryProvider.overrideWithValue(
                _ExtrasRepository(tags: const ['Flutter']),
              ),
            ],
          );
          addTearDown(container.dispose);
          var created = 0;
          var playerBuilds = 0;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: InputTestApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reducedMotion),
                  child: child!,
                ),
                home: Scaffold(
                  body: VideoScreen(
                    id: id,
                    playerBuilder: (_, _, _) {
                      playerBuilds++;
                      return _TrackedPlayer(
                        onCreate: () => created++,
                        onDispose: () {},
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(container.exists(videoTagsProvider(id)), isFalse);
          final description = find.text('测试简介');
          final transition = find
              .ancestor(of: description, matching: find.byType(SizeTransition))
              .first;

          await tester.tap(find.text('展开'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 55));
          final builds = playerBuilds;
          final openingHeight = tester.getSize(transition).height;
          await tester.pumpAndSettle();
          final expandedHeight = tester.getSize(transition).height;
          expect(openingHeight, greaterThan(0));
          expect(
            openingHeight,
            reducedMotion ? expandedHeight : lessThan(expandedHeight),
          );
          expect(playerBuilds, builds);
          expect(find.widgetWithText(ActionChip, 'Flutter'), findsOneWidget);

          await tester.tap(find.text('收起'));
          await tester.pump();
          if (!reducedMotion) {
            await tester.pump(const Duration(milliseconds: 55));
            expect(tester.getSize(transition).height, greaterThan(0));
            expect(tester.getSize(transition).height, lessThan(expandedHeight));
            final pointer = tester.widget<IgnorePointer>(
              find
                  .ancestor(
                    of: description,
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            );
            expect(pointer.ignoring, isTrue);
            expect(container.exists(videoTagsProvider(id)), isTrue);

            // Reverse an unfinished collapse without duplicating content.
            await tester.tap(find.text('展开'));
            await tester.pump();
            final reversingHeight = tester.getSize(transition).height;
            await tester.pump(const Duration(milliseconds: 40));
            expect(
              tester.getSize(transition).height,
              greaterThan(reversingHeight),
            );
            expect(description, findsOneWidget);
            await tester.pumpAndSettle();
            await tester.tap(find.text('收起'));
            await tester.pump();
          } else {
            expect(description, findsNothing);
          }
          await tester.pumpAndSettle();
          expect(description, findsNothing);
          expect(find.widgetWithText(ActionChip, 'Flutter'), findsNothing);
          expect(container.exists(videoTagsProvider(id)), isFalse);
          expect(created, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final initialSize in [const Size(480, 660), const Size(1100, 800)]) {
    testWidgets(
      'video info defaults to expanded at ${initialSize.width} and retains user choice',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = initialSize;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var created = 0;
        var disposed = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_GuestAuthController.new),
              videoRepositoryProvider.overrideWithValue(_VideoRepository()),
              videoExtrasRepositoryProvider.overrideWithValue(
                _ExtrasRepository(),
              ),
            ],
            child: InputTestApp(
              home: Scaffold(
                body: VideoScreen(
                  id: const VideoId('BV1abc123456'),
                  playerBuilder: (_, _, _) => _TrackedPlayer(
                    onCreate: () => created++,
                    onDispose: () => disposed++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('简介'), findsOneWidget);
        expect(find.text('评论'), findsOneWidget);
        expect(
          find.byTooltip('收起视频信息'),
          initialSize.width >= 1000 ? findsOneWidget : findsNothing,
        );
        expect(
          tester.getSize(find.byType(_TrackedPlayer)).height,
          initialSize.width >= 1000
              ? initialSize.height
              : initialSize.width * 9 / 16,
        );
        await tester.tap(find.text('评论'));
        await tester.pumpAndSettle();
        for (final width in [699.0, 700.0, 999.0, 1000.0, 1100.0, 480.0]) {
          tester.view.physicalSize = Size(width, 660);
          await tester.pumpAndSettle();
          expect(find.text('暂无评论信息'), findsOneWidget);
          expect(
            find.byTooltip('收起视频信息'),
            width >= 1000 ? findsOneWidget : findsNothing,
          );
          expect(
            tester.getSize(find.byType(_TrackedPlayer)).height,
            width >= 1000 ? 660 : width * 9 / 16,
          );
        }
        tester.view.physicalSize = const Size(1000, 660);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('收起视频信息'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(_TrackedPlayer)),
          const Size(1000, 660),
        );
        for (final width in [1100.0, 480.0]) {
          tester.view.physicalSize = Size(width, 660);
          await tester.pumpAndSettle();
          expect(find.text('评论'), findsNothing);
          expect(
            find.byTooltip('展开视频信息'),
            width >= 1000 ? findsOneWidget : findsNothing,
          );
          expect(tester.getSize(find.byType(_TrackedPlayer)), Size(width, 660));
        }
        final commands = tester.widget<PlaybackPageCommands>(
          find.byType(PlaybackPageCommands),
        );
        commands.toggleInfo();
        await tester.pumpAndSettle();
        expect(find.text('暂无评论信息'), findsOneWidget);
        expect(find.byTooltip('收起视频信息'), findsNothing);
        expect(tester.getSize(find.byType(_TrackedPlayer)).height, 270);
        expect(created, 1);
        expect(disposed, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'long collection stays bounded and current nested parts stay in one card',
    (tester) async {
      final base = await _VideoRepository().loadDetail(
        const VideoId('BV1abc123456'),
        cancellation: RequestCancellation(),
      );
      VideoPart? selected;
      final video = VideoDetail(
        summary: base.summary,
        description: base.description,
        parts: base.parts,
        collection: VideoCollection(
          id: '1',
          title: '长合集',
          playCount: 12340000,
          entries: List.generate(
            40,
            (index) => VideoCollectionEntry(
              id: index == 9
                  ? base.summary.id
                  : VideoId('BV${index.toString().padLeft(10, '0')}'),
              title: '合集第${index + 1}集',
              parts: const [],
              duration: const Duration(seconds: 326),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_GuestAuthController.new),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 356,
                  child: VideoCollectionPanel(
                    video: video,
                    selected: base.parts.first,
                    onSelectPart: (part) => selected = part,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('(10/40)'), findsOneWidget);
      expect(find.text('1234.0万播放'), findsOneWidget);
      expect(find.text('视频选集 · 2 P'), findsNothing);
      final tile = find
          .ancestor(of: find.text('合集第10集'), matching: find.byType(Column))
          .first;
      await tester.tap(
        find.descendant(of: tile, matching: find.byTooltip('展开分 P')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('P2 第二集'));
      await tester.tap(find.text('P2 第二集'));
      expect(selected?.cid, '2');
      expect(
        tester.getSize(find.byType(VideoCollectionPanel)).height,
        lessThan(390),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('video subtabs load lazily and retain the player', (
    tester,
  ) async {
    final extras = _ExtrasRepository();
    var created = 0;
    VideoSummary? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(extras),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: VideoScreen(
              id: const VideoId('BV1abc123456'),
              onOpenVideo: (video) => opened = video,
              playerBuilder: (_, _, _) =>
                  _TrackedPlayer(onCreate: () => created++, onDispose: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(extras.relatedRequests, 1);
    expect(extras.commentPages, isEmpty);
    await tester.ensureVisible(find.text('评论'));
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    expect(find.text('暂无评论信息'), findsOneWidget);
    expect(find.text('选集'), findsNothing);
    await tester.tap(find.text('简介').first);
    await tester.pumpAndSettle();
    expect(find.text('推荐'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('相关推荐视频'),
      150,
      scrollable: _introScrollable(),
    );
    expect(find.text('相关推荐视频'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video-info-separator-intro')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video-info-separator-collection')),
      findsOneWidget,
    );
    expect(extras.relatedRequests, 1);
    await tester.ensureVisible(find.text('相关推荐视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相关推荐视频'));
    expect(opened?.id.value, 'BV1xyz123456');
    expect(created, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(VideoScreen)),
    );
    container.invalidate(videoDetailProvider(const VideoId('BV1abc123456')));
    await tester.pumpAndSettle();
    expect(created, 1);
    await tester.ensureVisible(find.text('视频选集 · 2 P'));
    await tester.tap(find.text('视频选集 · 2 P'));
    await tester.pumpAndSettle();
    expect(find.text('第二集'), findsNothing);
    expect(find.text('相关推荐视频'), findsOneWidget);
    await tester.ensureVisible(find.text('评论'));
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    expect(find.text('暂无评论信息'), findsOneWidget);
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(1100, 800), const Size(480, 800)]) {
    testWidgets('related videos build lazily and retain player at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = _RelatedCardOperations();
      addTearDown(() => unawaited(operations.previews.close()));
      var created = 0;
      var disposed = 0;
      await tester.pumpWidget(
        _relatedCardApp(
          operations,
          extras: _ExtrasRepository(related: _manyRelated()),
          onOpen: () {},
          playerBuilder: (_, _, _) => _TrackedPlayer(
            onCreate: () => created++,
            onDispose: () => disposed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VideoCardCover).evaluate().length, lessThan(20));
      expect(find.text('推荐视频 39'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('推荐视频 39'),
        500,
        scrollable: _introScrollable(),
      );
      expect(find.text('推荐视频 0'), findsNothing);
      expect(find.byType(VideoCardCover).evaluate().length, lessThan(20));
      final position = tester
          .state<ScrollableState>(_introScrollable())
          .position;
      final offset = position.pixels;
      await tester.ensureVisible(find.text('评论'));
      await tester.tap(find.text('评论'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简介'));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(offset, .01));
      expect(find.text('推荐视频 39'), findsOneWidget);
      expect(created, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wheel scrolling cancels preview and idle hover resumes it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operations = _RelatedCardOperations();
    addTearDown(() => unawaited(operations.previews.close()));
    await tester.pumpWidget(
      _relatedCardApp(
        operations,
        extras: _ExtrasRepository(related: _manyRelated()),
        smoothScrolling: true,
        onOpen: () {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('推荐视频 0'),
      100,
      scrollable: _introScrollable(),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    addTearDown(mouse.removePointer);
    final location = tester.getCenter(find.text('推荐视频 0'));
    await mouse.moveTo(location);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pump();
    expect(operations.reads, 1);
    final engine = operations.engines.single;
    final token = operations.token;
    final position = tester.state<ScrollableState>(_introScrollable()).position;
    final start = position.pixels;
    for (var frame = 0; frame < 192; frame++) {
      if (frame % 6 == 0) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: location,
            scrollDelta: const Offset(0, 25),
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(operations.reads, 1, reason: 'No new preview while rolling');
      for (final cover in tester.widgetList<AnimatedScale>(
        find.byKey(const ValueKey('video-card-cover-scale')),
      )) {
        expect(cover.scale, 1, reason: 'No hover scale while rolling');
      }
    }
    expect(position.pixels - start, greaterThan(700));
    expect(token?.isCancelled, true);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(engine.disposals, 1);
    await tester.pumpAndSettle();
    expect(position.isScrollingNotifier.value, false);
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pump();
    expect(operations.reads, 2);
    expect(operations.engines, hasLength(2));
    expect(find.byKey(const ValueKey('video-card-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final pendingOpen in [false, true]) {
    testWidgets(
      'related eviction releases ${pendingOpen ? 'pending' : 'playing'} preview once',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final operations = _RelatedCardOperations(
          opening: pendingOpen ? Completer<void>() : null,
        );
        addTearDown(() => unawaited(operations.previews.close()));
        await tester.pumpWidget(
          _relatedCardApp(
            operations,
            extras: _ExtrasRepository(related: _manyRelated()),
            onOpen: () {},
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('推荐视频 0'),
          100,
          scrollable: _introScrollable(),
        );
        final first = find.byWidgetPredicate(
          (widget) =>
              widget is VideoCardCover &&
              widget.video.id == const VideoId('BV0000000000'),
        );
        final state = tester.state<State<VideoCardCover>>(first);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(100, 100));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('推荐视频 0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 210));
        await tester.pump();
        final token = operations.token;
        final engine = operations.engines.single;
        tester.state<ScrollableState>(_introScrollable()).position.jumpTo(3000);
        await tester.pump();
        await mouse.moveTo(const Offset(100, 100));
        await tester.pump(const Duration(milliseconds: 150));
        expect(state.mounted, false);
        expect(token?.isCancelled, true);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(engine.disposals, 1);
        operations.opening?.complete();
        await tester.pump(const Duration(milliseconds: 400));
        expect(engine.disposals, 1);
        expect(operations.reads, 1);
        expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [480.0, 1100.0]) {
    testWidgets(
      'related author opens space and highlights only its name at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final operations = _RelatedCardOperations();
        addTearDown(() => unawaited(operations.previews.close()));
        var opened = 0;
        var created = 0;
        final openedUsers = <UserId>[];
        await tester.pumpWidget(
          _relatedCardApp(
            operations,
            extras: _ExtrasRepository(
              related: const [
                VideoSummary(
                  id: VideoId('BV1xyz123456'),
                  title: '相关推荐视频',
                  coverUrl: '',
                  author: '推荐UP',
                  authorId: UserId('123'),
                  duration: Duration(minutes: 2),
                ),
              ],
            ),
            onOpen: () => opened++,
            onOpenUser: openedUsers.add,
            playerBuilder: (_, _, _) =>
                _TrackedPlayer(onCreate: () => created++, onDispose: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final author = find.text('推荐UP');
        await tester.ensureVisible(author);
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(author));
        final originalColor = tester.widget<Text>(author).style?.color;
        final authorLink = find
            .ancestor(of: author, matching: find.byType(InkWell))
            .first;
        expect(tester.getRect(authorLink), tester.getRect(author));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 0));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(author));
        await tester.pump();
        expect(
          tester.widget<Text>(author).style?.color,
          theme.colorScheme.primary,
        );
        expect(
          tester.widget<Text>(find.text('相关推荐视频')).style?.color,
          theme.textTheme.titleSmall?.color,
        );
        expect(
          tester.widget<InkWell>(authorLink).hoverColor,
          Colors.transparent,
        );
        await tester.tap(author);
        expect(openedUsers, [const UserId('123')]);
        expect(opened, 0);

        final badge = find
            .ancestor(of: author, matching: find.byType(Row))
            .first;
        final icon = find
            .descendant(of: badge, matching: find.byType(Icon))
            .first;
        await mouse.moveTo(tester.getCenter(icon));
        await tester.pump();
        expect(tester.widget<Text>(author).style?.color, originalColor);
        await tester.tap(icon);
        expect(opened, 1);
        expect(openedUsers, [const UserId('123')]);

        await mouse.moveTo(const Offset(0, 0));
        Focus.of(tester.element(author)).requestFocus();
        await tester.pump();
        expect(
          tester.widget<Text>(author).style?.color,
          theme.colorScheme.primary,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(openedUsers, [const UserId('123'), const UserId('123')]);
        expect(opened, 1);
        await tester.tap(find.text('相关推荐视频'));
        expect(opened, 2);
        expect(created, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (authorId, provideNavigation) in [
    (null, true),
    (const UserId('0'), true),
    (const UserId('invalid'), true),
    (const UserId('123'), false),
  ]) {
    testWidgets(
      'related author without a usable space link ($authorId, $provideNavigation)',
      (tester) async {
        final operations = _RelatedCardOperations();
        addTearDown(() => unawaited(operations.previews.close()));
        var opened = 0;
        final openedUsers = <UserId>[];
        await tester.pumpWidget(
          _relatedCardApp(
            operations,
            extras: _ExtrasRepository(
              related: [
                VideoSummary(
                  id: const VideoId('BV1xyz123456'),
                  title: '相关推荐视频',
                  coverUrl: '',
                  author: '推荐UP',
                  authorId: authorId,
                  duration: const Duration(minutes: 2),
                ),
              ],
            ),
            onOpen: () => opened++,
            onOpenUser: provideNavigation ? openedUsers.add : null,
          ),
        );
        await tester.pumpAndSettle();
        final author = find.text('推荐UP');
        await tester.ensureVisible(author);
        await tester.pumpAndSettle();
        final originalColor = tester.widget<Text>(author).style?.color;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 0));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(author));
        await tester.pump();
        expect(tester.widget<Text>(author).style?.color, originalColor);
        await tester.tap(author);
        expect(openedUsers, isEmpty);
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('related title tooltip only shows truncated names on hover', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operations = _RelatedCardOperations();
    addTearDown(() => unawaited(operations.previews.close()));
    const videos = [
      VideoSummary(
        id: VideoId('BV0000000000'),
        title:
            '相关推荐视频的完整长标题需要在鼠标悬停时显示，'
            '超出两行的这部分内容也必须完整展示，不能继续被省略',
        coverUrl: '',
        author: '推荐UP',
        duration: Duration(minutes: 2),
      ),
      VideoSummary(
        id: VideoId('BV0000000001'),
        title: '短标题',
        coverUrl: '',
        author: '推荐UP',
        duration: Duration(minutes: 2),
      ),
    ];
    var opened = 0;
    await tester.pumpWidget(
      _relatedCardApp(
        operations,
        extras: _ExtrasRepository(related: videos),
        onOpen: () => opened++,
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    addTearDown(mouse.removePointer);
    for (final video in videos) {
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.maxLines == 2 &&
            widget.data == video.title,
      );
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      final overflowing = video == videos.first;
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, overflowing);
      expect(
        find.byTooltip(video.title),
        overflowing ? findsOneWidget : findsNothing,
      );
      await mouse.moveTo(tester.getCenter(title));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == video.title,
        ),
        overflowing ? findsNWidgets(2) : findsOneWidget,
      );
      await tester.tap(title);
      await mouse.moveTo(const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(opened, 2);
  });

  testWidgets(
    'related card previews from title hover and adds without opening',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = _RelatedCardOperations();
      addTearDown(() => unawaited(operations.previews.close()));
      final notices = <String>[];
      var opened = 0;
      var created = 0;
      var disposed = 0;
      await tester.pumpWidget(
        _relatedCardApp(
          operations,
          onNotice: notices.add,
          onOpen: () => opened++,
          playerBuilder: (_, _, _) => _TrackedPlayer(
            onCreate: () => created++,
            onDispose: () => disposed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('相关推荐视频'));
      final cover = find.byType(VideoCardCover);
      final card = find
          .ancestor(of: cover, matching: find.byType(InkWell))
          .first;
      final counts = find.descendant(of: card, matching: find.byType(Wrap));
      expect(
        tester.getRect(counts).bottom,
        closeTo(tester.getRect(cover).bottom, .01),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('相关推荐视频')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(operations.reads, 0);
      expect(find.byTooltip('添加稍后再看'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('video-card-cover-scale')),
            )
            .scale,
        1.05,
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(operations.reads, 1);
      expect(operations.previewId, const VideoId('BV1xyz123456'));
      expect(operations.previewCid, '42');
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );
      final engine = operations.engines.single;
      expect(engine.options?.play, true);
      expect(engine.options?.volume, 0);
      engine.advance(const Duration(seconds: 8));
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('video-card-preview-progress')),
            )
            .value,
        .4,
      );
      await mouse.moveTo(tester.getCenter(find.byType(VideoCardCover)));
      await tester.pump(const Duration(milliseconds: 250));
      expect(operations.reads, 1);
      await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
      await tester.pump();
      expect(operations.writtenIds, [const VideoId('BV1xyz123456')]);
      expect(opened, 0);
      expect(notices, ['已加入稍后再看']);
      expect(find.byTooltip('已加入稍后再看'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
      expect(operations.writtenIds, hasLength(1));
      await mouse.moveTo(const Offset(100, 100));
      await tester.pump();
      expect(operations.token?.isCancelled, true);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(engine.disposals, 1);
      expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
      await tester.tap(find.text('相关推荐视频'));
      expect(opened, 1);
      expect(created, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('related card keyboard add and hidden sidebar cancel previews', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operations = _RelatedCardOperations();
    addTearDown(() => unawaited(operations.previews.close()));
    var opened = 0;
    await tester.pumpWidget(
      _relatedCardApp(operations, onOpen: () => opened++),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('相关推荐视频'));
    for (
      var i = 0;
      i < 20 && find.byTooltip('添加稍后再看').evaluate().isEmpty;
      i++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(find.byTooltip('添加稍后再看'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(operations.writtenIds, [const VideoId('BV1xyz123456')]);
    expect(operations.reads, 0);
    expect(opened, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    addTearDown(mouse.removePointer);
    Future<void> hoverRelated() async {
      await mouse.moveTo(const Offset(100, 100));
      await mouse.moveTo(tester.getCenter(find.text('相关推荐视频')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      await tester.pump();
      expect(find.byKey(const ValueKey('video-card-preview')), findsOneWidget);
    }

    await hoverRelated();
    await tester.tap(find.text('评论'));
    await tester.pump();
    expect(operations.token?.isCancelled, true);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(operations.engines.last.disposals, 1);
    await tester.tap(find.text('简介'));
    await tester.pumpAndSettle();
    await hoverRelated();
    await tester.tap(find.byTooltip('收起视频信息'));
    await tester.pump();
    expect(operations.token?.isCancelled, true);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(operations.engines.last.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection parts navigate with cid and collapse independently', (
    tester,
  ) async {
    VideoId? openedId;
    String? openedCid;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: VideoScreen(
              id: const VideoId('BV1abc123456'),
              onOpenVideoPart: (id, cid) {
                openedId = id;
                openedCid = cid;
              },
              playerBuilder: (_, _, _) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('展开分 P'));
    await tester.tap(find.byTooltip('展开分 P'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('P2 合集第二 P'));
    await tester.tap(find.text('P2 合集第二 P'));
    expect(openedId, const VideoId('BV1xyz123456'));
    expect(openedCid, '44');
    await tester.ensureVisible(find.text('测试合集'));
    await tester.tap(find.text('测试合集'));
    await tester.pumpAndSettle();
    expect(find.text('P2 合集第二 P'), findsNothing);
    expect(find.text('第二集'), findsOneWidget);
    await tester.ensureVisible(find.text('测试合集'));
    await tester.tap(find.text('测试合集'));
    await tester.pumpAndSettle();
    expect(find.text('P2 合集第二 P'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selecting a part sends that part to the player slot', (
    tester,
  ) async {
    VideoPart? selectedPart;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: VideoScreen(
              id: const VideoId('BV1abc123456'),
              onPartChanged: (part) => selectedPart = part,
              playerBuilder: (context, detail, part) =>
                  Center(child: Text('播放 ${part.title}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('播放 第一集'), findsOneWidget);
    await tester.ensureVisible(find.text('第二集'));
    await tester.tap(find.text('第二集'));
    await tester.pumpAndSettle();
    expect(find.text('播放 第二集'), findsOneWidget);
    expect(selectedPart?.title, '第二集');
  });

  testWidgets('retained fullscreen commands use the latest selected part', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: VideoScreen(
              id: const VideoId('BV1abc123456'),
              playerBuilder: (_, _, part) => Text('播放 ${part.title}'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final commands = tester.widget<PlaybackPageCommands>(
      find.byType(PlaybackPageCommands),
    );
    commands.nextPart();
    await tester.pumpAndSettle();
    expect(find.text('播放 第二集'), findsOneWidget);
    commands.previousPart();
    await tester.pumpAndSettle();
    expect(find.text('播放 第一集'), findsOneWidget);
    commands.nextPart();
    await tester.pumpAndSettle();
    expect(find.text('播放 第二集'), findsOneWidget);
  });

  testWidgets('changing between wide and narrow layouts retains player state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var created = 0;
    var disposed = 0;
    var infoCreated = 0;
    var infoDisposed = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_GuestAuthController.new),
          videoRepositoryProvider.overrideWithValue(_VideoRepository()),
          videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
        ],
        child: InputTestApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: VideoScreen(
              id: const VideoId('BV1abc123456'),
              menuBuilder: (_, _, _) => SizedBox(
                width: 24,
                height: 24,
                child: _TrackedPlayer(
                  onCreate: () => infoCreated++,
                  onDispose: () => infoDisposed++,
                ),
              ),
              playerBuilder: (context, detail, part) => _TrackedPlayer(
                onCreate: () => created++,
                onDispose: () => disposed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(created, 1);
    final infoElement = tester.element(find.byType(Material).first);
    await tester.tap(find.byTooltip('收起视频信息'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(disposed, 0);
    await tester.tap(find.byTooltip('展开视频信息'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(disposed, 0);
    expect(infoElement.mounted, isTrue);
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(disposed, 0);
    expect(infoCreated, 1);
    expect(infoDisposed, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _GuestAuthController extends AuthController {
  @override
  AuthState build() => const AuthState();
}

final class _QueueSignedInAuth extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, mid: '7');
}

final class _QueueAuthors extends Fake implements VideoAuthorRepository {
  int reads = 0;
  RequestCancellation? cancellation;
  @override
  String get accountScope => 'user:7';
  @override
  int get sessionEpoch => 0;
  @override
  Future<VideoAuthor> load(VideoAuthorId id, RequestCancellation token) async {
    reads++;
    cancellation = token;
    return const VideoAuthor(
      following: true,
      followerCount: 70700,
      likeCount: 12345,
    );
  }
}

Widget _relatedCardApp(
  _RelatedCardOperations operations, {
  required VoidCallback onOpen,
  ValueChanged<UserId>? onOpenUser,
  ValueChanged<String>? onNotice,
  VideoPlayerBuilder? playerBuilder,
  VideoExtrasRepository? extras,
  bool smoothScrolling = false,
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(_GuestAuthController.new),
    videoRepositoryProvider.overrideWithValue(_VideoRepository()),
    videoExtrasRepositoryProvider.overrideWithValue(
      extras ?? _ExtrasRepository(),
    ),
  ],
  child: InputTestApp(
    theme: smoothScrolling
        ? BiliTheme.light().copyWith(platform: TargetPlatform.windows)
        : null,
    home: Scaffold(
      body: VideoCardInteractionScope(
        interactions: operations,
        onNotice: (_, message) => onNotice?.call(message),
        child: ScrollConfiguration(
          behavior: smoothScrolling
              ? const SmoothScrollBehavior()
              : const MaterialScrollBehavior(),
          child: VideoScreen(
            id: const VideoId('BV1abc123456'),
            onOpenVideo: (_) => onOpen(),
            onOpenUser: onOpenUser,
            playerBuilder: playerBuilder ?? (_, _, _) => const SizedBox(),
          ),
        ),
      ),
    ),
  ),
);

final class _RelatedCardOperations implements VideoCardOperations {
  _RelatedCardOperations({this.opening});
  final Completer<void>? opening;
  final engines = <CardFakeEngine>[];
  late final previews = VideoCardPreviewPlayback(
    createEngine: () {
      final engine = CardFakeEngine()..opening = opening;
      engines.add(engine);
      return engine;
    },
  );
  int reads = 0;
  VideoId? previewId;
  String? previewCid;
  RequestCancellation? token;
  final writtenIds = <VideoId>[];

  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) {
    reads++;
    previewId = id;
    previewCid = cid;
    token = cancellation;
    return previews.start(cardPreviewMedia(), cancellation);
  }

  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async {
    writtenIds.add(id);
    return WatchLaterResult.added;
  }

  @override
  bool isAdded(VideoId id) => writtenIds.contains(id);
  @override
  bool isUncertain(VideoId id) => false;
}

final class _ProfilePagingRepository extends Fake implements ProfileRepository {
  _ProfilePagingRepository({this.expectedFolderId});
  final String? expectedFolderId;
  @override
  String get accountScope => 'user:7';
  @override
  int get sessionEpoch => 0;
  final pending = Completer<ProfilePage>();
  int reads = 0;
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    required RequestCancellation cancellation,
  }) {
    expect(id, const UserId('7'));
    expect(
      section,
      expectedFolderId == null ? ProfileSection.videos : ProfileSection.folders,
    );
    expect(folderId, expectedFolderId);
    expect(page, 2);
    reads++;
    return pending.future;
  }
}

final class _ProfilePagingSession extends Fake implements PlaybackSession {
  _ProfilePagingSession(this.detail);
  @override
  final VideoDetail detail;
  @override
  VideoPart get part => detail.parts.last;
  @override
  String Function() get accountScope =>
      () => 'user:7';
  @override
  int Function() get sessionEpoch =>
      () => 0;
  @override
  int get sourceGeneration => 1;
  @override
  final snapshots = ValueNotifier(
    const PlaybackSnapshot(phase: PlaybackPhase.ended, generation: 1),
  );
  final advances = <({VideoId id, bool completed})>[];
  @override
  bool prepareNextVideo(
    VideoId id,
    String cid, {
    required VideoId nextId,
    String? nextCid,
    bool completed = false,
  }) {
    advances.add((id: nextId, completed: completed));
    return true;
  }
}

final class _UnusedPlaybackRepository extends Fake
    implements PlaybackRepository {}

final class _UnusedProgressStore extends Fake
    implements PlaybackProgressStore {}

final class _QueueHomeRepository
    implements HomeRepository, HomeWatchLaterRepository {
  @override
  String get accountScope => 'user:7';
  final entries = [
    for (var i = 1; i <= 3; i++)
      HomeEntry(
        id: 'original-entry-$i',
        aid: i == 2 ? '9007199254740993' : '$i',
        bvid: 'BV${i}abc123456',
        title: '队列视频 $i',
        kind: HomeEntryKind.video,
      ),
  ];
  final writes = <Completer<void>>[];
  final removed = <HomeEntry>[];
  final tokens = <RequestCancellation>[];

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => HomePage(entries, hasMore: false);

  @override
  Future<void> removeWatchLater(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) {
    removed.add(entry);
    tokens.add(cancellation);
    final write = Completer<void>();
    writes.add(write);
    return write.future;
  }
}

Future<void> _tagsSnapshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('VIDEO_TAGS_PREVIEW')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('video-tags-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Preview encoding failed');
    await Directory('build/video-tags-preview').create(recursive: true);
    await File('build/video-tags-preview/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

final class _TrackedPlayer extends StatefulWidget {
  const _TrackedPlayer({required this.onCreate, required this.onDispose});

  final VoidCallback onCreate;
  final VoidCallback onDispose;

  @override
  State<_TrackedPlayer> createState() => _TrackedPlayerState();
}

final class _TrackedPlayerState extends State<_TrackedPlayer> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

final class _VideoRepository implements VideoRepository {
  const _VideoRepository({
    this.access = const VideoAccess(),
    this.parts,
    this.authorMid,
    this.includeCollection = true,
  });
  final VideoAccess access;
  final List<VideoPart>? parts;
  final String? authorMid;
  final bool includeCollection;
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => VideoDetail(
    summary: VideoSummary(
      access: access,
      id: id,
      title: '测试视频',
      coverUrl: '',
      author: 'UP',
      duration: Duration(minutes: 6),
    ),
    authorMid: authorMid,
    description: '测试简介',
    collection: !includeCollection
        ? null
        : VideoCollection(
            id: '1',
            title: '测试合集',
            entries: [
              VideoCollectionEntry(
                id: VideoId('BV1xyz123456'),
                title: '合集视频',
                parts: [
                  VideoPart(
                    cid: '33',
                    page: 1,
                    title: '合集第一 P',
                    duration: Duration(minutes: 1),
                  ),
                  VideoPart(
                    cid: '44',
                    page: 2,
                    title: '合集第二 P',
                    duration: Duration(minutes: 1),
                  ),
                ],
              ),
            ],
          ),
    parts:
        parts ??
        [
          VideoPart(
            cid: '1',
            page: 1,
            title: '第一集',
            duration: Duration(minutes: 3),
          ),
          VideoPart(
            cid: '2',
            page: 2,
            title: '第二集',
            duration: Duration(minutes: 3),
          ),
        ],
  );
}

final class _ExtrasRepository implements VideoExtrasRepository {
  _ExtrasRepository({this.tags = const [], this.related});
  final List<String> tags;
  final List<VideoSummary>? related;
  int relatedRequests = 0;
  final List<int> commentPages = [];
  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => tags;
  @override
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    relatedRequests++;
    return related ??
        const [
          VideoSummary(
            id: VideoId('BV1xyz123456'),
            title: '相关推荐视频',
            coverUrl: '',
            author: '推荐UP',
            duration: Duration(minutes: 2),
            previewCid: '42',
          ),
        ];
  }

  @override
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  }) async {
    commentPages.add(page);
    return VideoCommentsPage(
      comments: [
        VideoComment(
          id: '$page',
          author: '用户',
          avatarUrl: '',
          message: '评论第$page页',
          likeCount: 2,
        ),
      ],
      hasMore: page == 1,
    );
  }
}

Finder _introScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('video-intro-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

List<VideoSummary> _manyRelated() => [
  for (var i = 0; i < 40; i++)
    VideoSummary(
      id: VideoId('BV${i.toString().padLeft(10, '0')}'),
      title: '推荐视频 $i',
      coverUrl: '',
      author: 'UP 主',
      duration: const Duration(minutes: 2),
      previewCid: '${i + 100}',
    ),
];
