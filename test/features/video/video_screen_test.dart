import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:bilisail/features/video/presentation/video_collection_panel.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/core/presentation/playback_page_commands.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

void main() {
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
          child: MaterialApp(
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
      expect(find.byTooltip('收起视频信息'), findsOneWidget);
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
    'tags stay visible and search full names without expanding intro',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
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
          child: MaterialApp(
            theme: BiliTheme.light(),
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('video-tags-preview'),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: VideoScreen(
                id: const VideoId('BV1abc123456'),
                onSearchTag: (value) => searched = value,
                playerBuilder: (_, _, _) =>
                    _TrackedPlayer(onCreate: () => created++, onDispose: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试简介'), findsNothing);
      expect(find.text('标签'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, tag));
      expect(searched, tag);
      await _tagsSnapshot(tester, 'wide');
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.text('测试简介'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(find.byTooltip('收起视频信息'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      await _tagsSnapshot(tester, 'narrow');
      expect(created, 1);
      expect(tester.takeException(), isNull);
    },
  );

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
            child: MaterialApp(
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
        expect(find.byTooltip('收起视频信息'), findsOneWidget);
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
          expect(find.byTooltip('收起视频信息'), findsOneWidget);
          expect(
            tester.getSize(find.byType(_TrackedPlayer)).height,
            width >= 1000 ? 660 : width * 9 / 16,
          );
        }
        await tester.tap(find.byTooltip('收起视频信息'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(_TrackedPlayer)),
          const Size(480, 660),
        );
        for (final width in [1100.0, 480.0]) {
          tester.view.physicalSize = Size(width, 660);
          await tester.pumpAndSettle();
          expect(find.text('评论'), findsNothing);
          expect(find.byTooltip('展开视频信息'), findsOneWidget);
          expect(tester.getSize(find.byType(_TrackedPlayer)), Size(width, 660));
        }
        final commands = tester.widget<PlaybackPageCommands>(
          find.byType(PlaybackPageCommands),
        );
        commands.toggleInfo();
        await tester.pumpAndSettle();
        expect(find.text('暂无评论信息'), findsOneWidget);
        expect(find.byTooltip('收起视频信息'), findsOneWidget);
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
          child: MaterialApp(
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
        child: MaterialApp(
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
        child: MaterialApp(
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
        child: MaterialApp(
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
        child: MaterialApp(
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
        child: MaterialApp(
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

Widget _relatedCardApp(
  _RelatedCardOperations operations, {
  required VoidCallback onOpen,
  ValueChanged<String>? onNotice,
  VideoPlayerBuilder? playerBuilder,
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(_GuestAuthController.new),
    videoRepositoryProvider.overrideWithValue(_VideoRepository()),
    videoExtrasRepositoryProvider.overrideWithValue(_ExtrasRepository()),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: VideoCardInteractionScope(
        interactions: operations,
        onNotice: (_, message) => onNotice?.call(message),
        child: VideoScreen(
          id: const VideoId('BV1abc123456'),
          onOpenVideo: (_) => onOpen(),
          playerBuilder: playerBuilder ?? (_, _, _) => const SizedBox(),
        ),
      ),
    ),
  ),
);

final class _RelatedCardOperations implements VideoCardOperations {
  final engines = <CardFakeEngine>[];
  late final previews = VideoCardPreviewPlayback(
    createEngine: () {
      final engine = CardFakeEngine();
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

final class _UnusedPlaybackRepository extends Fake
    implements PlaybackRepository {}

final class _UnusedProgressStore extends Fake
    implements PlaybackProgressStore {}

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
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => const VideoDetail(
    summary: VideoSummary(
      id: VideoId('BV1abc123456'),
      title: '测试视频',
      coverUrl: '',
      author: 'UP',
      duration: Duration(minutes: 6),
    ),
    description: '测试简介',
    collection: VideoCollection(
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
    parts: [
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
  _ExtrasRepository({this.tags = const []});
  final List<String> tags;
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
    return const [
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
