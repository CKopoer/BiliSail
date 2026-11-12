import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = HomeEntry(id: '42', title: '音乐收藏夹', kind: HomeEntryKind.folder);
const _video = HomeEntry(
  id: 'BV1234567890',
  bvid: 'BV1234567890',
  aid: '9007199254740993123',
  title: '收藏视频',
  kind: HomeEntryKind.video,
);
const _other = HomeEntry(
  id: 'BV1234567891',
  bvid: 'BV1234567891',
  aid: '125',
  title: '另一条视频',
  kind: HomeEntryKind.video,
);
HomeQuery _query({bool folders = false, bool defaultFolder = false}) => (
  channel: HomeChannel.favorites,
  section: defaultFolder ? '默认收藏夹' : '我创建的收藏夹',
  scope: 'user:7',
  folderId: folders || defaultFolder ? null : '42',
);

void main() {
  test('subscribed folders cannot remove videos or delete folders', () async {
    final repo = _Repository();
    final query = (
      channel: HomeChannel.favorites,
      section: '我的收藏与订阅',
      scope: 'user:7',
      folderId: '42',
    );
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.listen(homeControllerProvider(query), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(homeControllerProvider(query).notifier);
    expect(controller.canRemoveFavorite(_video), false);
    expect(await controller.removeFavorite(_video), false);
    expect(await controller.deleteFavoriteFolder(_folder), false);
    expect(repo.writes, 0);
  });

  test('same-account session changes reject late mutation success', () async {
    final repo = _Repository();
    final query = _query();
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repo),
        sessionEpochProvider.overrideWithValue(() => repo.epoch),
      ],
    );
    addTearDown(container.dispose);
    container.listen(homeControllerProvider(query), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(homeControllerProvider(query).notifier);
    final write = controller.removeFavorite(_video);
    repo.epoch++;
    repo.pendingWrite.complete();
    expect(await write, false);
    expect(
      container.read(homeControllerProvider(query)).items.requireValue,
      contains(_video),
    );
  });

  for (final width in [320.0, 1920.0]) {
    testWidgets('default folder invalid video removal fits $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Repository(automaticReads: true)
        ..videos = const [
          HomeEntry(
            id: '123',
            aid: '123',
            title: '已失效视频',
            kind: HomeEntryKind.video,
          ),
        ];
      await tester.pumpWidget(_app(repo, section: '默认收藏夹', textScale: 2));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(HomeVideoCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('确认取消'));
      await tester.pump();
      expect(repo.writes, 1);
      repo.pendingWrite.complete();
      await tester.pumpAndSettle();
      expect(find.text('已失效视频'), findsNothing);
      expect(repo.writeFolderId, '42');
      expect(tester.takeException(), isNull);
    });
  }
  for (final deleteFolder in [false, true]) {
    test(
      'remove folder=$deleteFolder is single flight and rejects stale pages',
      () async {
        final repo = _Repository();
        final query = _query(folders: deleteFolder);
        final container = ProviderContainer(
          overrides: [homeRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        container.listen(homeControllerProvider(query), (_, _) {});
        await Future<void>.delayed(Duration.zero);
        final controller = container.read(
          homeControllerProvider(query).notifier,
        );
        final entry = deleteFolder ? _folder : _video;
        final page = controller.loadMore();
        final late = repo.pendingRead!;
        final write = deleteFolder
            ? controller.deleteFavoriteFolder(entry)
            : controller.removeFavorite(entry);
        expect(
          await (deleteFolder
              ? controller.deleteFavoriteFolder(entry)
              : controller.removeFavorite(entry)),
          false,
        );
        expect(repo.writes, 1);
        repo.pendingWrite.complete();
        expect(await write, true);
        late.complete(HomePage([entry, _other], hasMore: false));
        await page;
        expect(
          container.read(homeControllerProvider(query)).items.requireValue,
          isNot(contains(entry)),
        );
        expect(repo.writeFolderId, '42');
        final reconcile = controller.loadMore();
        expect(repo.lastReadPage, 1);
        repo.pendingRead!.complete(const HomePage([_other], hasMore: false));
        await reconcile;
        expect(
          container.read(homeControllerProvider(query)).items.requireValue,
          [_other],
        );
      },
    );

    test(
      'uncertain folder=$deleteFolder waits for refresh before another write',
      () async {
        final repo = _Repository();
        final query = _query(folders: deleteFolder);
        final container = ProviderContainer(
          overrides: [homeRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        container.listen(homeControllerProvider(query), (_, _) {});
        await Future<void>.delayed(Duration.zero);
        final controller = container.read(
          homeControllerProvider(query).notifier,
        );
        Future<bool> remove() => deleteFolder
            ? controller.deleteFavoriteFolder(_folder)
            : controller.removeFavorite(_video);
        final result = remove();
        final assertion = expectLater(
          result,
          throwsA(isA<UnknownWriteOutcome>()),
        );
        repo.pendingWrite.completeError(const UnknownWriteOutcome());
        await assertion;
        await expectLater(remove(), throwsA(isA<UnknownWriteOutcome>()));
        expect(repo.writes, 1);
        expect(
          container.read(homeControllerProvider(query)).items.requireValue,
          contains(deleteFolder ? _folder : _video),
        );
        final refresh = controller.refresh();
        repo.pendingRead!.complete(
          HomePage([deleteFolder ? _folder : _video], hasMore: false),
        );
        await refresh;
        repo.pendingWrite = Completer<void>();
        final retry = remove();
        repo.pendingWrite.complete();
        expect(await retry, true);
        expect(repo.writes, 2);
      },
    );

    for (final longPress in [false, true]) {
      testWidgets(
        'folder=$deleteFolder menu longPress=$longPress confirms before writing',
        (tester) async {
          final repo = _Repository(automaticReads: true);
          await tester.pumpWidget(_app(repo));
          await tester.pumpAndSettle();
          if (!deleteFolder) {
            await tester.tap(find.text(_folder.title));
            await tester.pumpAndSettle();
          }
          final card = find
              .byType(deleteFolder ? FavoriteFolderCard : HomeVideoCard)
              .first;
          if (longPress) {
            await tester.longPress(card);
          } else if (deleteFolder) {
            await tester.tap(find.byTooltip('更多操作').first);
          } else {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: tester.getCenter(card));
            await mouse.moveTo(tester.getCenter(card));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('video-card-title-menu')).first,
            );
            await mouse.removePointer();
          }
          await tester.pumpAndSettle();
          final label = deleteFolder ? '删除收藏夹' : '取消收藏';
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(repo.writes, 0);
          await tester.tap(find.text(deleteFolder ? '确认删除' : '确认取消'));
          await tester.pump();
          expect(repo.writes, 1);
          repo.pendingWrite.complete();
          await tester.pumpAndSettle();
          expect(
            find.text(deleteFolder ? _folder.title : _video.title),
            findsNothing,
          );
          expect(find.text(deleteFolder ? '收藏夹已删除' : '已取消收藏'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'default folder retains its server ID across consecutive removals',
    () async {
      final repo = _Repository()..snapshotDefault = true;
      final query = _query(defaultFolder: true);
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.listen(homeControllerProvider(query), (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(homeControllerProvider(query).notifier);
      final first = controller.removeFavorite(_video);
      repo.pendingWrite.complete();
      expect(await first, true);
      repo.pendingWrite = Completer<void>();
      final second = controller.removeFavorite(_other);
      repo.pendingWrite.complete();
      expect(await second, true);
      expect(repo.writeFolderId, '42');
      expect(repo.writes, 2);
      expect(await controller.deleteFavoriteFolder(_folder), false);
    },
  );

  for (final changeEpoch in [false, true]) {
    testWidgets(
      'account change epoch=$changeEpoch during confirmation prevents write',
      (tester) async {
        final repo = _Repository(automaticReads: true);
        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(FavoriteFolderCard));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除收藏夹'));
        await tester.pumpAndSettle();
        if (changeEpoch) {
          repo.epoch++;
        } else {
          repo.scope = 'user:8';
        }
        await tester.tap(find.text('确认删除'));
        await tester.pumpAndSettle();
        expect(repo.writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dismissal keeps the folder', (tester) async {
    final repo = _Repository(automaticReads: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(FavoriteFolderCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除收藏夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    expect(find.text(_folder.title), findsOneWidget);
  });
}

Widget _app(
  _Repository repo, {
  String section = '我创建的收藏夹',
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    homeRepositoryProvider.overrideWithValue(repo),
    sessionEpochProvider.overrideWithValue(() => repo.epoch),
  ],
  child: MaterialApp(
    builder: (context, child) => AppNoticeHost(
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
    home: Scaffold(
      body: HomeContent(
        channel: HomeChannel.favorites,
        section: section,
        isSignedIn: true,
      ),
    ),
  ),
);

final class _Repository implements HomeRepository, HomeFavoriteRepository {
  _Repository({this.automaticReads = false});
  final bool automaticReads;
  String scope = 'user:7';
  int epoch = 1, writes = 0, reads = 0, lastReadPage = 0;
  String? writeFolderId;
  bool snapshotDefault = false;
  List<HomeEntry> videos = [_video, _other];
  Completer<void> pendingWrite = Completer<void>();
  Completer<HomePage>? pendingRead;
  @override
  String get accountScope => scope;
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    lastReadPage = page;
    reads++;
    final folders = query.folderId == null && query.section != '默认收藏夹';
    if (reads <= 1 || automaticReads) {
      return HomePage(
        folders ? [_folder] : videos,
        hasMore: !automaticReads,
        nextCursor: folders
            ? '1'
            : snapshotDefault
            ? 'local-favorite-fixture'
            : '42',
        favoriteFolderId: snapshotDefault ? '42' : null,
      );
    }
    return (pendingRead = Completer<HomePage>()).future;
  }

  @override
  Future<void> removeFavorite(
    HomeEntry entry, {
    required String folderId,
    required String scope,
    required RequestCancellation cancellation,
  }) {
    writes++;
    writeFolderId = folderId;
    return pendingWrite.future;
  }

  @override
  Future<void> deleteFavoriteFolder(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) => removeFavorite(
    entry,
    folderId: entry.id,
    scope: scope,
    cancellation: cancellation,
  );
}
