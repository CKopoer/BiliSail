import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/primary_switch_app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile deeply scrolled retained card pages', (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 270);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final fixture = PrimarySwitchFixture(
      data!.buffer.asUint8List(),
      home: _Home(),
    );
    image.dispose();
    picture.dispose();
    await tester.pumpWidget(fixture.app);
    Future<void> settle() async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
    }

    ScrollableState visibleList() => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere(
          (state) =>
              state.position.axis == Axis.vertical &&
              (state.context
                      .getInheritedWidgetOfExactType<WorkspaceActivity>()
                      ?.active ??
                  true),
        );
    Finder listFinder() => find.byWidget(visibleList().widget);
    // The liquid dock exposes no per-destination keys; locate tabs by label.
    const dockLabels = {'home': '首页', 'dynamic': '动态', 'mine': '我的'};
    Future<void> select(String page) async {
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('workspace-bottom-navigation')),
              matching: find.text(dockLabels[page]!),
            )
            .first,
      );
      await tester.pump();
    }

    final timings = <ui.FrameTiming>[];
    final samples = <Map<String, Object>>[];
    void collect(List<ui.FrameTiming> frames) => timings.addAll(frames);
    await settle();
    // Keep separate cover URLs per page to exercise bounded decoded caches.
    for (final page in ['home', 'dynamic', 'mine']) {
      debugPrint('retained-cards: prepare $page');
      await select(page);
      await settle();
      if (page == 'dynamic') {
        await tester.tap(find.byKey(const ValueKey('channel-videoDynamic')));
      } else if (page == 'mine') {
        await tester.tap(find.byKey(const ValueKey('account-tab-watchLater')));
      }
      await settle();
      for (var i = 0; i < 35; i++) {
        final position = visibleList().position;
        position.jumpTo(position.pixels + 360);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle();
    }
    binding.addTimingsCallback(collect);
    try {
      for (var round = 0; round < 6; round++) {
        for (final page in ['home', 'dynamic', 'mine']) {
          debugPrint('retained-cards: sample $round $page');
          await select(page);
          await settle();
          final outgoing = visibleList().position;
          timings.clear();
          await tester.fling(listFinder(), const Offset(0, -360), 5000);
          debugPrint('retained-cards: flung $page');
          await tester.pump(const Duration(milliseconds: 32));
          final next = switch (page) {
            'home' => 'dynamic',
            'dynamic' => 'mine',
            _ => 'home',
          };
          await select(next);
          debugPrint('retained-cards: selected $next');
          final saved = outgoing.pixels;
          await tester.fling(listFinder(), const Offset(0, -120), 2500);
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          samples.add({
            'target': page,
            'round': round,
            'hiddenScrollDistance': outgoing.pixels - saved,
            'mountedCards': find
                .byType(VideoCard, skipOffstage: false)
                .evaluate()
                .length,
            'uiUs': timings.map((f) => f.buildDuration.inMicroseconds).toList(),
            'rasterUs': timings
                .map((f) => f.rasterDuration.inMicroseconds)
                .toList(),
          });
          outgoing.jumpTo(outgoing.pixels);
          final current = visibleList().position;
          current.jumpTo(current.pixels);
          await settle();
        }
      }
    } finally {
      binding.removeTimingsCallback(collect);
    }
    binding.reportData = {
      'retainedCards': {
        'label': const String.fromEnvironment(
          'SWITCH_LABEL',
          defaultValue: 'current',
        ),
        'samples': samples,
        'refreshRate':
            ui.PlatformDispatcher.instance.views.first.display.refreshRate,
      },
    };
    expect(
      samples.every((sample) => (sample['uiUs']! as List).isNotEmpty),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await fixture.dispose();
  });
}

class _Home extends SwitchHomeRepository {
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    reads.update(query.channel.name, (value) => value + 1, ifAbsent: () => 1);
    return HomePage([
      for (var i = 0; i < 300; i++)
        HomeEntry(
          id: '$i',
          title: '${query.channel.label}视频 $i',
          kind: HomeEntryKind.video,
          bvid: 'BV1abc${i.toString().padLeft(6, '0')}',
          coverUrl: Uri.parse(
            'https://i0.hdslb.com/${query.channel.name}-$i.png',
          ),
          authorName: '测试作者',
          duration: const Duration(minutes: 3),
        ),
    ], hasMore: false);
  }
}
