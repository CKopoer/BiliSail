import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_discovery_controller.dart';
import 'package:bilisail/features/search/domain/search_discovery_repository.dart';
import 'package:bilisail/features/search/presentation/search_entry_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'inline search slides to center, blurs tabs, follows field and closes with Escape',
    (tester) async {
      final calls = <String>[];
      await _mount(tester, width: 1200, inline: true, calls: calls);
      final field = find.byKey(const ValueKey('workspace-search'));
      final initial = tester.getRect(field);
      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getRect(field).left, greaterThan(initial.left));
      await tester.pumpAndSettle();
      expect(tester.getCenter(field).dx, closeTo(600, 1));
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
      await tester.pumpAndSettle();
      expect(find.text('搜索历史'), findsNothing);
      expect(tester.getRect(field), initial);
    },
  );

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
      expect(find.text('搜索历史'), findsNothing);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '查询热搜'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('outside')));
      await tester.pumpAndSettle();
      expect(find.text('搜索历史'), findsNothing);
    },
  );

  testWidgets(
    'mobile opens independent search page; keyboard insets scroll; submit saves and returns',
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
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '手机搜索'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(calls, ['手机搜索']);
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
      expect(find.widgetWithText(ActionChip, '未提交的草稿'), findsNothing);
      expect(calls, isEmpty);
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
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });

  final text = TextEditingController();
  addTearDown(text.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchDiscoveryRepositoryProvider.overrideWithValue(_Repository()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              SearchEntryHeader(
                leading: const SizedBox(width: 44, child: Icon(Icons.person)),
                trailing: const SizedBox(width: 8),
                controller: text,
                onSearch: calls.add,
                inlineNavigation: inline,
                navigation: const Text('推荐分类'),
              ),
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
  Future<List<SearchTrend>> loadTrending(
    RequestCancellation cancellation,
  ) async => [const SearchTrend(keyword: '查询热搜', label: '展示热搜')];
}
