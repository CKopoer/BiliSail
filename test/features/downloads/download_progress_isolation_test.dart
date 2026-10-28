import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/application/download_controller.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/presentation/downloads_screen.dart';
import 'package:bilisail/features/downloads/presentation/offline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask _task(
  int index, {
  DownloadStatus status = DownloadStatus.paused,
  String scope = 'user:1',
  String? title,
}) => DownloadTask(
  id: '$index',
  scope: scope,
  item: DownloadItem(
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

  testWidgets('large queue builds lazily and isolates byte progress', (
    tester,
  ) async {
    final repository = _Repository(List.generate(500, _task));
    addTearDown(repository.close);
    await _pump(tester, repository, const DownloadsScreen());

    final cardFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_DownloadTaskCard',
    );
    final mountedCards = cardFinder.evaluate().length;
    final delegate = tester
        .widget<ListView>(find.byType(ListView))
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

    for (var tick = 1; tick <= 10; tick++) {
      repository.progress('0', tick * 1024);
      await tester.pump();
      await tester.pump();
    }
    debugPrint(
      'download progress probe: eager=$eagerCards '
      'mounted=$mountedCards screenBuilds=${builds['DownloadsScreen'] ?? 0} '
      'cardBuilds=${builds['_DownloadTaskCard'] ?? 0}',
    );
    expect(find.text('已传输 1018 KB'), findsOneWidget);
    expect(eagerCards, 0);
    expect(mountedCards, lessThan(20));
    expect(builds['DownloadsScreen'] ?? 0, 0);
    expect(builds['_DownloadTaskCard'] ?? 0, 10);
    builds.clear();
    repository.progress('499', 10000);
    await tester.pump();
    await tester.pump();
    expect(builds['DownloadsScreen'] ?? 0, 0);
    expect(builds['_DownloadTaskCard'] ?? 0, 0);
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
            of: find.byType(ListView),
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
    return _state.tasks.firstWhere((task) => task.id == id);
  }

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
  Future<List<int>> qualities(
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
