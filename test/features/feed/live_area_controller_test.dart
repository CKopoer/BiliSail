import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _parent = (
  channel: HomeChannel.live,
  section: '推荐',
  scope: 'guest',
  folderId: '2',
);
const _child = (
  channel: HomeChannel.live,
  section: '推荐',
  scope: 'guest',
  folderId: '2:86',
);

void main() {
  test('late parent rooms cannot replace a selected child area', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final parentSub = container.listen(
      homeControllerProvider(_parent),
      (_, _) {},
    );
    final childSub = container.listen(
      homeControllerProvider(_child),
      (_, _) {},
    );
    addTearDown(parentSub.close);
    addTearDown(childSub.close);
    await _settle();
    final parentCall = repository.calls.firstWhere((c) => c.query == _parent);
    final childCall = repository.calls.firstWhere((c) => c.query == _child);
    childCall.result.complete(_page('child', more: true));
    await _settle();
    parentCall.result.complete(_page('parent', more: false));
    await _settle();
    expect(
      container
          .read(homeControllerProvider(_child))
          .items
          .requireValue
          .single
          .id,
      'child',
    );
    expect(container.read(homeControllerProvider(_child)).hasMore, isTrue);
    expect(
      container
          .read(homeControllerProvider(_parent))
          .items
          .requireValue
          .single
          .id,
      'parent',
    );
    final pending = container
        .read(homeControllerProvider(_child).notifier)
        .loadMore();
    expect(repository.calls.last.query.folderId, '2:86');
    expect(repository.calls.last.page, 2);
    repository.calls.last.result.complete(_page('child-page-2', more: false));
    await pending;
    expect(
      container
          .read(homeControllerProvider(_child))
          .items
          .requireValue
          .map((e) => e.id),
      ['child', 'child-page-2'],
    );
  });

  test(
    'failed live area page keeps rooms and explicit retry uses the same page',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(homeControllerProvider(_parent), (_, _) {});
      addTearDown(sub.close);
      await _settle();
      repository.calls.single.result.complete(_page('first', more: true));
      await _settle();
      final controller = container.read(
        homeControllerProvider(_parent).notifier,
      );
      final pending = controller.loadMore();
      final failure = const AppFailure(AppFailureKind.rateLimited, '稍后重试');
      repository.calls.last.result.completeError(failure);
      await pending;
      final failed = container.read(homeControllerProvider(_parent));
      expect(failed.items.requireValue.single.id, 'first');
      expect(failed.pageError, same(failure));
      expect(failed.hasMore, isTrue);
      await _settle();
      expect(repository.calls, hasLength(2));
      final retry = controller.loadMore();
      expect(repository.calls.last.page, 2);
      repository.calls.last.result.complete(_page('second', more: false));
      await retry;
      expect(container.read(homeControllerProvider(_parent)).pageError, isNull);
      await controller.loadMore();
      expect(repository.calls, hasLength(3));
    },
  );

  test(
    'refresh cancels an area page and ignores its late completion',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(homeControllerProvider(_child), (_, _) {});
      addTearDown(sub.close);
      await _settle();
      repository.calls.single.result.complete(_page('old', more: true));
      await _settle();
      final controller = container.read(
        homeControllerProvider(_child).notifier,
      );
      final more = controller.loadMore();
      final old = repository.calls.last;
      final refresh = controller.refresh();
      expect(old.cancellation.isCancelled, isTrue);
      expect(repository.calls.last.page, 1);
      repository.calls.last.result.complete(_page('fresh', more: false));
      await refresh;
      old.result.complete(_page('late', more: true));
      await more;
      expect(
        container
            .read(homeControllerProvider(_child))
            .items
            .requireValue
            .single
            .id,
        'fresh',
      );
      expect(container.read(homeControllerProvider(_child)).hasMore, isFalse);
    },
  );
}

HomePage _page(String id, {required bool more}) => HomePage([
  HomeEntry(id: id, title: id, kind: HomeEntryKind.live),
], hasMore: more);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _Repository implements HomeRepository {
  final calls =
      <
        ({
          HomeQuery query,
          int page,
          RequestCancellation cancellation,
          Completer<HomePage> result,
        })
      >[];
  @override
  String get accountScope => 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<HomePage>();
    calls.add((
      query: query,
      page: page,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }
}
