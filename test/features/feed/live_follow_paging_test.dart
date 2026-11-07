import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'live follows retain the first snapshot until load more is clicked',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: Scaffold(
              body: HomeContent(
                channel: HomeChannel.live,
                section: '我的关注',
                isSignedIn: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.pages, [1]);
      expect(find.text('主播 1'), findsOneWidget);
      expect(find.text('加载更多'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.pages, [1]);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(repository.pages, [1, 2]);
      expect(find.text('主播 1'), findsOneWidget);
      expect(find.text('主播 2'), findsOneWidget);
      expect(find.text('加载更多'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Repository implements HomeRepository {
  final pages = <int>[];
  @override
  String get accountScope => 'user:1';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    pages.add(page);
    return HomePage([
      HomeEntry(id: '$page', title: '主播 $page', kind: HomeEntryKind.live),
    ], hasMore: page < 2);
  }
}
