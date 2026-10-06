import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_episode_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('section wheel and hovered thumb reach later episode groups', (
    tester,
  ) async {
    if (const bool.fromEnvironment('BILI_PGC_TABS_PREVIEW')) {
      await tester.runAsync(() async {
        await (FontLoader('HarmonyOS Sans')..addFont(
              rootBundle.load(
                'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
              ),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    const titles = ['正片', '精彩花絮', 'UP主带你看风犬', '原声MV', '特别篇', '制作访谈'];
    final season = PgcSeason(
      id: const PgcSeasonId('1'),
      title: '测试选集',
      episodes: [
        for (var i = 0; i < titles.length; i++)
          PgcEpisode(
            id: PgcEpisodeId('${i + 1}'),
            title: '第 ${i + 1} 集',
            longTitle: titles[i],
            sectionTitle: i == 0 ? null : titles[i],
            cid: '${i + 1}',
            bvid: 'BV1ab411c7mD',
          ),
      ],
    );
    final outerScroll = ScrollController();
    addTearDown(outerScroll.dispose);
    final boundaryKey = GlobalKey();
    PgcEpisode? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light().copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outerScroll,
            child: Column(
              children: [
                RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: 320,
                    child: PgcEpisodePanel(
                      season: season,
                      selected: season.episodes.first,
                      onSelect: (episode) => selected = episode,
                    ),
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tabs = find.byKey(const ValueKey('pgc-section-tabs'));
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('pgc-section-list')),
    );
    final controller = list.controller!;
    final scrollbar = find.byKey(const ValueKey('pgc-section-scrollbar'));
    expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, false);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tabs));
    await tester.pumpAndSettle();
    expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, true);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(tabs),
        scrollDelta: const Offset(0, 130),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(130, .01));
    expect(outerScroll.offset, 0);
    await tester.tap(find.byKey(const ValueKey('pgc-section-原声MV')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pgc-episode-4')), findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    final rect = tester.getRect(scrollbar);
    final thumb = Offset(rect.left + 24, rect.bottom - 2);
    await mouse.moveTo(thumb);
    await mouse.down(thumb);
    await mouse.moveTo(thumb + const Offset(240, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(130));
    await tester.tap(find.byKey(const ValueKey('pgc-section-制作访谈')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pgc-episode-6')));
    expect(selected?.id, const PgcEpisodeId('6'));

    if (const bool.fromEnvironment('BILI_PGC_TABS_PREVIEW')) {
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('artifacts/pgc-section-tabs-preview.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, false);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
