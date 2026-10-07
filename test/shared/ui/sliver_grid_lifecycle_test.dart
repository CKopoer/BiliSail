import 'dart:async';

import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _GridKind { responsive, video, indexedVideo }

void main() {
  for (final kind in _GridKind.values) {
    testWidgets(
      '$kind invalidates equal-count data and shifted action identities',
      (tester) async {
        final entries = ValueNotifier(_entries('a'));
        addTearDown(entries.dispose);
        final opened = <String>[];
        final menus = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: entries,
                builder: (_, values, _) => CustomScrollView(
                  slivers: [
                    _grid(kind, values, opened: opened.add, menu: menus.add),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('a0'), findsOneWidget);
        entries.value = _entries('b');
        await tester.pumpAndSettle();
        expect(find.text('a0'), findsNothing);
        expect(find.text('b0'), findsOneWidget);
        await tester.tap(find.text('b0'));
        await tester.pumpAndSettle();
        expect(opened, ['b0']);

        entries.value = entries.value.skip(1).toList();
        await tester.pumpAndSettle();
        expect(find.text('b0'), findsNothing);
        expect(find.text('b1'), findsOneWidget);
        await tester.tap(find.text('b1'));
        await tester.pumpAndSettle();
        expect(opened, ['b0', 'b1']);
        final card = kind == _GridKind.responsive
            ? find.byKey(const ValueKey('card-b1'))
            : find.ancestor(
                of: find.text('b1'),
                matching: find.byType(VideoCard),
              );
        await tester.tap(
          find.descendant(
            of: card,
            matching: kind == _GridKind.responsive
                ? find.byType(PopupMenuButton<String>)
                : find.byKey(const ValueKey('video-card-title-menu')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(menus, ['b1']);
        expect(opened, ['b0', 'b1'], reason: 'menu must not open the video');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$kind retains mounted cards on small scrolls and top-button changes',
      (tester) async {
        var viewportBuilds = 0;
        late ScrollController controller;
        final builtItems = <String, int>{};
        final grid = _grid(
          kind,
          _entries('a'),
          built: (id) {
            builtItems.update(id, (count) => count + 1, ifAbsent: () => 1);
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PagedScrollViewport(
                active: true,
                canLoadMore: false,
                contentVersion: 1,
                onLoadMore: () async {},
                onRefresh: () async {},
                builder: (value) {
                  viewportBuilds++;
                  controller = value;
                  return CustomScrollView(controller: value, slivers: [grid]);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cards = kind == _GridKind.responsive
            ? find.byType(_Card)
            : find.byType(VideoCard);
        final originals = tester.widgetList(cards).toList();
        final initialBuilds = Map<String, int>.of(builtItems);
        expect(originals.length, inInclusiveRange(2, 30));
        expect(viewportBuilds, 1);
        expect(find.byTooltip('回到顶部'), findsNothing);
        controller.jumpTo(20);
        await tester.pumpAndSettle();
        expect(find.byTooltip('回到顶部'), findsOneWidget);
        expect(viewportBuilds, 1);
        final mounted = tester.widgetList(cards).toList();
        final retained = originals.where(mounted.contains).toList();
        expect(retained.length, originals.length);
        for (final id in initialBuilds.keys) {
          expect(
            builtItems[id],
            initialBuilds[id],
            reason: 'scrolling must not invoke the existing row builder again',
          );
        }
        controller.jumpTo(40);
        await tester.pumpAndSettle();
        expect(viewportBuilds, 1);
        for (final card in retained) {
          expect(find.byWidget(card), findsOneWidget);
        }
        await tester.tap(find.byTooltip('回到顶部'));
        await tester.pumpAndSettle();
        expect(controller.offset, 0);
        expect(find.byTooltip('回到顶部'), findsNothing);
        expect(viewportBuilds, 1);
        for (final card in retained) {
          expect(find.byWidget(card), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final kind in [_GridKind.responsive, _GridKind.video]) {
    testWidgets(
      '$kind invalidates cached row layout on width and text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(700, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scale = ValueNotifier(1.0);
        addTearDown(scale.dispose);
        final grid = _grid(kind, _entries('a'));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: scale,
                child: CustomScrollView(slivers: [grid]),
                builder: (context, value, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(value)),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder card(int index) => kind == _GridKind.responsive
            ? find.byKey(ValueKey('card-a$index'))
            : find.ancestor(
                of: find.text('a$index'),
                matching: find.byType(VideoCard),
              );
        void expectColumns(int columns, double width) {
          final first = tester.getRect(card(0));
          final last = tester.getRect(card(columns - 1));
          final next = tester.getRect(card(columns));
          expect(
            first.width,
            closeTo((width - 20 * (columns - 1)) / columns, .01),
          );
          expect(first.top, last.top);
          expect(last.right, closeTo(width, .01));
          expect(next.top, greaterThan(first.bottom));
        }

        expectColumns(2, 700);
        tester.view.physicalSize = const Size(1000, 600);
        await tester.pumpAndSettle();
        expectColumns(3, 1000);
        scale.value = 2;
        await tester.pumpAndSettle();
        expectColumns(2, 1000);
        scale.value = 1;
        await tester.pumpAndSettle();
        expectColumns(3, 1000);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('queued viewport metrics check can run after viewport disposal', (
    tester,
  ) async {
    var requests = 0;
    late ScrollController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedScrollViewport(
            active: true,
            canLoadMore: true,
            contentVersion: 1,
            onLoadMore: () async => requests++,
            onRefresh: () async {},
            builder: (value) {
              controller = value;
              return CustomScrollView(
                controller: value,
                slivers: [_grid(_GridKind.responsive, _entries('a'))],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    final context = tester.element(find.byType(CustomScrollView));
    ScrollMetricsNotification(
      metrics: controller.position,
      context: context,
    ).dispatch(context);
    // Dispose before the notification's coalesced post-frame check executes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending viewport page request can complete after disposal', (
    tester,
  ) async {
    final request = Completer<void>();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedScrollViewport(
            active: true,
            canLoadMore: true,
            contentVersion: 1,
            onLoadMore: () {
              requests++;
              return request.future;
            },
            builder: (controller) => CustomScrollView(
              controller: controller,
              slivers: [const SliverToBoxAdapter(child: SizedBox(height: 10))],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox());
    request.complete();
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
}

List<String> _entries(String prefix) => List.generate(100, (i) => '$prefix$i');

Widget _grid(
  _GridKind kind,
  List<String> entries, {
  ValueChanged<String>? opened,
  ValueChanged<String>? menu,
  ValueChanged<String>? built,
}) {
  if (kind == _GridKind.responsive) {
    return SliverResponsiveCardGrid(
      itemCount: entries.length,
      itemBuilder: (_, index) {
        final id = entries[index];
        built?.call(id);
        return _Card(
          key: ValueKey('card-$id'),
          id: id,
          opened: () => opened?.call(id),
          menu: () => menu?.call(id),
        );
      },
    );
  }
  final videos = [
    for (final id in entries)
      VideoSummary(
        id: VideoId('BV${id.padLeft(10, '0')}'),
        title: id,
        coverUrl: '',
        author: '作者',
        duration: const Duration(minutes: 1),
      ),
  ];
  VideoCardMenu menuFor(VideoSummary video) {
    built?.call(video.title);
    return VideoCardMenu(
      actions: const [VideoCardMenuAction.removeWatchLater],
      onSelected: (_) => menu?.call(video.title),
    );
  }

  return kind == _GridKind.indexedVideo
      ? SliverVideoGrid.indexed(
          items: videos,
          onOpen: (index) => opened?.call(entries[index]),
          menuFor: menuFor,
        )
      : SliverVideoGrid(
          items: videos,
          onOpen: (id) =>
              opened?.call(videos.firstWhere((video) => video.id == id).title),
          menuFor: menuFor,
        );
}

final class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.id,
    required this.opened,
    required this.menu,
  });
  final String id;
  final VoidCallback opened, menu;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: Column(
      children: [
        TextButton(onPressed: opened, child: Text(id)),
        PopupMenuButton<String>(
          onSelected: (_) => menu(),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ],
    ),
  );
}
