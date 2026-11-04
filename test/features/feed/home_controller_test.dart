import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const query = (
  channel: HomeChannel.dynamic,
  section: '全部',
  scope: 'user:1',
  folderId: null,
);
const entry = HomeEntry(id: '1', title: '动态', kind: HomeEntryKind.dynamic);

final class Repository implements HomeRepository {
  final List<
    ({
      int page,
      HomeQuery query,
      String? cursor,
      RequestCancellation cancellation,
      Completer<HomePage> result,
    })
  >
  calls = [];
  String currentScope = 'user:1';
  @override
  String get accountScope => currentScope;
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<HomePage>();
    calls.add((
      page: page,
      query: query,
      cursor: cursor,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }
}

void main() {
  for (final value in [
    (
      channel: HomeChannel.videoDynamic,
      section: '最新视频',
      scope: query.scope,
      folderId: null,
    ),
    (
      channel: HomeChannel.dynamic,
      section: '视频',
      scope: query.scope,
      folderId: null,
    ),
  ]) {
    for (final uploaderFirst in [false, true]) {
      test(
        '${value.channel.name} coauthored video prefers uploader ($uploaderFirst)',
        () async {
          final (container, repository, _) = await _setup(value);
          final uploader = _videoPost('1', action: '投稿了视频');
          final contributor = _videoPost('2');
          repository.calls.single.result.complete(
            HomePage([
              if (uploaderFirst) uploader,
              contributor,
              if (!uploaderFirst) uploader,
              _videoPost('3'),
              _videoPost('4', bvid: 'BV1234567891'),
            ], hasMore: false),
          );
          await _settle();
          final items = container
              .read(homeControllerProvider(value))
              .items
              .requireValue;
          expect(items.map((item) => item.id), ['1', '4']);
          // Keep the selected author's entire dynamic, including interaction IDs.
          expect(items.first, same(uploader));
          expect(
            items.first.dynamicPost?.commentTarget,
            const CommentTarget('42', CommentTargetType.video),
          );
        },
      );
    }
  }
  test(
    'coauthored video merges across pages and refresh resets selection',
    () async {
      const value = (
        channel: HomeChannel.videoDynamic,
        section: '最新视频',
        scope: 'user:1',
        folderId: null,
      );
      final (container, repository, controller) = await _setup(value);
      final contributor = _videoPost('1');
      repository.calls.single.result.complete(
        HomePage(
          [contributor, _videoPost('2', bvid: 'BV1234567891')],
          hasMore: true,
          nextCursor: 'first',
        ),
      );
      await _settle();
      await _more(
        controller,
        repository,
        HomePage(
          [_videoPost('3'), _videoPost('4', action: '投稿了视频')],
          hasMore: true,
          nextCursor: 'second',
        ),
      );
      expect(
        container
            .read(homeControllerProvider(value))
            .items
            .requireValue
            .map((item) => item.id),
        ['4', '2'],
      );
      // A later collaborator cannot replace the uploader or reorder its slot.
      await _more(
        controller,
        repository,
        HomePage([_videoPost('5')], hasMore: false),
      );
      expect(
        container
            .read(homeControllerProvider(value))
            .items
            .requireValue
            .map((item) => item.id),
        ['4', '2'],
      );
      final refresh = controller.refresh();
      repository.calls.last.result.complete(
        HomePage([contributor, _videoPost('6')], hasMore: false),
      );
      await refresh;
      expect(container.read(homeControllerProvider(value)).items.requireValue, [
        contributor,
      ]);
    },
  );
  test('coauthors without uploader keep first record but allow its metadata update', () async {
    const value = (
      channel: HomeChannel.videoDynamic,
      section: '最新视频',
      scope: 'user:1',
      folderId: null,
    );
    final (container, repository, controller) = await _setup(value);
    repository.calls.single.result.complete(
      HomePage(
        [for (var i = 0; i < 250; i++) _videoPost('$i')],
        hasMore: true,
        nextCursor: 'first',
      ),
    );
    await _settle();
    expect(
      container
          .read(homeControllerProvider(value))
          .items
          .requireValue
          .single
          .id,
      '0',
    );
    expect(container.read(homeControllerProvider(value)).limitReached, isFalse);
    final update = _videoPost('0', title: '更新后的标题');
    await _more(
      controller,
      repository,
      HomePage([_videoPost('251'), update], hasMore: false),
    );
    expect(container.read(homeControllerProvider(value)).items.requireValue, [
      update,
    ]);
  });
  test(
    'all dynamics and favorites preserve distinct posts for the same video',
    () async {
      for (final value in [
        query,
        (
          channel: HomeChannel.favorites,
          section: '默认收藏夹',
          scope: query.scope,
          folderId: null,
        ),
      ]) {
        final (container, repository, _) = await _setup(value);
        final items = [_videoPost('1'), _videoPost('2', action: '投稿了视频')];
        repository.calls.single.result.complete(
          HomePage(items, hasMore: false),
        );
        await _settle();
        expect(
          container.read(homeControllerProvider(value)).items.requireValue,
          items,
        );
      }
    },
  );
  test('coauthored duplicates do not consume capacity and uploader can replace at the cap', () async {
    const value = (
      channel: HomeChannel.videoDynamic,
      section: '最新视频',
      scope: 'user:1',
      folderId: null,
    );
    final (container, repository, _) = await _setup(value);
    final uploader = _videoPost('primary', action: '投稿了视频');
    repository.calls.single.result.complete(
      HomePage(
        [
          _videoPost('first'),
          for (var i = 1; i < HomeController.maxDynamicEntries + 5; i++)
            _videoPost('$i', bvid: 'BV${i.toString().padLeft(10, '0')}'),
          uploader,
          _videoPost('last'),
        ],
        hasMore: true,
        nextCursor: 'next',
      ),
    );
    await _settle();
    final state = container.read(homeControllerProvider(value));
    expect(
      state.items.requireValue,
      hasLength(HomeController.maxDynamicEntries),
    );
    expect(state.items.requireValue.first, same(uploader));
    expect(state.items.requireValue.last.id, '199');
    expect(state.limitReached, isTrue);
    expect(state.hasMore, isFalse);
  });
  test(
    'video dynamic preserves reposts and entries without a valid BVID',
    () async {
      const value = (
        channel: HomeChannel.videoDynamic,
        section: '最新视频',
        scope: 'user:1',
        folderId: null,
      );
      final (container, repository, _) = await _setup(value);
      final repost = HomeEntry(
        id: '2',
        title: '转发附言',
        kind: HomeEntryKind.video,
        bvid: 'BV1234567890',
        dynamicPost: DynamicPost(
          id: '2',
          original: DynamicPost(id: '1'),
        ),
      );
      final items = [
        _videoPost('1'),
        repost,
        _videoPost('3', bvid: ''),
        _videoPost('4', bvid: ''),
        _videoPost('5', bvid: 'invalid'),
        _videoPost('6', bvid: 'invalid'),
      ];
      repository.calls.single.result.complete(HomePage(items, hasMore: false));
      await _settle();
      expect(
        container.read(homeControllerProvider(value)).items.requireValue,
        items,
      );
    },
  );
  test(
    'favorite paging retains distinct folder types and caps loaded media',
    () async {
      const value = (
        channel: HomeChannel.favorites,
        section: '我的收藏与订阅',
        scope: 'user:1',
        folderId: null,
      );
      final (container, repository, controller) = await _setup(value);
      repository.calls.single.result.complete(
        const HomePage([
          HomeEntry(id: '42', title: '收藏夹', kind: HomeEntryKind.folder),
          HomeEntry(id: '42', title: '合集', kind: HomeEntryKind.collection),
        ], hasMore: true),
      );
      await _settle();
      expect(
        container.read(homeControllerProvider(value)).items.requireValue,
        hasLength(2),
      );
      await _more(
        controller,
        repository,
        HomePage([
          for (var i = 0; i < 510; i++)
            HomeEntry(id: '$i', title: '视频$i', kind: HomeEntryKind.video),
        ], hasMore: true),
      );
      final state = container.read(homeControllerProvider(value));
      expect(
        state.items.requireValue,
        hasLength(HomeController.maxFavoriteEntries),
      );
      expect(state.limitReached, isTrue);
      expect(state.hasMore, isFalse);
      await controller.loadMore();
      expect(repository.calls, hasLength(2));
    },
  );
  for (final (channel, firstPageSize) in [
    for (final channel in [HomeChannel.dynamic, HomeChannel.videoDynamic])
      for (final size in [190, 250]) (channel, size),
  ]) {
    test(
      '${channel.name} media stays bounded from $firstPageSize initial entries',
      () async {
        final value = (
          channel: channel,
          section: channel.sections.first,
          scope: query.scope,
          folderId: null,
        );
        final repository = Repository();
        final container = ProviderContainer(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final sub = container.listen(homeControllerProvider(value), (_, _) {});
        addTearDown(sub.close);
        await Future<void>.delayed(Duration.zero);
        List<HomeEntry> entries(int start, int count) => List.generate(
          count,
          (i) => HomeEntry(
            id: '${start + i}',
            title: '动态',
            kind: HomeEntryKind.dynamic,
          ),
        );
        repository.calls.single.result.complete(
          HomePage(
            entries(1, firstPageSize),
            hasMore: true,
            nextCursor: 'next',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final controller = container.read(
          homeControllerProvider(value).notifier,
        );
        if (firstPageSize < HomeController.maxDynamicEntries) {
          final pending = controller.loadMore();
          repository.calls.last.result.complete(
            HomePage(entries(185, 50), hasMore: true, nextCursor: 'later'),
          );
          await pending;
        }
        final state = container.read(homeControllerProvider(value));
        expect(
          state.items.requireValue.length,
          HomeController.maxDynamicEntries,
        );
        expect(state.items.requireValue.last.id, '200');
        expect(state.limitReached, isTrue);
        expect(state.hasMore, isFalse);
        final calls = repository.calls.length;
        await controller.loadMore();
        expect(repository.calls.length, calls);
        final refresh = controller.refresh();
        repository.calls.last.result.complete(
          const HomePage([entry], hasMore: false),
        );
        await refresh;
        expect(
          container.read(homeControllerProvider(value)).limitReached,
          isFalse,
        );
      },
    );
  }
  test('refresh cancels old read and ignores late responses', () async {
    final repository = Repository();
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(homeControllerProvider(query), (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    final refresh = container
        .read(homeControllerProvider(query).notifier)
        .refresh();
    expect(repository.calls.first.cancellation.isCancelled, true);
    repository.calls.last.result.complete(
      const HomePage([entry], hasMore: false),
    );
    await refresh;
    repository.calls.first.result.complete(const HomePage([], hasMore: true));
    await Future<void>.delayed(Duration.zero);
    expect(
      container
          .read(homeControllerProvider(query))
          .items
          .asData!
          .value
          .single
          .id,
      '1',
    );
    expect(container.read(homeControllerProvider(query)).hasMore, false);
  });
  test(
    'cursor pagination retains list after failure and deduplicates retry',
    () async {
      final repository = Repository();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(homeControllerProvider(query), (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      repository.calls.single.result.complete(
        const HomePage([entry], hasMore: true, nextCursor: 'opaque'),
      );
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(homeControllerProvider(query).notifier);
      var pending = controller.loadMore();
      expect(repository.calls.last.cursor, 'opaque');
      repository.calls.last.result.completeError(
        const AppFailure(AppFailureKind.network, '下一页失败'),
      );
      await pending;
      expect(
        container
            .read(homeControllerProvider(query))
            .items
            .asData!
            .value
            .length,
        1,
      );
      pending = controller.loadMore();
      expect(repository.calls.last.page, 2);
      expect(repository.calls.last.cursor, 'opaque');
      repository.calls.last.result.complete(
        const HomePage([
          entry,
          HomeEntry(id: '2', title: '第二条', kind: HomeEntryKind.dynamic),
        ], hasMore: false),
      );
      await pending;
      expect(
        container
            .read(homeControllerProvider(query))
            .items
            .asData!
            .value
            .length,
        2,
      );
    },
  );
  test(
    'duplicates on the first page do not consume the dynamic capacity',
    () async {
      final (container, repository, controller) = await _setup();
      repository.calls.single.result.complete(
        HomePage(List.filled(250, entry), hasMore: true, nextCursor: 'first'),
      );
      await _settle();
      expect(container.read(homeControllerProvider(query)).items.requireValue, [
        entry,
      ]);
      expect(
        container.read(homeControllerProvider(query)).limitReached,
        isFalse,
      );
      final more = controller.loadMore();
      repository.calls.last.result.complete(
        const HomePage([
          entry,
          HomeEntry(id: '2', title: '第二条', kind: HomeEntryKind.dynamic),
          HomeEntry(id: '2', title: '更新', kind: HomeEntryKind.dynamic),
        ], hasMore: false),
      );
      await more;
      final items = container
          .read(homeControllerProvider(query))
          .items
          .requireValue;
      expect(items.map((item) => item.id), ['1', '2']);
      expect(items.last.title, '更新');
    },
  );
  test('concurrent pagination calls make a single cursor request', () async {
    final (container, repository, controller) = await _setup();
    repository.calls.single.result.complete(
      const HomePage([entry], hasMore: true, nextCursor: 'opaque:first'),
    );
    await _settle();
    final first = controller.loadMore();
    final concurrent = controller.loadMore();
    expect(repository.calls.length, 2);
    expect(repository.calls.last.page, 2);
    expect(repository.calls.last.cursor, 'opaque:first');
    expect(container.read(homeControllerProvider(query)).loadingMore, isTrue);
    repository.calls.last.result.complete(const HomePage([], hasMore: false));
    await Future.wait([first, concurrent]);
    expect(container.read(homeControllerProvider(query)).loadingMore, isFalse);
    expect(container.read(homeControllerProvider(query)).hasMore, isFalse);
  });
  test(
    'filtered empty pages advance within a bounded scan that can be continued',
    () async {
      const textQuery = (
        channel: HomeChannel.dynamic,
        section: '图文',
        scope: 'user:1',
        folderId: null,
      );
      final (container, repository, controller) = await _setup(textQuery);
      repository.calls.single.result.complete(
        const HomePage([], hasMore: true, nextCursor: 'filtered:1'),
      );
      await _settle();
      for (var page = 2; page <= 3; page++) {
        final more = controller.loadMore();
        expect(repository.calls.last.page, page);
        expect(repository.calls.last.cursor, 'filtered:${page - 1}');
        repository.calls.last.result.complete(
          HomePage([], hasMore: true, nextCursor: 'filtered:$page'),
        );
        await more;
        final state = container.read(homeControllerProvider(textQuery));
        expect(state.hasMore, isTrue);
        expect(state.pageError == null, page == 2);
      }
      // Automatic calls stop on pageError; explicit retry resets the scan
      // budget and continues from the successful page's opaque cursor.
      for (var page = 4; page <= 5; page++) {
        final more = controller.loadMore();
        expect(repository.calls.last.page, page);
        expect(repository.calls.last.cursor, 'filtered:${page - 1}');
        repository.calls.last.result.complete(
          HomePage([], hasMore: true, nextCursor: 'filtered:$page'),
        );
        await more;
        expect(
          container.read(homeControllerProvider(textQuery)).pageError,
          isNull,
        );
      }
      await _more(
        controller,
        repository,
        const HomePage([entry], hasMore: true, nextCursor: 'filtered:6'),
      );
      await _more(
        controller,
        repository,
        const HomePage([], hasMore: true, nextCursor: 'filtered:7'),
      );
      expect(
        container.read(homeControllerProvider(textQuery)).pageError,
        isNull,
      );
      await _more(controller, repository, const HomePage([], hasMore: false));
      expect(
        container.read(homeControllerProvider(textQuery)).hasMore,
        isFalse,
      );
      expect(
        container.read(homeControllerProvider(textQuery)).pageError,
        isNull,
      );
    },
  );
  for (final stalledCursor in <String?>[null, '', 'first']) {
    test(
      'stalled cursor $stalledCursor pauses without advancing the request',
      () async {
        final (container, repository, controller) = await _setup();
        repository.calls.single.result.complete(
          const HomePage([entry], hasMore: true, nextCursor: 'first'),
        );
        await _settle();
        await _more(
          controller,
          repository,
          HomePage(
            const [
              HomeEntry(id: '2', title: '新增但游标坏了', kind: HomeEntryKind.dynamic),
            ],
            hasMore: true,
            nextCursor: stalledCursor,
          ),
        );
        var state = container.read(homeControllerProvider(query));
        expect(state.items.requireValue.map((item) => item.id), ['1', '2']);
        expect(state.hasMore, isTrue);
        expect((state.pageError as AppFailure).kind, AppFailureKind.protocol);
        final retry = controller.loadMore();
        expect(repository.calls.last.page, 2);
        expect(repository.calls.last.cursor, 'first');
        repository.calls.last.result.complete(
          const HomePage(
            [HomeEntry(id: '2', title: '新增但游标坏了', kind: HomeEntryKind.dynamic)],
            hasMore: true,
            nextCursor: 'second',
          ),
        );
        await retry;
        state = container.read(homeControllerProvider(query));
        expect(state.items.requireValue.length, 2);
        expect(state.pageError, isNull);
      },
    );
  }
  test(
    'cursor cycles pause even when the repeated page has new entries',
    () async {
      final (container, repository, controller) = await _setup();
      repository.calls.single.result.complete(
        const HomePage([entry], hasMore: true, nextCursor: 'first'),
      );
      await _settle();
      await _more(
        controller,
        repository,
        const HomePage(
          [HomeEntry(id: '2', title: '第二条', kind: HomeEntryKind.dynamic)],
          hasMore: true,
          nextCursor: 'second',
        ),
      );
      await _more(
        controller,
        repository,
        const HomePage(
          [HomeEntry(id: '3', title: '第三条', kind: HomeEntryKind.dynamic)],
          hasMore: true,
          nextCursor: 'first',
        ),
      );
      final state = container.read(homeControllerProvider(query));
      expect(state.items.requireValue.length, 3);
      expect((state.pageError as AppFailure).kind, AppFailureKind.protocol);
    },
  );
  test(
    'refresh discards pending pagination and resets cursor history',
    () async {
      final (container, repository, controller) = await _setup();
      repository.calls.single.result.complete(
        const HomePage([entry], hasMore: true, nextCursor: 'first'),
      );
      await _settle();
      final oldMore = controller.loadMore();
      final oldCall = repository.calls.last;
      final refresh = controller.refresh();
      expect(oldCall.cancellation.isCancelled, isTrue);
      expect(repository.calls.last.cursor, isNull);
      expect(repository.calls.last.page, 1);
      repository.calls.last.result.complete(
        const HomePage(
          [HomeEntry(id: '新', title: '刷新', kind: HomeEntryKind.dynamic)],
          hasMore: true,
          nextCursor: 'first',
        ),
      );
      await refresh;
      oldCall.result.complete(
        const HomePage([
          HomeEntry(id: '旧', title: '过期', kind: HomeEntryKind.dynamic),
        ], hasMore: false),
      );
      await oldMore;
      final state = container.read(homeControllerProvider(query));
      expect(state.items.requireValue.single.id, '新');
      expect(state.hasMore, isTrue);
      expect(state.pageError, isNull);
      expect(state.loadingMore, isFalse);
    },
  );
  test(
    'different section and channel queries own independent cursor state',
    () async {
      final (container, repository, controller) = await _setup();
      const videoQuery = (
        channel: HomeChannel.videoDynamic,
        section: '最新视频',
        scope: 'user:1',
        folderId: null,
      );
      const sectionQuery = (
        channel: HomeChannel.dynamic,
        section: '视频',
        scope: 'user:1',
        folderId: null,
      );
      final videoSub = container.listen(
        homeControllerProvider(videoQuery),
        (_, _) {},
      );
      final sectionSub = container.listen(
        homeControllerProvider(sectionQuery),
        (_, _) {},
      );
      addTearDown(videoSub.close);
      addTearDown(sectionSub.close);
      await _settle();
      for (final call in repository.calls) {
        call.result.complete(
          HomePage(
            [
              HomeEntry(
                id: call.query.section,
                title: call.query.section,
                kind: HomeEntryKind.dynamic,
              ),
            ],
            hasMore: true,
            nextCursor: '${call.query.section}:1',
          ),
        );
      }
      await _settle();
      final allMore = controller.loadMore();
      final videoMore = container
          .read(homeControllerProvider(videoQuery).notifier)
          .loadMore();
      final sectionMore = container
          .read(homeControllerProvider(sectionQuery).notifier)
          .loadMore();
      final calls = repository.calls.skip(3).toList();
      expect(calls.map((call) => call.cursor), ['全部:1', '最新视频:1', '视频:1']);
      for (final call in calls.reversed) {
        call.result.complete(
          HomePage([
            HomeEntry(
              id: '${call.query.section}:2',
              title: '下一页',
              kind: HomeEntryKind.dynamic,
            ),
          ], hasMore: false),
        );
      }
      await Future.wait([allMore, videoMore, sectionMore]);
      for (final value in [query, videoQuery, sectionQuery]) {
        expect(
          container
              .read(homeControllerProvider(value))
              .items
              .requireValue
              .map((item) => item.id),
          [value.section, '${value.section}:2'],
        );
      }
    },
  );
  test(
    'an account change discards a late response before the new query loads',
    () async {
      final (container, repository, _) = await _setup();
      final oldCall = repository.calls.single;
      repository.currentScope = 'user:2';
      oldCall.result.complete(
        const HomePage([entry], hasMore: true, nextCursor: 'old'),
      );
      await _settle();
      expect(oldCall.cancellation.isCancelled, isTrue);
      expect(
        container.read(homeControllerProvider(query)).items.asData,
        isNull,
      );
      const nextQuery = (
        channel: HomeChannel.dynamic,
        section: '全部',
        scope: 'user:2',
        folderId: null,
      );
      final sub = container.listen(
        homeControllerProvider(nextQuery),
        (_, _) {},
      );
      addTearDown(sub.close);
      await _settle();
      repository.calls.last.result.complete(
        const HomePage([
          HomeEntry(id: '新账号', title: '新账号', kind: HomeEntryKind.dynamic),
        ], hasMore: false),
      );
      await _settle();
      expect(
        container
            .read(homeControllerProvider(nextQuery))
            .items
            .requireValue
            .single
            .id,
        '新账号',
      );
    },
  );
  test('a closed account query cancels its pending page', () async {
    final repository = Repository();
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(homeControllerProvider(query), (_, _) {});
    await _settle();
    final oldCall = repository.calls.single;
    sub.close();
    await container.pump();
    expect(oldCall.cancellation.isCancelled, isTrue);
    oldCall.result.complete(const HomePage([entry], hasMore: false));
    await _settle();
    expect(container.exists(homeControllerProvider(query)), isFalse);
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

HomeEntry _videoPost(
  String id, {
  String bvid = 'BV1234567890',
  String action = '与他人联合创作',
  String title = '合作视频',
}) => HomeEntry(
  id: id,
  title: title,
  kind: HomeEntryKind.video,
  bvid: bvid,
  authorMid: id,
  authorName: '作者$id',
  dynamicPost: DynamicPost(
    id: id,
    actionText: action,
    commentTarget: const CommentTarget('42', CommentTargetType.video),
  ),
);

Future<(ProviderContainer, Repository, HomeController)> _setup([
  HomeQuery value = query,
]) async {
  final repository = Repository();
  final container = ProviderContainer(
    overrides: [homeRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  final sub = container.listen(homeControllerProvider(value), (_, _) {});
  addTearDown(sub.close);
  await _settle();
  return (
    container,
    repository,
    container.read(homeControllerProvider(value).notifier),
  );
}

Future<void> _more(
  HomeController controller,
  Repository repository,
  HomePage result,
) async {
  final pending = controller.loadMore();
  repository.calls.last.result.complete(result);
  await pending;
}
