import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/application/download_controller.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/presentation/download_dialog.dart';
import 'package:bilisail/features/downloads/presentation/downloads_screen.dart';
import 'package:bilisail/features/downloads/presentation/offline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _video = VideoSummary(
  id: const VideoId('BV1234567890'),
  title: '测试视频',
  coverUrl: '',
  author: '作者',
  duration: const Duration(minutes: 8),
);

DownloadItem _item(int index) => DownloadItem(
  video: _video,
  part: VideoPart(
    cid: '$index',
    page: index,
    title: '第 $index 集',
    duration: const Duration(minutes: 4),
  ),
);

DownloadTask _task(int index, DownloadStatus status) => DownloadTask(
  id: '$index',
  scope: 'user:1',
  item: _item(index),
  selection: const DownloadSelection(),
  status: status,
  directory: '/tmp/offline',
  createdAt: DateTime(2026, 10, 7),
  updatedAt: DateTime(2026, 10, 7),
  failure: status == DownloadStatus.failed
      ? const AppFailure(AppFailureKind.network, '连接中断')
      : null,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  _DownloadRepository repository,
  _SourceRepository source, {
  Size size = const Size(800, 700),
  double textScale = 1,
  GlobalKey? captureKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        downloadSourceRepositoryProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        theme: BiliTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: captureKey,
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final previewDirectory = Platform.environment['DOWNLOAD_PREVIEW_DIR'];
  if (previewDirectory != null && previewDirectory.isNotEmpty) {
    for (final width in [390.0, 1000.0]) {
      testWidgets('capture ${width.toInt()}px download preview', (
        tester,
      ) async {
        final repository = _DownloadRepository(
          tasks: [
            _task(1, DownloadStatus.downloading),
            _task(2, DownloadStatus.paused),
            _task(3, DownloadStatus.failed),
          ],
        );
        final key = GlobalKey();
        await _pump(
          tester,
          const DownloadsScreen(),
          repository,
          _SourceRepository(),
          size: Size(width, 800),
          captureKey: key,
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final target = File(
            '$previewDirectory/download-${width.toInt()}.png',
          );
          target.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await repository.close();
      });
    }
  }
  testWidgets('selection remains explicit and includes chosen episodes only', (
    tester,
  ) async {
    final repository = _DownloadRepository();
    final source = _SourceRepository();
    await _pump(
      tester,
      DownloadDialog(items: [_item(1), _item(2)], initialKey: _item(1).key),
      repository,
      source,
    );
    expect(repository.enqueued, isEmpty);
    expect(find.textContaining('已选 1 / 2'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('已选 2 / 2'), findsOneWidget);
    expect(repository.enqueued, isEmpty);
    await tester.tap(find.text('开始下载'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.enqueued.single.map((item) => item.part.cid), ['1', '2']);
    expect(repository.selection?.quality, 80);
    await repository.close();
  });

  testWidgets('unavailable quality prevents enqueue', (tester) async {
    final repository = _DownloadRepository();
    final source = _SourceRepository()
      ..qualitiesByCid = {
        '1': [80],
        '2': [64],
      };
    await _pump(
      tester,
      DownloadDialog(items: [_item(1), _item(2)]),
      repository,
      source,
    );
    expect(find.text('所选分集没有共同可用画质，请调整选择'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始下载'))
          .onPressed,
      isNull,
    );
    expect(repository.enqueued, isEmpty);
    await repository.close();
  });

  testWidgets('account change disables an already opened download dialog', (
    tester,
  ) async {
    final repository = _DownloadRepository();
    final source = _SourceRepository();
    await _pump(tester, DownloadDialog(items: [_item(1)]), repository, source);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始下载'))
          .onPressed,
      isNotNull,
    );
    source.scope = 'user:2';
    source.epoch = 2;
    repository.setTasks([]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('账号已变化，请重新打开下载窗口'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始下载'))
          .onPressed,
      isNull,
    );
    expect(repository.enqueued, isEmpty);
    await repository.close();
  });

  testWidgets('successful quality results are reused after selection changes', (
    tester,
  ) async {
    final repository = _DownloadRepository();
    final source = _SourceRepository();
    await _pump(
      tester,
      DownloadDialog(items: [_item(1), _item(2)]),
      repository,
      source,
    );
    expect(source.qualityCalls, 2);
    await tester.tap(find.text('清空'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('全选'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(source.qualityCalls, 2);
    await repository.close();
  });

  testWidgets('queue actions and delete cancellation preserve files choice', (
    tester,
  ) async {
    final repository = _DownloadRepository(
      tasks: [
        _task(1, DownloadStatus.downloading),
        _task(2, DownloadStatus.failed),
      ],
    );
    final source = _SourceRepository();
    await _pump(tester, const DownloadsScreen(), repository, source);
    await tester.tap(find.text('暂停'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.paused, ['1']);
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.resumed, ['2']);
    await tester.tap(find.text('删除任务').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('测试视频 · 第 1 集'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.removed, isEmpty);
    await tester.tap(find.text('删除任务').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('同时删除已下载文件'));
    await tester.tap(find.widgetWithText(FilledButton, '删除任务'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.removed, [('1', true)]);
    await repository.close();
  });

  testWidgets('unknown progress animates only during active transfer stages', (
    tester,
  ) async {
    final statuses = [
      DownloadStatus.queued,
      DownloadStatus.resolving,
      DownloadStatus.downloading,
      DownloadStatus.verifying,
      DownloadStatus.paused,
      DownloadStatus.failed,
    ];
    final repository = _DownloadRepository(
      tasks: [
        for (var index = 0; index < statuses.length; index++)
          _task(index + 1, statuses[index]),
      ],
    );
    await _pump(
      tester,
      const DownloadsScreen(),
      repository,
      _SourceRepository(),
      size: const Size(1000, 1800),
    );
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars.map((bar) => bar.value), [0, null, null, null, 0, 0]);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets('320px with large text has no overflow', (tester) async {
    final repository = _DownloadRepository(
      tasks: [_task(1, DownloadStatus.downloading)],
    );
    final source = _SourceRepository();
    await _pump(
      tester,
      const DownloadsScreen(),
      repository,
      source,
      size: const Size(320, 680),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  for (final width in [390.0, 1000.0]) {
    testWidgets('${width.toInt()}px download center has no overflow', (
      tester,
    ) async {
      final repository = _DownloadRepository(
        tasks: [
          _task(1, DownloadStatus.downloading),
          _task(2, DownloadStatus.completed),
        ],
      );
      final source = _SourceRepository();
      await _pump(
        tester,
        const DownloadsScreen(),
        repository,
        source,
        size: Size(width, 800),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('已完成'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('播放'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    });
  }

  testWidgets('320px large text download dialog scrolls without overflow', (
    tester,
  ) async {
    final repository = _DownloadRepository();
    final source = _SourceRepository();
    await _pump(
      tester,
      DownloadDialog(items: [_item(1), _item(2)]),
      repository,
      source,
      size: const Size(320, 680),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets('offline player waits for verification and unloads on deletion', (
    tester,
  ) async {
    final repository = _DownloadRepository(
      tasks: [_task(1, DownloadStatus.completed)],
    );
    final source = _SourceRepository();
    final gate = Completer<DownloadTask>();
    repository.offlineResult = gate.future;
    await _pump(
      tester,
      OfflineScreen(taskId: '1', playerBuilder: (_, _) => const Text('本地播放器')),
      repository,
      source,
    );
    expect(find.text('本地播放器'), findsNothing);
    gate.complete(repository.current.tasks.single);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('本地播放器'), findsOneWidget);
    repository.setTasks([]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('本地播放器'), findsNothing);
    await repository.close();
  });

  for (final width in [390.0, 1000.0]) {
    testWidgets('offline player has finite 16:9 bounds at ${width.toInt()}px', (
      tester,
    ) async {
      final repository = _DownloadRepository(
        tasks: [_task(1, DownloadStatus.completed)],
      );
      BoxConstraints? playerConstraints;
      await _pump(
        tester,
        OfflineScreen(
          taskId: '1',
          playerBuilder: (_, _) => LayoutBuilder(
            builder: (_, constraints) {
              playerConstraints = constraints;
              return const Stack(
                fit: StackFit.expand,
                children: [ColoredBox(color: Colors.black)],
              );
            },
          ),
        ),
        repository,
        _SourceRepository(),
        size: Size(width, 800),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(playerConstraints, isNotNull);
      expect(playerConstraints!.hasBoundedWidth, isTrue);
      expect(playerConstraints!.hasBoundedHeight, isTrue);
      expect(
        playerConstraints!.maxHeight,
        closeTo(playerConstraints!.maxWidth * 9 / 16, 0.1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    });
  }
}

final class _SourceRepository implements DownloadSourceRepository {
  Map<String, List<int>> qualitiesByCid = {};
  String scope = 'user:1';
  int epoch = 1;
  int qualityCalls = 0;
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<List<int>> qualities(
    DownloadItem item, {
    required RequestCancellation cancellation,
  }) async {
    qualityCalls++;
    return qualitiesByCid[item.part.cid] ?? [80, 64];
  }

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

final class _DownloadRepository implements DownloadRepository {
  _DownloadRepository({List<DownloadTask> tasks = const []})
    : _state = DownloadQueueState(tasks: tasks, initialized: true);
  DownloadQueueState _state;
  final _stream = StreamController<DownloadQueueState>.broadcast();
  final List<List<DownloadItem>> enqueued = [];
  DownloadSelection? selection;
  final List<String> paused = [], resumed = [];
  final List<(String, bool)> removed = [];
  Future<DownloadTask>? offlineResult;
  void setTasks(List<DownloadTask> tasks) {
    _state = DownloadQueueState(tasks: tasks, initialized: true);
    _stream.add(_state);
  }

  @override
  DownloadQueueState get current => _state;
  @override
  Stream<DownloadQueueState> get changes => _stream.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> enqueue(
    List<DownloadItem> items,
    DownloadSelection selection,
  ) async {
    enqueued.add(items);
    this.selection = selection;
  }

  @override
  Future<void> pause(String id) async => paused.add(id);
  @override
  Future<void> resume(String id) async => resumed.add(id);
  @override
  Future<void> pauseAll() async {}
  @override
  Future<void> resumeAll() async {}
  @override
  Future<void> remove(String id, {required bool deleteFiles}) async =>
      removed.add((id, deleteFiles));
  @override
  Future<void> refresh() async {}
  @override
  Future<void> updatePreferences(DownloadPreferences preferences) async {}
  @override
  Future<void> sessionChanged() async {}
  @override
  Future<DownloadTask> offlineTask(String id) =>
      offlineResult ??
      Future.value(_state.tasks.firstWhere((task) => task.id == id));
  @override
  Future<void> close() => _stream.close();
}
