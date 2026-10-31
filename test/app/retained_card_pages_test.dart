import 'dart:convert';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/primary_switch_app.dart';

void main() {
  testWidgets(
    'deep card pages retain offsets without hidden scrolling or growth',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = PrimarySwitchFixture(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGNgAAIAAAUAAarVyFEAAAAASUVORK5CYII=',
        ),
        feed: SwitchFeedRepository(covers: false),
        home: SwitchHomeRepository(covers: false),
      );
      try {
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        ScrollableState activeList() => tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .firstWhere(
              (state) =>
                  state.position.axis == Axis.vertical &&
                  state.widget.controller is HeaderScrollController &&
                  (state.context
                          .getInheritedWidgetOfExactType<WorkspaceActivity>()
                          ?.active ??
                      true),
            );
        Future<void> select(String page) async {
          await tester.tap(find.byKey(ValueKey('workspace-bottom-$page')));
          await tester.pumpAndSettle(
            const Duration(milliseconds: 16),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
        }

        final positions = <String, ScrollPosition>{};
        final offsets = <String, double>{};
        for (final page in ['home', 'dynamic', 'mine']) {
          await select(page);
          if (page == 'dynamic') {
            await tester.tap(
              find.byKey(const ValueKey('channel-videoDynamic')),
            );
          } else if (page == 'mine') {
            await tester.tap(
              find.byKey(const ValueKey('account-tab-watchLater')),
            );
          }
          await tester.pumpAndSettle(
            const Duration(milliseconds: 16),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          final position = activeList().position;
          positions[page] = position;
          for (var i = 0; i < 30; i++) {
            position.jumpTo(position.pixels + 360);
            await tester.pump();
          }
          await tester.pumpAndSettle(
            const Duration(milliseconds: 16),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          offsets[page] = position.pixels;
        }
        for (var round = 0; round < 2; round++) {
          for (final page in ['home', 'dynamic', 'mine']) {
            await select(page);
            expect(activeList().position, same(positions[page]));
            expect(activeList().position.pixels, offsets[page]);
            await tester.fling(
              find.byWidget(activeList().widget),
              const Offset(0, -200),
              4000,
            );
            await tester.pump(const Duration(milliseconds: 32));
            final next = page == 'home' ? 'dynamic' : 'home';
            await tester.tap(find.byKey(ValueKey('workspace-bottom-$next')));
            await tester.pump();
            final saved = positions[page]!.pixels;
            await tester.pumpAndSettle(
              const Duration(milliseconds: 16),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );
            expect(positions[page]!.pixels, saved);
            expect(positions[page]!.isScrollingNotifier.value, isFalse);
            offsets[page] = saved;
            // 900 loaded summaries across three retained lists, only nearby rows mounted.
            expect(
              find.byType(VideoCard, skipOffstage: false).evaluate().length,
              lessThan(65),
            );
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await fixture.dispose();
      }
    },
  );
}
