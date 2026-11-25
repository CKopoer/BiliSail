import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/downloads/application/download_controller.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/presentation/downloads_screen.dart';
import 'package:bilisail/features/downloads/presentation/offline_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/playback_layout_session_fake.dart';

DownloadTask _task(
  int index, {
  DownloadStatus status = DownloadStatus.paused,
  String scope = 'user:1',
  String? title,
  String? seasonId,
  int? seasonType,
}) => DownloadTask(
  id: '$index',
  scope: scope,
  item: DownloadItem(
    seasonId: seasonId,
    episodeId: seasonId == null ? null : '$index',
    work: seasonType == null
        ? null
        : DownloadWork(seasonType: seasonType, description: '作品简介 $index'),
    video: VideoSummary(
      id: const VideoId('BV1234567890'),
      title: title ?? 'Video $index',
      coverUrl: '',
      author: 'Author',
      duration: const Duration(minutes: 1),
    ),
    part: VideoPart(
      cid: '$index',
      page: index + 1,
      title: 'Episode $index',
      duration: const Duration(minutes: 1),
    ),
  ),
  selection: const DownloadSelection(),
  status: status,
  directory: '/offline/$index',
  createdAt: DateTime(2026, 10, 28),
  updatedAt: DateTime(2026, 10, 28),
  tracks: [
    for (final kind in DownloadTrackKind.values)
      DownloadTrackProgress(
        kind: kind,
        identity: kind.name,
        fileName: '${kind.name}.m4s',
        codec: 'test',
        bandwidth: 100,
        bytes: 1024,
        totalBytes: 100000,
      ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  _Repository repository,
  Widget screen, {
  _Source? source,
  Size size = const Size(1000, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadSourceRepositoryProvider.overrideWithValue(source ?? _Source()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: screen),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a missing file leaves the player and other local entries usable at large text',
    (tester) async {
      final first = _task(
        1,
        status: DownloadStatus.completed,
        seasonId: '77',
        seasonType: 4,
      );
      final second = _task(
        2,
        status: DownloadStatus.completed,
        seasonId: '77',
        seasonType: 4,
      );
      final repository = _Repository([first, second]);
      addTearDown(repository.close);
      final failed = Completer<DownloadTask>();
      repository.pending['2'] = failed.future;
      await _pump(
        tester,
        repository,
        Theme(
          data: ThemeData.dark(),
          child: OfflineScreen(
            taskId: '1',
            playerBuilder: (_, task) => Text('播放文件 ${task.id}'),
          ),
        ),
        size: const Size(320, 760),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      final target = find.text('Episode 2');
      await tester.dragUntilVisible(
        target,
        find.byType(CustomScrollView).last,
        const Offset(0, -120),
      );
      await tester.tap(target);
      await tester.pump();
      repository.setTasks([
        first,
        second.copyWith(status: DownloadStatus.failed),
      ]);
      failed.completeError(const AppFailure(AppFailureKind.storage, '本地文件已移走'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('本地文件已移走'), findsOneWidget);
      expect(find.text('播放文件 1'), findsOneWidget);
      expect(find.text('Episode 2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'completed categories combine the query with reliable season types',
    (tester) async {
      final tasks = [
        _task(1, status: DownloadStatus.completed),
        for (final (index, type) in [(2, 1), (3, 4), (4, 2), (5, null)])
          _task(
            index,
            status: DownloadStatus.completed,
            seasonId: '$index',
            seasonType: type,
          ),
        _task(6, seasonId: '6', seasonType: 1),
      ];
      final repository = _Repository(tasks);
      addTearDown(repository.close);
      await _pump(tester, repository, const DownloadsScreen());
      await tester.tap(find.text('已完成'));
      await tester.pumpAndSettle();
      for (final (label, ids) in [
        ('视频', [1]),
        ('番剧', [2]),
        ('国创', [3]),
        ('影视', [4, 5]),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        for (var i = 1; i <= 6; i++) {
          expect(
            find.text('Video $i'),
            ids.contains(i) ? findsOneWidget : findsNothing,
          );
        }
      }
      await tester.enterText(find.byType(TextField), 'Episode 5');
      await tester.pump();
      expect(find.text('Video 5'), findsOneWidget);
      expect(find.text('Video 4'), findsNothing);
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('Video 5'), findsOneWidget);
      expect(find.text('Video 1'), findsNothing);
    },
  );

  testWidgets(
    'browsing the library preserves playback and a late verification cannot replace a later pick',
    (tester) async {
      final tasks = [
        _task(1, status: DownloadStatus.completed),
        _task(2, status: DownloadStatus.completed),
        _task(
          3,
          status: DownloadStatus.completed,
          seasonId: '9',
          seasonType: 4,
        ),
      ];
      final repository = _Repository(tasks);
      addTearDown(repository.close);
      final selected = <String>[];
      await _pump(
        tester,
        repository,
        OfflineScreen(
          taskId: '1',
          onTaskChanged: selected.add,
          playerBuilder: (_, t) => Text('播放文件 ${t.id}'),
        ),
      );
      await tester.pumpAndSettle();
      final delayed = Completer<DownloadTask>();
      repository.pending['2'] = delayed.future;
      await tester.tap(find.text('P3 · Episode 2'));
      await tester.pump();
      await tester.tap(find.text('全部下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Video 3'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(find.text('播放文件 1'), findsOneWidget);
      await tester.tap(find.text('Episode 3'));
      await tester.pumpAndSettle();
      expect(find.text('本季剧集'), findsOneWidget);
      expect(find.text('作品简介 3'), findsOneWidget);
      delayed.complete(tasks[1]);
      await tester.pumpAndSettle();
      expect(selected, ['3']);
      expect(find.text('播放文件 3'), findsOneWidget);
    },
  );
  test(
    'derived queue index is released after its last UI subscription',
    () async {
      final repository = _Repository([_task(0)]);
      addTearDown(repository.close);
      final container = ProviderContainer(
        overrides: [downloadRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        downloadQueueIndexProvider,
        (_, _) {},
      );
      expect(container.exists(downloadQueueIndexProvider), isTrue);
      subscription.close();
      await container.pump();
      expect(container.exists(downloadQueueIndexProvider), isFalse);
      repository.progress('0', 10000);
      await container.pump();
      expect(container.exists(downloadQueueIndexProvider), isFalse);
    },
  );

  test('completed row layout changes invalidate the queue structure', () async {
    final completed = _task(0, status: DownloadStatus.completed);
    final repository = _Repository([completed, _task(1)]);
    addTearDown(repository.close);
    final container = ProviderContainer(
      overrides: [downloadRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      downloadQueueIndexProvider,
      (_, _) {},
    );
    final original = subscription.read().structure;

    repository.progress('1', 4096);
    await container.pump();
    expect(subscription.read().structure, same(original));

    repository.setTasks([
      completed.copyWith(warnings: ['需要重新下载离线字幕']),
      repository.current.tasks.last,
    ]);
    await container.pump();
    expect(subscription.read().structure, isNot(same(original)));
    subscription.close();
  });

  testWidgets('large queue builds lazily and isolates byte progress', (
    tester,
  ) async {
    final repository = _Repository(List.generate(500, _task));
    addTearDown(repository.close);
    final activity = ValueNotifier((active: true, previewing: false));
    addTearDown(activity.dispose);
    await _pump(
      tester,
      repository,
      ValueListenableBuilder(
        valueListenable: activity,
        child: const DownloadsScreen(),
        builder: (context, value, child) => Offstage(
          offstage: !value.active && !value.previewing,
          child: WorkspaceActivity(
            active: value.active,
            previewing: value.previewing,
            child: child!,
          ),
        ),
      ),
    );

    final cardFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_DownloadTaskCard',
    );
    final mountedCards = cardFinder.evaluate().length;
    final delegate = tester
        .widget<ListView>(find.bySubtype<ListView>())
        .childrenDelegate;
    final eagerCards = delegate is SliverChildListDelegate
        ? delegate.children
              .where(
                (widget) =>
                    widget.runtimeType.toString() == '_DownloadTaskCard',
              )
              .length
        : 0;
    final builds = <String, int>{};
    final previousHook = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousHook?.call(element, builtOnce);
      final type = element.widget.runtimeType.toString();
      builds.update(type, (count) => count + 1, ifAbsent: () => 1);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousHook);

    for (var tick = 2; tick <= 11; tick++) {
      repository.progress('0', tick * 1024);
      await tester.pump();
      await tester.pump();
    }
    debugPrint(
      'download progress probe: eager=$eagerCards '
      'mounted=$mountedCards screenBuilds=${builds['_DownloadsContent'] ?? 0} '
      'cardBuilds=${builds['_DownloadTaskCard'] ?? 0} '
      'transferBuilds=${builds['_DownloadTransferDetails'] ?? 0}',
    );
    expect(find.text('已传输 1020 KB'), findsOneWidget);
    expect(eagerCards, 0);
    expect(mountedCards, lessThan(20));
    expect(builds['_DownloadsContent'] ?? 0, 0);
    expect(builds['_DownloadTaskCard'] ?? 0, 0);
    expect(builds['_DownloadTransferDetails'], 10);
    expect(builds['_DownloadProgressIndicator'], 10);
    builds.clear();
    repository.progress('499', 10000);
    await tester.pump();
    await tester.pump();
    expect(builds['_DownloadsContent'] ?? 0, 0);
    expect(builds['_DownloadTaskCard'] ?? 0, 0);
    expect(builds['_DownloadTransferDetails'] ?? 0, 0);

    activity.value = (active: false, previewing: false);
    await tester.pump();
    builds.clear();
    repository.progress('0', 20 * 1024);
    await tester.pump();
    await tester.pump();
    expect(builds['_DownloadTransferredLabel'] ?? 0, 0);
    expect(builds['_DownloadTransferDetails'] ?? 0, 0);
    expect(builds['_DownloadProgressIndicator'] ?? 0, 0);

    activity.value = (active: false, previewing: true);
    await tester.pump();
    await tester.pump();
    expect(find.text('40 KB / 195 KB'), findsOneWidget);
  });

  testWidgets(
    'search projection survives progress and tracks regrouping and replacement',
    (tester) async {
      final repository = _Repository([
        _task(0, status: DownloadStatus.downloading),
        _task(1, status: DownloadStatus.completed),
      ]);
      addTearDown(repository.close);
      await _pump(tester, repository, const DownloadsScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DownloadsScreen)),
      );
      final structure = container.read(downloadQueueIndexProvider).structure;
      await tester.enterText(find.byType(TextField), '  ViDeO 0  ');
      await tester.pump();
      expect(find.text('Video 0'), findsOneWidget);
      expect(find.text('Video 1'), findsNothing);
      repository.progress('0', 12345);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(downloadQueueIndexProvider).structure,
        same(structure),
      );
      expect(find.text('Video 0'), findsOneWidget);

      repository.setTasks([
        repository.current.tasks.first.copyWith(
          status: DownloadStatus.completed,
        ),
        repository.current.tasks.last,
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('没有匹配的下载任务'), findsOneWidget);
      await tester.tap(find.text('已完成'));
      await tester.pump();
      expect(find.text('Video 0'), findsOneWidget);
      expect(find.text('Video 1'), findsNothing);

      repository.setTasks([
        _task(
          0,
          status: DownloadStatus.completed,
          scope: 'user:2',
          title: 'Replacement',
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('没有匹配的下载任务'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'replacement');
      await tester.pump();
      expect(find.text('Replacement'), findsOneWidget);
      expect(
        container.read(downloadQueueIndexProvider).tasksById['0']?.scope,
        'user:2',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('completed actions use current task and updated callbacks', (
    tester,
  ) async {
    final repository = _Repository([
      _task(0, status: DownloadStatus.completed),
    ]);
    addTearDown(repository.close);
    final source = _Source();
    DownloadTask? played;
    var oldCallbackCalls = 0;
    String? opened;
    await _pump(
      tester,
      repository,
      DownloadsScreen(
        onPlay: (_) => oldCallbackCalls++,
        onOpenDirectory: (_) async => oldCallbackCalls++,
      ),
      source: source,
    );
    await tester.tap(find.text('已完成'));
    await tester.pump();
    repository.progress('0', 10000);
    await tester.pump();
    await tester.pump();
    await _pump(
      tester,
      repository,
      DownloadsScreen(
        onPlay: (task) => played = task,
        onOpenDirectory: (directory) async => opened = directory,
      ),
      source: source,
    );
    await tester.tap(find.text('播放'));
    await tester.tap(find.text('打开目录'));
    await tester.pump();
    expect(played, same(repository.current.tasks.single));
    expect(played?.downloadedBytes, 20000);
    expect(opened, '/offline/0');
    expect(oldCallbackCalls, 0);
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除任务'));
    await tester.pumpAndSettle();
    expect(repository.removed, [('0', false)]);
  });

  testWidgets(
    'scroll offset and search survive progress and responsive rebuilds',
    (tester) async {
      final repository = _Repository(List.generate(100, _task));
      addTearDown(repository.close);
      final source = _Source();
      await _pump(tester, repository, const DownloadsScreen(), source: source);
      await tester.enterText(find.byType(TextField), 'video');
      await tester.pump();
      final scrollable = find
          .descendant(
            of: find.bySubtype<ListView>(),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(2000);
      await tester.pump();
      final offset = position.pixels;
      repository.progress('0', 10000);
      await tester.pump();
      await tester.pump();
      expect(position.pixels, offset);
      await _pump(
        tester,
        repository,
        const DownloadsScreen(),
        source: source,
        size: const Size(320, 800),
        textScale: 1.5,
      );
      expect(position.pixels, offset);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -600,
        scrollable: scrollable,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'video',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline listening uses half the page and retains its player', (
    tester,
  ) async {
    final repository = _Repository([
      _task(1, status: DownloadStatus.completed),
    ]);
    final session = PlaybackLayoutSessionFake();
    addTearDown(repository.close);
    addTearDown(session.dispose);
    const player = ColoredBox(
      key: ValueKey('offline-listening-player'),
      color: Colors.black,
    );
    await _pump(
      tester,
      repository,
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: OfflineScreen(
          taskId: '1',
          playerBuilder: (context, _) {
            ProviderScope.containerOf(context).read(playbackSessionProvider);
            return player;
          },
        ),
      ),
      size: const Size(390, 800),
    );
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('offline-listening-player'));
    final element = tester.element(finder);
    expect(tester.getSize(finder).height, 390 * 9 / 16);
    await session.setAudioOnly(true);
    await tester.pumpAndSettle();
    expect(tester.getSize(finder).height, 400);
    expect(tester.element(finder), same(element));
    await session.setAudioOnly(false);
    await tester.pumpAndSettle();
    expect(tester.getSize(finder).height, 390 * 9 / 16);
    expect(tester.element(finder), same(element));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrelated queue progress leaves the offline player intact', (
    tester,
  ) async {
    final repository = _Repository([
      _task(0),
      _task(1, status: DownloadStatus.completed),
    ]);
    addTearDown(repository.close);
    var playerBuilds = 0;
    await _pump(
      tester,
      repository,
      OfflineScreen(
        taskId: '1',
        playerBuilder: (_, _) {
          playerBuilds++;
          return const Text('Offline player');
        },
      ),
    );
    await tester.pump();
    final initialBuilds = playerBuilds;
    for (var tick = 1; tick <= 10; tick++) {
      repository.progress('0', tick * 1024);
      await tester.pump();
      await tester.pump();
    }
    debugPrint(
      'offline progress probe: playerBuilds='
      '${playerBuilds - initialBuilds} verificationCalls=${repository.verifications}',
    );
    expect(playerBuilds - initialBuilds, 0);
    expect(repository.verifications, 1);
  });

  testWidgets(
    'offline availability follows account scope and current task status',
    (tester) async {
      final completed = _task(1, status: DownloadStatus.completed);
      final repository = _Repository([completed]);
      final source = _Source();
      addTearDown(repository.close);
      await _pump(
        tester,
        repository,
        OfflineScreen(
          taskId: '1',
          playerBuilder: (_, task) => Text('Player ${task.scope}'),
        ),
        source: source,
      );
      await tester.pump();
      expect(find.text('Player user:1'), findsOneWidget);
      source.scope = 'user:2';
      repository.setTasks([completed]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Player user:1'), findsNothing);
      expect(find.textContaining('已不可用'), findsOneWidget);
      repository.setTasks([
        _task(1, status: DownloadStatus.completed, scope: 'user:2'),
      ]);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Player user:2'), findsOneWidget);
      expect(repository.verifications, 2);
      repository.setTasks([
        repository.current.tasks.single.copyWith(status: DownloadStatus.failed),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Player user:2'), findsNothing);
      expect(find.textContaining('已不可用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Repository implements DownloadRepository {
  _Repository(List<DownloadTask> tasks)
    : _state = DownloadQueueState(tasks: tasks, initialized: true);
  DownloadQueueState _state;
  final _changes = StreamController<DownloadQueueState>.broadcast();
  int verifications = 0;
  final List<(String, bool)> removed = [];

  void setTasks(List<DownloadTask> tasks) {
    _state = DownloadQueueState(tasks: tasks, initialized: true);
    _changes.add(_state);
  }

  void progress(String id, int bytes) => setTasks([
    for (final task in _state.tasks)
      if (task.id == id)
        task.copyWith(
          tracks: [
            for (final track in task.tracks) track.copyWith(bytes: bytes),
          ],
        )
      else
        task,
  ]);

  @override
  DownloadQueueState get current => _state;
  @override
  Stream<DownloadQueueState> get changes => _changes.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> close() => _changes.close();
  @override
  Future<void> enqueue(
    List<DownloadItem> items,
    DownloadSelection selection,
  ) async {}
  @override
  Future<DownloadTask> offlineTask(String id) async {
    verifications++;
    if (pending[id] case final future?) return future;
    return _state.tasks.firstWhere((task) => task.id == id);
  }

  final pending = <String, Future<DownloadTask>>{};

  @override
  Future<void> pause(String id) async {}
  @override
  Future<void> pauseAll() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> remove(String id, {required bool deleteFiles}) async =>
      removed.add((id, deleteFiles));
  @override
  Future<void> resume(String id) async {}
  @override
  Future<void> resumeAll() async {}
  @override
  Future<void> sessionChanged() async {}
  @override
  Future<void> updatePreferences(DownloadPreferences preferences) async {}
}

final class _Source implements DownloadSourceRepository {
  String scope = 'user:1';
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => 1;
  @override
  Future<Set<DownloadVideoOption>> videoOptions(
    DownloadItem item, {
    required RequestCancellation cancellation,
  }) => throw UnimplementedError();
  @override
  Future<DownloadResolvedSource> resolve(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) => throw UnimplementedError();
  @override
  Future<DownloadExtras> extras(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) => throw UnimplementedError();
}
