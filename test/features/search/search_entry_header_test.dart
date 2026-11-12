import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_discovery_controller.dart';
import 'package:bilisail/features/search/domain/search_discovery_repository.dart';
import 'package:bilisail/features/search/presentation/search_entry_header.dart';
import 'package:bilisail/features/search/presentation/search_history_chip.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 700.0, 1200.0]) {
    testWidgets('opening search preserves page scroll at width $width', (
      tester,
    ) async {
      final mobile = width < 600;
      late ScrollController listController;
      await _mount(
        tester,
        width: width,
        inline: width >= 760,
        calls: [],
        bodyBuilder: (header) => ScrollHeaderLayout(
          enabled: mobile,
          header: mobile ? header : const SizedBox.shrink(),
          child: Column(
            children: [
              if (!mobile) header,
              Expanded(
                child: PagedScrollViewport(
                  active: true,
                  canLoadMore: false,
                  contentVersion: 0,
                  onLoadMore: () async {},
                  builder: (controller) {
                    listController = controller;
                    return ListView.builder(
                      controller: controller,
                      itemExtent: 60,
                      itemCount: 100,
                      itemBuilder: (_, index) => Text('row $index'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      // Leave the narrow header partly visible so its field can be tapped.
      if (mobile) {
        nested.outerController.jumpTo(12);
      } else {
        listController.jumpTo(480);
      }
      await tester.pumpAndSettle();
      final outerOffset = nested.outerController.offset;
      final innerOffset = listController.offset;
      final row = find.text(mobile ? 'row 0' : 'row 10');
      final rowRect = tester.getRect(row);
      final field = find.byKey(const ValueKey('workspace-search'));
      final fieldTop = tester.getTopLeft(field).dy;

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(nested.outerController.offset, outerOffset);
      expect(listController.offset, innerOffset);
      if (mobile) {
        expect(
          find.byKey(const ValueKey('search-discovery-page')),
          findsOneWidget,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.enterText(
          find.byKey(const ValueKey('search-page-input')),
          '搜索草稿',
        );
        await tester.pumpAndSettle();
        expect(nested.outerController.offset, outerOffset);
        expect(listController.offset, innerOffset);
        tester.view.resetViewInsets();
        await tester.pageBack();
      } else {
        expect(find.text('搜索历史'), findsOneWidget);
        expect(tester.getRect(row), rowRect);
        expect(tester.getTopLeft(field).dy, fieldTop);
        await tester.enterText(field, '保留页面位置' * 20);
        await tester.pumpAndSettle();
        expect(nested.outerController.offset, outerOffset);
        expect(listController.offset, innerOffset);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(nested.outerController.offset, outerOffset);
      expect(listController.offset, innerOffset);
      expect(tester.getRect(row), rowRect);
      expect(tester.getTopLeft(field).dy, fieldTop);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'inline search slides to center, blurs tabs, follows field and closes with Escape',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 1200, inline: true, calls: calls);
      final field = find.byKey(const ValueKey('workspace-search'));
      final account = find.byKey(const ValueKey('search-account'));
      final initial = tester.getRect(field);
      final initialAccount = tester.getRect(account);
      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getRect(field).left, greaterThan(initial.left));
      expect(tester.getRect(account), initialAccount);
      expect(account.hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.getCenter(field).dx, closeTo(600, 1));
      expect(tester.getRect(account), initialAccount);
      expect(account.hitTestable(), findsOneWidget);
      expect(find.text('搜索历史'), findsOneWidget);
      expect(find.text('热搜'), findsOneWidget);
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(
                    of: find.text('推荐分类'),
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        isTrue,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('search-discovery-panel')))
            .dx,
        closeTo(tester.getTopLeft(field).dx, 1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getRect(account), initialAccount);
      expect(account.hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('搜索历史'), findsNothing);
      expect(tester.getRect(field), initial);
      expect(tester.getRect(account), initialAccount);
    },
  );

  for (final width in [760.0, 1600.0]) {
    testWidgets(
      'inline search keeps account visible and clickable at width $width',
      (tester) async {
        var accountTaps = 0;
        await _mount(
          tester,
          width: width,
          inline: true,
          calls: [],
          leadingWidth: 88,
          onAccountTap: () => accountTaps++,
        );
        final field = find.byKey(const ValueKey('workspace-search'));
        final account = find.byKey(const ValueKey('search-account'));
        final initialAccount = tester.getRect(account);
        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(tester.getRect(account), initialAccount);
        expect(tester.getCenter(field).dx, closeTo(width / 2, 1));
        expect(tester.getRect(field).left, greaterThan(initialAccount.right));
        await tester.tap(account);
        await tester.pumpAndSettle();
        expect(accountTaps, 1);
        expect(find.text('搜索历史'), findsNothing);
        expect(tester.getRect(account), initialAccount);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'separate row stays in place; history expands and clears; hot label searches keyword',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 700, inline: false, calls: calls);
      final field = find.byKey(const ValueKey('workspace-search'));
      final initial = tester.getRect(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.getRect(field), initial);
      expect(find.text('历史11'), findsNothing);
      await tester.tap(find.text('展开更多'));
      await tester.pumpAndSettle();
      expect(find.text('历史11'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('暂无搜索历史'), findsOneWidget);
      await tester.tap(find.text('展示热搜'));
      await tester.pumpAndSettle();
      expect(calls, ['查询热搜']);
      expect(tester.widget<TextField>(field).controller!.text, '查询热搜');
      expect(find.text('搜索历史'), findsNothing);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey(('search-history', '查询热搜'))),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('outside')));
      await tester.pumpAndSettle();
      expect(find.text('搜索历史'), findsNothing);
    },
  );

  testWidgets(
    'mobile retains the submitted query for editing and searching again',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 390, inline: false, calls: calls);
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search-discovery-page')),
        findsOneWidget,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(
        find.byKey(const ValueKey('search-page-input')),
        ' 手机搜索 ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(calls, ['手机搜索']);
      expect(find.byKey(const ValueKey('search-discovery-page')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('workspace-search')))
            .controller!
            .text,
        '手机搜索',
      );
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('search-page-input'));
      expect(tester.widget<TextField>(input).controller!.text, '手机搜索');
      expect(
        ProviderScope.containerOf(tester.element(input))
            .read(searchDiscoveryControllerProvider)
            .history,
        contains('手机搜索'),
      );
      await tester.enterText(input, '手机搜索 教程');
      await tester.tap(find.widgetWithText(TextButton, '搜索'));
      await tester.pumpAndSettle();
      expect(calls, ['手机搜索', '手机搜索 教程']);
      expect(find.byKey(const ValueKey('search-discovery-page')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('workspace-search')))
            .controller!
            .text,
        '手机搜索 教程',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short desktop viewport and large text keep panel within window',
    (tester) async {
      await _mount(
        tester,
        width: 800,
        inline: true,
        calls: [],
        height: 320,
        scale: 2,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('search-discovery-panel')),
      );
      expect(panel.bottom, lessThanOrEqualTo(320));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancelled mobile input remains a draft and does not create history',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 390, inline: false, calls: calls);
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-page-input')),
        '未提交的草稿',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('search-page-input')))
            .controller
            ?.text,
        '未提交的草稿',
      );
      expect(
        find.byKey(const ValueKey(('search-history', '未提交的草稿'))),
        findsNothing,
      );
      expect(calls, isEmpty);
    },
  );

  testWidgets(
    'hover and long press reveal a corner delete button without searching',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 1200, inline: true, calls: calls);
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey(('search-history', '历史0')));
      final remove = find.byTooltip('删除历史记录：历史0');
      expect(remove, findsNothing);
      final rect = tester.getRect(first);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1100, 700));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(rect.center);
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      expect(tester.getRect(first), rect);
      expect(tester.getCenter(remove).dx, greaterThan(rect.center.dx));
      expect(tester.getCenter(remove).dy, lessThan(rect.center.dy));
      await mouse.moveTo(const Offset(1100, 700));
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      await tester.longPress(first);
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(first, findsNothing);
      expect(calls, isEmpty);
      expect(find.text('搜索历史'), findsOneWidget);
      expect(find.byType(SearchHistoryChip), findsNWidgets(10));
    },
  );

  testWidgets(
    'privacy toggle skips new history; candidate and history clicks retain the query',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 1200, inline: true, calls: calls);
      final field = find.byKey(const ValueKey('workspace-search'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-history-recording')));
      await tester.pumpAndSettle();
      expect(find.text('已关闭历史记录，新搜索不会保存'), findsOneWidget);
      await tester.enterText(field, '新搜索');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('search-suggestion', '新搜索建议'))),
      );
      await tester.pumpAndSettle();
      expect(calls, ['新搜索建议']);
      expect(tester.widget<TextField>(field).controller!.text, '新搜索建议');
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey(('search-history', '新搜索建议'))),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('search-history-recording')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(('search-history', '历史2'))));
      await tester.pumpAndSettle();
      expect(calls, ['新搜索建议', '历史2']);
      expect(tester.widget<TextField>(field).controller!.text, '历史2');
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SearchHistoryChip>(find.byType(SearchHistoryChip))
            .first
            .query,
        '历史2',
      );
    },
  );

  testWidgets(
    'keyboard submit retains an editable query; blank submit retains open search',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 1200, inline: true, calls: calls);
      final field = find.byKey(const ValueKey('workspace-search'));
      await tester.enterText(field, ' 键盘搜索 ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(calls, ['键盘搜索']);
      expect(tester.widget<TextField>(field).controller!.text, '键盘搜索');
      expect(
        tester.widget<TextField>(field).controller!.selection,
        TextSelection.collapsed(offset: '键盘搜索'.length),
      );
      await tester.enterText(field, '键盘搜索 教程');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(calls, ['键盘搜索', '键盘搜索 教程']);
      expect(tester.widget<TextField>(field).controller!.text, '键盘搜索 教程');
      await tester.enterText(field, '   ');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(calls, ['键盘搜索', '键盘搜索 教程']);
      expect(find.text('搜索历史'), findsOneWidget);
    },
  );
}

