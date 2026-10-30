import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/video/presentation/watch_later_queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstId = VideoId('BV1abc123456');
const _secondId = VideoId('BV2abc123456');

WatchLaterQueueItem _item(int number) => WatchLaterQueueItem(
  entryId: 'entry-$number',
  aid: '${number + 1}',
  video: VideoSummary(
    id: number == 0
        ? _firstId
        : number == 1
        ? _secondId
        : VideoId('BV${number.toString().padLeft(10, '0')}'),
    title: '第 ${number + 1} 条稍后再看视频，标题用于验证两行省略',
    coverUrl: '',
    author: '测试 UP 主',
    duration: const Duration(minutes: 4, seconds: 33),
  ),
  playCountText: '64.5万',
  danmakuCountText: '539',
);

void main() {
  test(
    'confirmed removals change navigation while retaining the current source',
    () {
      final queue = WatchLaterQueue(
        id: 'queue',
        scope: 'user:7',
        sessionEpoch: 3,
        items: List.generate(3, _item),
      );
      final filtered = queue.withoutRemoved({
        'entry-0',
        'entry-1',
      }, current: _firstId);
      expect(filtered.items.map((item) => item.video.id), [
        _firstId,
        queue.items.last.video.id,
      ]);
      expect(
        filtered.adjacent(_firstId, 1)?.video.id,
        queue.items.last.video.id,
      );
      expect(filtered.withoutRemoved({'entry-0'}).items, [queue.items.last]);
      expect(queue.items, hasLength(3));
    },
  );
  test(
    'queue is scoped, bounded, and retains snapshots owned by open tabs',
    () {
      final registry = WatchLaterQueueRegistry();
      final first = registry.capture(
        scope: 'user:7',
        sessionEpoch: 3,
        items: [_item(0), _item(1)],
      )!;
      final nextSession = WatchLaterQueueRegistry().capture(
        scope: 'user:7',
        sessionEpoch: 3,
        items: [_item(0)],
      )!;
      expect(nextSession.id, isNot(first.id));
      expect(
        WatchLaterQueueRegistry().resolve(
          first.id,
          scope: 'user:7',
          sessionEpoch: 3,
        ),
        isNull,
      );
      expect(first.adjacent(_firstId, 1)?.video.id, _secondId);
      expect(first.adjacent(const VideoId('BV9abc123456'), 1), isNull);
      registry.retain(first.id);
      for (var i = 0; i < 20; i++) {
        registry.capture(scope: 'user:7', sessionEpoch: 3, items: [_item(0)]);
      }
      expect(
        registry.resolve(first.id, scope: 'user:7', sessionEpoch: 3),
        same(first),
      );
      registry.release(first.id);
      registry.capture(scope: 'user:7', sessionEpoch: 3, items: [_item(0)]);
      expect(
        registry.resolve(first.id, scope: 'user:7', sessionEpoch: 3),
        isNull,
      );
      final bounded = registry.capture(
        scope: 'user:7',
        sessionEpoch: 3,
        items: List.generate(1200, _item),
      )!;
      expect(bounded.items.length, WatchLaterQueueRegistry.maximumItems);
      expect(
        registry.resolve(bounded.id, scope: 'user:7', sessionEpoch: 4),
        isNull,
      );
      expect(
        registry.resolve(bounded.id, scope: 'user:8', sessionEpoch: 3),
        isNull,
      );
    },
  );

  setUpAll(() async {
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

  testWidgets(
    'scrolling both edges requests adjacent pages and retains the visible anchor',
    (tester) async {
      var start = 20, end = 40;
      var previousAvailable = true;
      var previousReads = 0, nextReads = 0;
      late StateSetter update;
      final current = _item(20).video.id;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 380,
                height: 600,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return WatchLaterQueuePanel(
                      queue: WatchLaterQueue(
                        id: 'moving',
                        scope: 'user:7',
                        sessionEpoch: 0,
                        items: [for (var i = start; i < end; i++) _item(i)],
                      ),
                      current: current,
                      expanded: true,
                      onToggle: () {},
                      onSelect: (_) {},
                      onLoadPrevious: previousAvailable
                          ? () => previousReads++
                          : null,
                      onLoadMore: () => nextReads++,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(previousReads, 0);
      expect(nextReads, 0);
      final list = find.byKey(const ValueKey('watch-later-queue-list'));
      await tester.drag(list, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(previousReads, greaterThan(0));
      final anchor = find.byKey(ValueKey('watch-later-queue-${current.value}'));
      final before = tester.getRect(anchor).top;
      update(() {
        start = 0;
        previousAvailable = false;
      });
      await tester.pumpAndSettle();
      expect(tester.getRect(anchor).top, closeTo(before, 1));
      expect(nextReads, 0);
      await tester.drag(list, const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(nextReads, greaterThan(0));
      final tail = find.byKey(
        ValueKey('watch-later-queue-${_item(39).video.id.value}'),
      );
      final oldTailTop = tester.getRect(tail).top;
      final reads = nextReads;
      update(() {
        start = 20;
        end = 60;
        previousAvailable = true;
      });
      await tester.pumpAndSettle();
      expect(tester.getRect(tail).top, closeTo(oldTailTop, 1));
      expect(nextReads, reads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queue heading folds, selected row scrolls into view, and rows navigate',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final queue = WatchLaterQueue(
        id: 'queue',
        scope: 'user:7',
        sessionEpoch: 3,
        items: List.generate(58, _item),
      );
      final selected = <VideoId>[];
      var expanded = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 380,
                height: 600,
                child: StatefulBuilder(
                  builder: (context, setState) => WatchLaterQueuePanel(
                    queue: queue,
                    current: queue.items[40].video.id,
                    expanded: expanded,
                    onToggle: () => setState(() => expanded = !expanded),
                    onSelect: selected.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('41/58'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey('watch-later-queue-${queue.items[40].video.id.value}'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('watch-later-queue-list')),
        findsNothing,
      );
      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('watch-later-queue-${queue.items[40].video.id.value}'),
        ),
      );
      expect(selected, [queue.items[40].video.id]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queue counts share numeric text, fallback and abbreviation formatting',
    (tester) async {
      for (final (text, count, expected) in <(String, int?, String)>[
        ('0', 12345, '0'),
        ('9999', null, '9999'),
        ('10000', null, '1.0万'),
        ('12345', null, '1.2万'),
        ('100000000', null, '1.0亿'),
        ('123456789', null, '1.2亿'),
        ('  ', 12345, '1.2万'),
        ('', null, '—'),
        ('2.34亿', 12345, '2.34亿'),
      ]) {
        final queue = WatchLaterQueue(
          id: 'counts',
          scope: 'user:7',
          sessionEpoch: 0,
          items: [
            WatchLaterQueueItem(
              video: VideoSummary(
                id: _firstId,
                title: '计数测试',
                coverUrl: '',
                author: 'UP',
                duration: const Duration(minutes: 1),
                playCount: count,
                danmakuCount: count,
              ),
              playCountText: text,
              danmakuCountText: text,
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 380,
                height: 600,
                child: WatchLaterQueuePanel(
                  queue: queue,
                  current: _firstId,
                  expanded: true,
                  onToggle: () {},
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected), findsNWidgets(2), reason: '$text / $count');
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'queue transition retains details and reverses safely, reducedMotion=$reducedMotion',
      (tester) async {
        var expanded = true;
        var detailBuilds = 0;
        final queue = WatchLaterQueue(
          id: 'motion',
          scope: 'user:7',
          sessionEpoch: 0,
          items: List.generate(1000, _item),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(disableAnimations: reducedMotion),
                child: SizedBox(
                  width: 380,
                  height: 600,
                  child: StatefulBuilder(
                    builder: (context, setState) => WatchLaterQueuePanel(
                      queue: queue,
                      current: _firstId,
                      expanded: expanded,
                      onToggle: () => setState(() => expanded = !expanded),
                      onSelect: (_) {},
                      collapsedChild: Builder(
                        builder: (_) {
                          detailBuilds++;
                          return const Text('保留的简介');
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(detailBuilds, 0);
        expect(
          find.byKey(
            ValueKey('watch-later-queue-${queue.items.last.video.id.value}'),
          ),
          findsNothing,
        );
        await tester.tap(find.text('稍后再看'));
        await tester.pump();
        final details = tester.element(find.text('保留的简介'));
        final builds = detailBuilds;
        if (!reducedMotion) {
          final fade = tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('watch-later-queue-list')),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          await tester.pump(const Duration(milliseconds: 60));
          expect(fade.opacity.value, inExclusiveRange(0, 1));
          expect(detailBuilds, builds);
          // Reverse before settling; retain one details element and one list.
          await tester.tap(find.text('稍后再看'));
          await tester.pump();
          await tester.pumpAndSettle();
          expect(details.mounted, isTrue);
          expect(find.text('保留的简介'), findsNothing);
          await tester.tap(find.text('稍后再看'));
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('watch-later-queue-list')),
          findsNothing,
        );
        expect(details.mounted, isTrue);
        expect(find.text('保留的简介'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'queue renders theme and narrow large-text previews without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final queue = WatchLaterQueue(
        id: 'preview',
        scope: 'user:7',
        sessionEpoch: 3,
        items: List.generate(58, _item),
      );
      for (final (name, dark, expanded, width, scale) in [
        ('light-expanded', false, true, 380.0, 1.0),
        ('light-folded', false, false, 380.0, 1.0),
        ('dark-expanded', true, true, 380.0, 1.0),
        ('narrow-large', false, true, 360.0, 2.0),
      ]) {
        const previewCase = String.fromEnvironment(
          'WATCH_LATER_QUEUE_PREVIEW_CASE',
        );
        if (previewCase.isNotEmpty && previewCase != name) continue;
        tester.view.physicalSize = Size(width, 700);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BiliTheme.dark() : BiliTheme.light(),
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('queue-preview'),
                child: Material(
                  color: dark
                      ? BiliTheme.dark().colorScheme.surface
                      : BiliTheme.light().colorScheme.surface,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SizedBox(
                      width: width,
                      height: 700,
                      child: WatchLaterQueuePanel(
                        queue: queue,
                        current: _firstId,
                        expanded: expanded,
                        onToggle: () {},
                        onSelect: (_) {},
                        onRemove: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        if (previewCase == name) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('queue-preview')),
          );
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final result = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            return result;
          });
          final directory = Directory('build/watch-later-queue-preview')
            ..createSync(recursive: true);
          File('${directory.path}/$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        }
      }
      addTearDown(tester.view.resetPhysicalSize);
    },
  );
}
