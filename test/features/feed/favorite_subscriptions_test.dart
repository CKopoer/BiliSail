import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = (
  channel: HomeChannel.favorites,
  section: '我的收藏与订阅',
  scope: 'user:7',
  folderId: null,
);
const _folder = HomeEntry(id: '42', title: '收藏夹A', kind: HomeEntryKind.folder);
const _collection = HomeEntry(
  id: '42',
  title: '流行',
  kind: HomeEntryKind.collection,
  contentCount: 38,
  viewCount: 1635000,
);
const _entries = [_folder, _collection];

void main() {
  test(
    'unsubscribe is explicit, single flight and identifies kind plus ID',
    () async {
      final (container, repo, controller) = await _setup();
      expect(repo.writes, isEmpty);
      final result = controller.unsubscribeFavorite(_collection);
      expect(await controller.unsubscribeFavorite(_collection), isFalse);
      expect(repo.writes, hasLength(1));
      expect(container.read(homeControllerProvider(_query)).unsubscribing, {
        (HomeEntryKind.collection, '42'),
      });
      repo.writes.single.result.complete();
      expect(await result, isTrue);
      expect(
        container.read(homeControllerProvider(_query)).items.requireValue,
        [_folder],
      );
      expect(
        container.read(homeControllerProvider(_query)).unsubscribing,
        isEmpty,
      );
      expect(await controller.unsubscribeFavorite(_collection), isFalse);
    },
  );

  test('simultaneous removals preserve the other pending operation', () async {
    final (container, repo, controller) = await _setup();
    final first = controller.unsubscribeFavorite(_folder);
    final second = controller.unsubscribeFavorite(_collection);
    repo.writes.first.result.complete();
    expect(await first, isTrue);
    expect(container.read(homeControllerProvider(_query)).unsubscribing, {
      (HomeEntryKind.collection, '42'),
    });
    repo.writes.last.result.complete();
    expect(await second, isTrue);
    expect(
      container.read(homeControllerProvider(_query)).items.requireValue,
      isEmpty,
    );
  });

  test(
    'failed write preserves cards and only retries on a new explicit action',
    () async {
      final (container, repo, controller) = await _setup();
      final result = controller.unsubscribeFavorite(_collection);
      final expectation = expectLater(result, throwsA(isA<AppFailure>()));
      repo.writes.single.result.completeError(
        const AppFailure(AppFailureKind.timeout, 'fixture'),
      );
      await expectation;
      expect(
        container.read(homeControllerProvider(_query)).items.requireValue,
        _entries,
      );
      expect(
        container.read(homeControllerProvider(_query)).unsubscribing,
        isEmpty,
      );
      expect(repo.writes, hasLength(1));
      final retry = controller.unsubscribeFavorite(_collection);
      repo.writes.last.result.complete();
      expect(await retry, isTrue);
    },
  );

  test(
    'late pagination cannot resurrect a removal or skip a shifted page',
    () async {
      final (container, repo, controller) = await _setup(hasMore: true);
      final more = controller.loadMore();
      final stalePage = repo.reads.last;
      expect(stalePage.page, 2);
      final result = controller.unsubscribeFavorite(_collection);
      repo.writes.single.result.complete();
      expect(await result, isTrue);
      expect(stalePage.cancellation.isCancelled, isTrue);
      stalePage.result.complete(const HomePage(_entries, hasMore: false));
      await more;
      expect(
        container.read(homeControllerProvider(_query)).items.requireValue,
        [_folder],
      );
      final resumed = controller.loadMore();
      expect(repo.reads.last.page, 1);
      repo.reads.last.result.complete(
        const HomePage([
          ..._entries,
          HomeEntry(id: '43', title: '下一项', kind: HomeEntryKind.collection),
        ], hasMore: false),
      );
      await resumed;
      expect(
        container
            .read(homeControllerProvider(_query))
            .items
            .requireValue
            .map((e) => e.title),
        ['收藏夹A', '下一项'],
      );
    },
  );

  test(
    'refresh during a write retains busy state and discards stale data',
    () async {
      final (container, repo, controller) = await _setup();
      final result = controller.unsubscribeFavorite(_collection);
      final refreshed = controller.refresh();
      final stalePage = repo.reads.last;
      expect(container.read(homeControllerProvider(_query)).unsubscribing, {
        (HomeEntryKind.collection, '42'),
      });
      repo.writes.single.result.complete();
      expect(await result, isTrue);
      stalePage.result.complete(const HomePage(_entries, hasMore: false));
      await refreshed;
      expect(
        container.read(homeControllerProvider(_query)).items.requireValue,
        [_folder],
      );
      // A later explicit refresh is authoritative, including external resubscription.
      final authoritative = controller.refresh();
      repo.reads.last.result.complete(const HomePage(_entries, hasMore: false));
      await authoritative;
      expect(
        container.read(homeControllerProvider(_query)).items.requireValue,
        _entries,
      );
    },
  );

  test('account switch suppresses late completion', () async {
    final (container, repo, controller) = await _setup();
    final result = controller.unsubscribeFavorite(_collection);
    repo.scope = 'user:8';
    repo.writes.single.result.complete();
    expect(await result, isFalse);
    expect(
      container.read(homeControllerProvider(_query)).items.requireValue,
      _entries,
    );
  });

  test(
    'reconciling many retained pages does not report stalled pagination',
    () async {
      final (container, repo, controller) = await _setup(hasMore: true);
      for (var page = 2; page <= 5; page++) {
        final more = controller.loadMore();
        repo.reads.last.result.complete(
          HomePage([
            HomeEntry(
              id: '$page',
              title: '合集$page',
              kind: HomeEntryKind.collection,
            ),
          ], hasMore: page < 5),
        );
        await more;
      }
      final result = controller.unsubscribeFavorite(_collection);
      repo.writes.single.result.complete();
      expect(await result, isTrue);
      for (var page = 1; page <= 5; page++) {
        final more = controller.loadMore();
        expect(repo.reads.last.page, page);
        repo.reads.last.result.complete(
          HomePage(
            page == 1
                ? [_folder]
                : [
                    HomeEntry(
                      id: '$page',
                      title: '合集$page',
                      kind: HomeEntryKind.collection,
                    ),
                  ],
            hasMore: page < 5,
          ),
        );
        await more;
        expect(
          container.read(homeControllerProvider(_query)).pageError,
          isNull,
        );
      }
      expect(container.read(homeControllerProvider(_query)).hasMore, isFalse);
      expect(
        container.read(homeControllerProvider(_query)).items.requireValue,
        hasLength(5),
      );
    },
  );

  test('closed query cancels writes and suppresses late failure', () async {
    final repo = _Repository();
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(homeControllerProvider(_query), (_, _) {});
    await _settle();
    repo.reads.single.result.complete(const HomePage(_entries, hasMore: false));
    await _settle();
    final result = container
        .read(homeControllerProvider(_query).notifier)
        .unsubscribeFavorite(_collection);
    sub.close();
    await container.pump();
    expect(repo.writes.single.cancellation.isCancelled, isTrue);
    repo.writes.single.result.completeError(
      const AppFailure(AppFailureKind.network, 'fixture'),
    );
    expect(await result, isFalse);
  });

  for (final value in [
    (
      channel: HomeChannel.favorites,
      section: '我创建的收藏夹',
      scope: 'user:7',
      folderId: null,
    ),
    (
      channel: HomeChannel.favorites,
      section: '我的收藏与订阅',
      scope: 'user:7',
      folderId: 'ugc:42',
    ),
  ]) {
    test('non-subscription-list query cannot submit a write: $value', () async {
      final repo = _Repository(automaticReads: true);
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(homeControllerProvider(value), (_, _) {});
      addTearDown(sub.close);
      await _settle();
      expect(
        await container
            .read(homeControllerProvider(value).notifier)
            .unsubscribeFavorite(_folder),
        isFalse,
      );
      expect(repo.writes, isEmpty);
    });
  }

  for (final entry in _entries) {
    testWidgets('${entry.kind.name} menu removes only after server success', (
      tester,
    ) async {
      final repo = _Repository(automaticReads: true);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(find.byType(FavoriteFolderCard), findsNWidgets(2));
      final card = find.byKey(ValueKey((entry.kind, entry.id)));
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('更多操作')),
      );
      await tester.pumpAndSettle();
      expect(find.text('取消订阅'), findsOneWidget);
      expect(repo.writes, isEmpty);
      expect(repo.reads, hasLength(1));
      await tester.tap(find.text('取消订阅'));
      await tester.pumpAndSettle();
      expect(find.text('确定取消订阅“${entry.title}”吗？'), findsOneWidget);
      expect(repo.writes, isEmpty);
      await tester.tap(find.text('确认取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.writes.single.entry, entry);
      expect(find.byTooltip('取消订阅中'), findsOneWidget);
      expect(find.text(entry.title), findsOneWidget);
      repo.writes.single.result.complete();
      await tester.pumpAndSettle();
      expect(find.text(entry.title), findsNothing);
      expect(find.text('已取消订阅'), findsOneWidget);
      expect(repo.reads, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('ambiguous failure keeps the card and asks for refresh', (
    tester,
  ) async {
    final repo = _Repository(automaticReads: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消订阅'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认取消'));
    await tester.pump();
    repo.writes.single.result.completeError(
      const AppFailure(AppFailureKind.timeout, 'fixture'),
    );
    await tester.pumpAndSettle();
    expect(find.text('流行'), findsOneWidget);
    expect(find.text('取消订阅结果未确认，请刷新列表查看'), findsOneWidget);
    expect(repo.writes, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final dismissWithButton in [true, false]) {
    testWidgets(
      'dismissing confirmation (button=$dismissWithButton) preserves subscription',
      (tester) async {
        final repo = _Repository(automaticReads: true);
        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多操作').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消订阅'));
        await tester.pumpAndSettle();
        expect(find.text('确定取消订阅“流行”吗？'), findsOneWidget);
        expect(repo.writes, isEmpty);
        if (dismissWithButton) {
          await tester.tap(find.text('取消'));
        } else {
          await tester.tapAt(const Offset(1, 1));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('流行'), findsOneWidget);
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('account change while confirming prevents submission', (
    tester,
  ) async {
    final repo = _Repository(automaticReads: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消订阅'));
    await tester.pumpAndSettle();
    repo.scope = 'user:8';
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();
    expect(repo.writes, isEmpty);
    expect(find.text('流行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1920.0]) {
    testWidgets(
      'menu fits $width with doubled text and preserves card navigation',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = _Repository(automaticReads: true);
        await tester.pumpWidget(_app(repo, textScale: 2));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多操作').first);
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.text('取消订阅'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消订阅'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('确定取消订阅“收藏夹A”吗？'), findsOneWidget);
        expect(repo.writes, isEmpty);
        final confirmRect = tester.getRect(find.text('确认取消'));
        expect(confirmRect.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('流行'));
        await tester.pumpAndSettle();
        expect(repo.reads.last.query.folderId, 'ugc:42');
        expect(find.byTooltip('更多操作'), findsNothing);
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<(ProviderContainer, _Repository, HomeController)> _setup({
  bool hasMore = false,
}) async {
  final repo = _Repository();
  final container = ProviderContainer(
    overrides: [homeRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  final sub = container.listen(homeControllerProvider(_query), (_, _) {});
  addTearDown(sub.close);
  await _settle();
  repo.reads.single.result.complete(HomePage(_entries, hasMore: hasMore));
  await _settle();
  return (
    container,
    repo,
    container.read(homeControllerProvider(_query).notifier),
  );
}

Widget _app(_Repository repo, {double textScale = 1}) => ProviderScope(
  overrides: [homeRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    builder: (context, child) => AppNoticeHost(
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox(),
      ),
    ),
    home: const Scaffold(
      body: HomeContent(
        channel: HomeChannel.favorites,
        section: '我的收藏与订阅',
        isSignedIn: true,
      ),
    ),
  ),
);

final class _Repository implements HomeRepository, HomeSubscriptionRepository {
  _Repository({this.automaticReads = false});
  final bool automaticReads;
  String scope = 'user:7';
  @override
  String get accountScope => scope;
  final reads =
      <
        ({
          HomeQuery query,
          int page,
          RequestCancellation cancellation,
          Completer<HomePage> result,
        })
      >[];
  final writes =
      <
        ({
          HomeEntry entry,
          RequestCancellation cancellation,
          Completer<void> result,
        })
      >[];
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<HomePage>();
    reads.add((
      query: query,
      page: page,
      cancellation: cancellation,
      result: result,
    ));
    if (automaticReads) {
      result.complete(
        HomePage(query.folderId == null ? _entries : const [], hasMore: false),
      );
    }
    return result.future;
  }

  @override
  Future<void> unsubscribeFavorite(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<void>();
    writes.add((entry: entry, cancellation: cancellation, result: result));
    return result.future;
  }
}
