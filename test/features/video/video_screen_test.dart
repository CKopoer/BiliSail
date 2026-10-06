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
import 'package:bilisail/core/presentation/playback_page_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'narrow window fills the page and restores details without remounting',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
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
      await tester.tap(find.text('评论'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(480, 660);
      await tester.pumpAndSettle();
      expect(find.text('评论'), findsNothing);
      expect(tester.getSize(find.byType(_TrackedPlayer)), const Size(480, 660));
      expect(find.byTooltip('展开视频信息').hitTestable(), findsOneWidget);
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpAndSettle();
      expect(find.text('暂无评论信息'), findsOneWidget);
      tester.view.physicalSize = const Size(480, 660);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开视频信息'));
      await tester.pumpAndSettle();
      expect(find.text('暂无评论信息'), findsOneWidget);
      expect(tester.getSize(find.byType(_TrackedPlayer)).height, 270);
      await tester.tap(find.byTooltip('收起视频信息'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(_TrackedPlayer)), const Size(480, 660));
      expect(created, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    },
  );

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
  int relatedRequests = 0;
  final List<int> commentPages = [];
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
