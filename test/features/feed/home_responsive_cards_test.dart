import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      // Widths include the home page's 40 logical pixels of horizontal padding.
      for (final (width, scale, columns) in [
        (339.0, 1.0, 1),
        (340.0, 1.0, 2),
        (375.0, 1.0, 2),
        (979.0, 1.0, 2),
        (980.0, 1.0, 3),
        (1920.0, 1.0, 5),
        (479.0, 2.0, 1),
        (480.0, 2.0, 2),
        (375.0, 1.0, 2),
      ]) {
        tester.view.physicalSize = Size(width, 1400);
        await tester.pumpWidget(
          _app(repository, channel, channel.sections.first, scale: scale),
        );
        await tester.pumpAndSettle();

        final slots = _slots(tester);
        expect(slots.length, inInclusiveRange(columns + 1, 6));
        final first = tester.getRect(slots.first);
        final last = tester.getRect(slots[columns - 1]);
        final next = tester.getRect(slots[columns]);
        expect(first.left, 20);
        expect(
          first.width,
          closeTo((width - 40 - (columns - 1) * 20) / columns, .01),
        );
        expect(last.top, first.top);
        expect(last.right, closeTo(width - 20, .01));
        expect(next.top, closeTo(first.bottom + 24, .01));
        final cover = tester.getSize(
          find.descendant(of: slots.first, matching: find.byType(AspectRatio)),
        );
        expect(cover.width, closeTo(first.width, .01));
        expect(cover.aspectRatio, closeTo(16 / 9, .01));
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
        expect(tester.takeException(), isNull, reason: section);
      }
    });
  }
}

List<Finder> _slots(WidgetTester tester) => tester
    .widgetList<Row>(
      find.descendant(
        of: find.byType(SliverResponsiveCardGrid),
        matching: find.byWidgetPredicate(
          (widget) => widget is Row && widget.spacing == 20,
        ),
      ),
    )
    .expand((row) => row.children)
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
      for (var index = 0; index < 6; index++)
        HomeEntry(
          id: '${index + 1}',
          title: '第${index + 1}张卡片的长标题，用于检查窄屏布局与文字缩放',
          kind: query.channel == HomeChannel.live
              ? HomeEntryKind.live
              : HomeEntryKind.season,
          coverUrl: Uri.https('example.invalid', '/cover-$index.jpg'),
          authorName: query.channel == HomeChannel.live ? '直播作者' : '',
          subtitle: '更新至第12集',
          popularityText: '8万',
          areaName: '单机游戏',
        ),
    ], hasMore: false);
  }
}
