import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_results.dart';
import 'package:bilisail/shared/ui/live_room_tile.dart';
import 'package:bilisail/shared/ui/responsive_layout_scope.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final (width, columns) in [(360.0, 2), (1280.0, 4)]) {
    testWidgets('search live rooms share the channel grid at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: CustomScrollView(
                slivers: [
                  SearchResults(
                    items: [
                      for (var i = 1; i <= columns + 1; i++)
                        SearchLiveEntry(
                          id: RoomId('$i'),
                          title: '直播标题$i',
                          author: '主播$i',
                          authorId: UserId('$i'),
                          online: 12345,
                          isLive: i.isEven,
                        ),
                    ],
                    category: SearchCategory.live,
                    query: '标题',
                    onCategory: (_) {},
                  ),
                ],
              ),
            ),
          ),
          for (final path in ['/user/:id', '/live/:id'])
            GoRoute(path: path, builder: (_, state) => Text(state.uri.path)),
        ],
      );
      addTearDown(router.dispose);
      final ratio = ValueNotifier(CardCoverRatio.widescreen);
      addTearDown(ratio.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => ValueListenableBuilder(
            valueListenable: ratio,
            child: child,
            builder: (context, value, child) => ResponsiveLayoutScope(
              settings: ResponsiveLayoutSettings.defaults(
                cardCoverRatio: value,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tiles = find.byType(LiveRoomTile);
      final first = tester.getRect(tiles.first);
      expect(
        tester.getTopRight(tiles.at(columns - 1)),
        Offset(width, first.top),
      );
      expect(
        tester.getTopLeft(tiles.at(columns)).dy,
        greaterThan(first.bottom),
      );
      expect(find.text('♨ 1.2万'), findsNWidgets(columns + 1));
      expect(find.text('未开播'), findsWidgets);
      expect(find.text('直播中'), findsWidgets);
      final cover = find.descendant(
        of: tiles.first,
        matching: find.byType(AspectRatio),
      );
      final wideCover = tester.getSize(cover);
      expect(wideCover.aspectRatio, closeTo(16 / 9, .001));
      ratio.value = CardCoverRatio.standard;
      await tester.pumpAndSettle();
      final standardCover = tester.getSize(cover);
      expect(standardCover.aspectRatio, closeTo(4 / 3, .001));
      expect(standardCover.width, wideCover.width);
      expect(tester.getSize(tiles.first).width, first.width);
      expect(
        tester.getTopRight(tiles.at(columns - 1)),
        Offset(width, first.top),
      );
      expect(
        tester.getTopLeft(tiles.at(columns)).dy,
        greaterThan(tester.getBottomLeft(tiles.first).dy),
      );
      await tester.tap(find.text('主播1'));
      await tester.pumpAndSettle();
      expect(find.text('/user/1'), findsOneWidget);
      router.go('/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('直播标题2', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('/live/2'), findsOneWidget);
    });
  }
  testWidgets(
    'live popularity uses the shared video count units without thousands',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final (text, label) in [
          ('0', '0'),
          ('999', '999'),
          ('1000', '1000'),
          ('1234', '1234'),
          ('9999', '9999'),
          ('10000', '1.0万'),
          ('12345', '1.2万'),
          ('100000000', '1.0亿'),
          ('123456789', '1.2亿'),
        ]) {
          await tester.pumpWidget(_app(text));
          expect(find.text('♨ $label'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape('♨ $label'))),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'live popularity preserves server abbreviations and unknown text',
    (tester) async {
      for (final text in ['1.23千', '8万', '2.34亿', '—', '未知']) {
        await tester.pumpWidget(_app(text));
        expect(find.text('♨ $text'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('live popularity omits missing or blank count', (tester) async {
    for (final text in ['', '   ']) {
      await tester.pumpWidget(_app(text));
      expect(find.textContaining('♨'), findsNothing);
      expect(find.text('直播标题'), findsOneWidget);
      expect(find.text('单机游戏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compact live popularity retains narrow card navigation', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      _app('12345', width: 140, scale: 2, onTap: () => opens++),
    );
    expect(find.text('♨ 1.2万'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('直播标题'));
    expect(opens, 1);
  });
}

Widget _app(
  String popularity, {
  double width = 320,
  double scale = 1,
  VoidCallback? onTap,
}) => MaterialApp(
  theme: BiliTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Center(
        child: SizedBox(
          width: width,
          child: LiveRoomCard(
            entry: HomeEntry(
              id: '7777',
              title: '直播标题',
              kind: HomeEntryKind.live,
              authorName: '直播作者',
              popularityText: popularity,
              areaName: '单机游戏',
            ),
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  ),
);
