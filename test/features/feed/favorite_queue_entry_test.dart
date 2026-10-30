import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late _Repository repository;
  late ProviderContainer container;
  late GoRouter router;
  setUp(() {
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repository),
        sessionEpochProvider.overrideWithValue(() => 4),
      ],
    );
  });
  tearDown(() {
    router.dispose();
    container.dispose();
  });
  Future<void> mount(
    WidgetTester tester,
    String section, {
    double scale = 1,
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: HomeContent(
              channel: HomeChannel.favorites,
              section: section,
              isSignedIn: true,
            ),
          ),
        ),
        GoRoute(
          path: '/video/:bvid',
          builder: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final section in ['默认收藏夹', '我创建的收藏夹', '我的收藏与订阅']) {
    for (final playAll in [true, false]) {
      testWidgets(
        '$section ${playAll ? 'play all' : 'select item'} includes unseen pages',
        (tester) async {
          await mount(tester, section);
          if (section != '默认收藏夹') {
            expect(
              find.byKey(const ValueKey('favorite-play-all')),
              findsNothing,
            );
            await tester.tap(find.text('测试收藏夹'));
            await tester.pumpAndSettle();
          }
          final readsBefore = repository.pages.length;
          await tester.tap(
            playAll
                ? find.byKey(const ValueKey('favorite-play-all'))
                : find.text('视频 2'),
          );
          await tester.pumpAndSettle();
          final uri = router.routeInformationProvider.value.uri;
          expect(
            uri.path,
            playAll ? '/video/BV0000000001' : '/video/BV0000000002',
          );
          final queue = container
              .read(watchLaterQueueRegistryProvider)
              .resolve(
                uri.queryParameters['queue'],
                scope: 'user:7',
                sessionEpoch: 4,
              )!;
          expect(queue.items, hasLength(25));
          expect(queue.items.last.video.id.value, 'BV0000000025');
          expect(queue.title, section == '默认收藏夹' ? section : '测试收藏夹');
          expect(queue.isWatchLater, isFalse);
          expect(repository.pages.skip(readsBefore), [1, 2]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'play all disables duplicate requests, leaving folder cancels pending navigation',
    (tester) async {
      await mount(tester, '我创建的收藏夹');
      await tester.tap(find.text('测试收藏夹'));
      await tester.pumpAndSettle();
      repository.pending = Completer<HomePage>();
      await tester.tap(find.byKey(const ValueKey('favorite-play-all')));
      await tester.pump();
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('favorite-play-all')),
      );
      expect(button.onPressed, isNull);
      final cancellation = repository.lastCancellation!;
      await tester.tap(find.byTooltip('返回列表'));
      await tester.pumpAndSettle();
      expect(cancellation.isCancelled, isTrue);
      repository.pending!.complete(const HomePage([], hasMore: false));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subscribed UGC collections retain their distinct paging identity',
    (tester) async {
      repository.collection = true;
      await mount(tester, '我的收藏与订阅');
      await tester.tap(find.text('测试收藏夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('favorite-play-all')));
      await tester.pumpAndSettle();
      expect(repository.folderIds, everyElement('ugc:42'));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/video/BV0000000001',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folder header fits narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, '我创建的收藏夹', scale: 2);
    await tester.tap(find.text('测试收藏夹'));
    await tester.pumpAndSettle();
    expect(find.text('播放全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _Repository implements HomeRepository {
  @override
  String get accountScope => 'user:7';
  final pages = <int>[];
  final folderIds = <String?>[];
  bool collection = false;
  Completer<HomePage>? pending;
  RequestCancellation? lastCancellation;
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    if (query.folderId == null && query.section != '默认收藏夹') {
      return HomePage([
        HomeEntry(
          id: '42',
          kind: collection ? HomeEntryKind.collection : HomeEntryKind.folder,
          title: '测试收藏夹',
        ),
      ], hasMore: false);
    }
    pages.add(page);
    if (query.folderId != null) folderIds.add(query.folderId);
    lastCancellation = cancellation;
    if (pending != null) return pending!.future;
    return HomePage([
      if (page == 1)
        const HomeEntry(
          id: 'invalid',
          title: '失效视频',
          kind: HomeEntryKind.video,
        ),
      for (var n = page == 1 ? 1 : 25; n <= (page == 1 ? 24 : 25); n++)
        HomeEntry(
          id: '$n',
          kind: HomeEntryKind.video,
          title: '视频 $n',
          bvid: 'BV${n.toString().padLeft(10, '0')}',
        ),
    ], hasMore: page == 1);
  }
}