Future<void> _mount(
  WidgetTester tester, {
  required double width,
  required bool inline,
  required List<String> calls,
  double height = 800,
  double scale = 1,
  double leadingWidth = 44,
  VoidCallback? onAccountTap,
  Widget Function(Widget header)? bodyBuilder,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });

  final text = TextEditingController();
  final recording = StateProvider<bool>((ref) => true);
  addTearDown(text.dispose);
  final header = SearchEntryHeader(
    leading: SizedBox(
      width: leadingWidth,
      child: IconButton(
        key: const ValueKey('search-account'),
        onPressed: onAccountTap ?? () {},
        icon: const Icon(Icons.person),
      ),
    ),
    trailing: const SizedBox(width: 8),
    controller: text,
    onSearch: calls.add,
    inlineNavigation: inline,
    navigation: const Text('推荐分类'),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchDiscoveryRepositoryProvider.overrideWithValue(_Repository()),
        searchHistoryRecordingProvider.overrideWith(
          (ref) => ref.watch(recording),
        ),
        searchHistoryRecordingWriterProvider.overrideWith(
          (ref) =>
              (value) async => ref.read(recording.notifier).state = value,
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body:
              bodyBuilder?.call(header) ??
              Column(
                children: [
                  header,
                  const Expanded(child: SizedBox()),
                  TextButton(
                    key: const ValueKey('outside'),
                    onPressed: () {},
                    child: const Text('其他内容'),
                  ),
                ],
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Repository implements SearchDiscoveryRepository {
  List<String> history = List.generate(12, (i) => '历史$i');
  @override
  Future<List<String>> loadHistory(String scope) async => history;
  @override
  Future<void> saveHistory(String scope, List<String> history) async {
    this.history = history;
  }

  @override
  Future<List<String>> loadSuggestions(
    String query,
    RequestCancellation cancellation,
  ) async => ['$query建议'];

  @override
  Future<List<SearchTrend>> loadTrending(
    RequestCancellation cancellation,
  ) async => [const SearchTrend(keyword: '查询热搜', label: '展示热搜')];
}
