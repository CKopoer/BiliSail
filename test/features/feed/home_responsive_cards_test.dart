import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:bilisail/shared/ui/season_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final channel in [
    HomeChannel.live,
    HomeChannel.bangumi,
    HomeChannel.guochuang,
    HomeChannel.cinema,
  ]) {
    testWidgets('${channel.name} resizes with the common video grid', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      // Widths include 8px compact or 40px desktop horizontal page padding.
      for (final (width, scale, columns) in [
        (307.0, 1.0, 1),
        (308.0, 1.0, 2),
        (320.0, 1.0, 2),
        (375.0, 1.0, 2),
        (499.0, 1.0, 2),
        (500.0, 1.0, 3),
        (600.0, 1.0, 3),
        (640.0, 1.0, 3),
        (979.0, 1.0, 3),
        (980.0, 1.0, 3),
        (1139.0, 1.0, 3),
        (1140.0, 1.0, 4),
        (1920.0, 1.0, 6),
        (447.0, 2.0, 1),
        (448.0, 2.0, 2),
        (799.0, 2.0, 2),
        (800.0, 2.0, 3),
        (375.0, 1.0, 2),
      ]) {
        tester.view.physicalSize = Size(width, 1400);
        await tester.pumpWidget(
          _app(repository, channel, channel.sections.first, scale: scale),
        );
        await tester.pumpAndSettle();

        final slots = _slots(tester);
        expect(slots.length, inInclusiveRange(columns + 1, 8));
        final first = tester.getRect(slots.first);
        final last = tester.getRect(slots[columns - 1]);
        final next = tester.getRect(slots[columns]);
        final inset = width < 600 ? 4.0 : 20.0;
        final compactGrid = width - inset * 2 < 600;
        final gap = compactGrid ? 6.0 : 20.0;
        expect(first.left, inset);
        expect(
          first.width,
          closeTo((width - inset * 2 - (columns - 1) * gap) / columns, .01),
        );
        expect(last.top, first.top);
        expect(last.right, closeTo(width - inset, .01));
        expect(next.top, closeTo(first.bottom + (compactGrid ? 16 : 24), .01));
        final cover = tester.getSize(
          find.descendant(of: slots.first, matching: find.byType(AspectRatio)),
        );
        expect(cover.width, closeTo(first.width, .01));
        expect(
          cover.aspectRatio,
          closeTo(channel == HomeChannel.live ? 16 / 9 : 3 / 4, .01),
        );
        expect(
          repository.calls,
          channel == HomeChannel.live ? 2 : 1,
          reason: 'resizing must retain the loaded page',
        );
        expect(tester.takeException(), isNull, reason: '$width, scale=$scale');
      }

      // Every subtab, including timetable, index and following, uses the grid.
      for (final section in channel.sections) {
        await tester.pumpWidget(_app(repository, channel, section));
        await tester.pumpAndSettle();
        final slots = _slots(tester);
        expect(tester.getTopLeft(slots[1]).dy, tester.getTopLeft(slots[0]).dy);
        expect(
          find.text(channel == HomeChannel.live ? '直播作者' : '更新至第12集'),
          findsNWidgets(slots.length),
        );
        if (channel != HomeChannel.live) {
          expect(find.byType(SeasonCard), findsNWidgets(slots.length));
          expect(find.text(channel.label), findsNWidgets(slots.length));
        }
        expect(tester.takeException(), isNull, reason: section);
      }
    });
  }

  for (final channel in [
    HomeChannel.bangumi,
    HomeChannel.guochuang,
    HomeChannel.cinema,
  ]) {
    testWidgets(
      '${channel.name} poster opens the requested season and episode',
      (tester) async {
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: HomeContent(
                  channel: channel,
                  section: channel == HomeChannel.cinema ? '电影' : '时间表',
                  isSignedIn: true,
                ),
              ),
            ),
            GoRoute(
              path: '/pgc/season/:seasonId',
              builder: (_, state) => Scaffold(
                body: Text(
                  '影视 ${state.pathParameters['seasonId']} '
                  '剧集 ${state.uri.queryParameters['ep']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeRepositoryProvider.overrideWithValue(
                _Repository(firstId: '9007199254740993123:17'),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SeasonCard).first);
        await tester.pumpAndSettle();
        expect(find.text('影视 9007199254740993123 剧集 17'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

List<Finder> _slots(WidgetTester tester) => tester
    .widgetList<SizedBox>(
      find.descendant(
        of: find.byType(SliverResponsiveCardGrid),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width != null &&
              widget.child is RepaintBoundary,
        ),
      ),
    )
    .map(find.byWidget)
    .toList();

Widget _app(
  _Repository repository,
  HomeChannel channel,
  String section, {
  double scale = 1,
}) => ProviderScope(
  overrides: [homeRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: scale == 1 ? BiliTheme.light() : BiliTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: HomeContent(channel: channel, section: section, isSignedIn: true),
    ),
  ),
);

final class _Repository implements HomeRepository {
  _Repository({this.firstId = '1'});

  final String firstId;
  int calls = 0;

  @override
  String get accountScope => 'guest';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    if (query.channel == HomeChannel.live && query.section == '全部分区') {
      return const HomePage([], hasMore: false);
    }
    return HomePage([
      for (var index = 0; index < 8; index++)
        HomeEntry(
          id: index == 0 ? firstId : '${index + 1}',
          title: '第${index + 1}张卡片的长标题，用于检查窄屏布局与文字缩放',
          kind: query.channel == HomeChannel.live
              ? HomeEntryKind.live
              : HomeEntryKind.season,
          coverUrl: index == 0
              ? null
              : Uri.https('example.invalid', '/cover-$index.jpg'),
          authorName: query.channel == HomeChannel.live ? '直播作者' : '',
          subtitle: '更新至第12集',
          popularityText: '8万',
          areaName: '单机游戏',
        ),
    ], hasMore: false);
  }
}
