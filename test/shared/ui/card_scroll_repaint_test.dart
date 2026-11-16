import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/profile/presentation/profile_video_card.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

enum _CardKind { grid, profile, cover }

void main() {
  for (final kind in _CardKind.values) {
    testWidgets('$kind suppresses repeated hover during scrolling and '
        'restores stationary hover', (tester) async {
      final controller = ScrollController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      final video = _video(0);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: SizedBox(
                height: 1600,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: switch (kind) {
                      _CardKind.grid => VideoCard(video: video, onTap: () {}),
                      _CardKind.profile => ProfileVideoCard(
                        video: video,
                        onTap: () {},
                      ),
                      _CardKind.cover => SizedBox(
                        height: 180,
                        child: VideoCardCover(
                          video: video,
                          child: const ColoredBox(color: Colors.blue),
                        ),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final scale = find.byKey(const ValueKey('video-card-cover-scale'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(scale));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(scale).scale, 1.05);
      final scrolling = controller.animateTo(
        25,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linear,
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scale).scale, 1);
      expect(tester.widget<AnimatedScale>(scale).duration, Duration.zero);
      var cardBuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is VideoCard ||
            element.widget is ProfileVideoCard ||
            element.widget is VideoCardCover) {
          cardBuilds++;
        }
      };
      try {
        for (var frame = 0; frame < 4; frame++) {
          await mouse.moveTo(const Offset(700, 450));
          await mouse.moveTo(tester.getCenter(scale));
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.widget<AnimatedScale>(scale).scale, 1);
        }
        expect(cardBuilds, 0);
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      await tester.pump(const Duration(milliseconds: 350));
      await scrolling;
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(scale).scale, 1.05);
      expect(tester.takeException(), isNull);
    });
  }

  for (final lazy in [false, true]) {
    testWidgets('hovering one ${lazy ? 'sliver' : 'wrap'} grid card does not '
        'repaint its neighbour', (tester) async {
      Widget card(int i) => VideoCard(video: _video(i), onTap: () {});
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 660,
                child: lazy
                    ? CustomScrollView(
                        slivers: [
                          SliverResponsiveCardGrid(
                            itemCount: 4,
                            itemBuilder: (_, i) => card(i),
                          ),
                        ],
                      )
                    : ResponsiveCardGrid(
                        children: [for (var i = 0; i < 4; i++) card(i)],
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var neighbourPaints = 0;
      var hoveredPaints = 0;
      debugOnProfilePaint = (render) {
        if (render is! RenderParagraph) return;
        if (render.text.toPlainText() == '视频 1') neighbourPaints++;
        if (render.text.toPlainText() == '视频 0') hoveredPaints++;
      };
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(100, 60));
        for (var frame = 0; frame < 15; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(hoveredPaints, greaterThan(0));
        expect(neighbourPaints, 0);
      } finally {
        debugOnProfilePaint = null;
        await mouse.removePointer();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shrinking a scrolling cover defers idle hover until after '
      'viewport layout', (tester) async {
    var height = 1600.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light().copyWith(platform: TargetPlatform.windows),
        scrollBehavior: const SmoothScrollBehavior(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SingleChildScrollView(
                child: SizedBox(
                  height: height,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 320,
                      height: 180,
                      child: VideoCardCover(
                        video: _video(0),
                        child: const ColoredBox(color: Colors.blue),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 60));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(100, 60),
        scrollDelta: Offset(0, 120),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    update(() => height = 300);
    await tester.pumpAndSettle();
    final scale = find.byKey(const ValueKey('video-card-cover-scale'));
    expect(tester.widget<AnimatedScale>(scale).scale, 1.05);
    expect(tester.takeException(), isNull);
  });
}

VideoSummary _video(int i) => VideoSummary(
  id: VideoId('BV${i.toString().padLeft(10, '0')}'),
  title: '视频 $i',
  coverUrl: '',
  author: 'UP 主',
  duration: const Duration(minutes: 3),
);
