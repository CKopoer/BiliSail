import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final (title, uri, route, expected) in [
    (
      '影视卡片',
      'https://www.bilibili.com/bangumi/play/ep12',
      '/pgc/episode/:id',
      '剧集 12',
    ),
    (
      '视频卡片',
      'https://www.bilibili.com/video/BV1234567890',
      '/video/:id',
      '视频 BV1234567890',
    ),
  ]) {
    testWidgets('$title opens inside the workspace from an attached card', (
      tester,
    ) async {
      final browser = <Uri>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: HomeContent(
                channel: HomeChannel.dynamic,
                section: '全部',
                isSignedIn: true,
              ),
            ),
          ),
          GoRoute(
            path: route,
            builder: (_, state) => Scaffold(
              body: Text(
                '${route.startsWith('/pgc') ? '剧集' : '视频'} ${state.pathParameters['id']}',
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
              _Repository(
                DynamicPost(
                  id: '1',
                  contentCards: [
                    DynamicContentCard(
                      kind: DynamicCardKind.pgc,
                      title: title,
                      url: Uri.parse(uri),
                    ),
                  ],
                ),
              ),
            ),
            webLinkOpenerProvider.overrideWithValue((uri) async {
              browser.add(uri);
              return true;
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      expect(browser, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'topics open an internal page while commerce uses the public link opener',
    (tester) async {
      final browser = <Uri>[];
      final topic = Uri.https('www.bilibili.com', '/v/topic/detail', {
        'topic_id': '12',
      });
      final goods = Uri.https('mall.bilibili.com', '/item/1');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: HomeContent(
                channel: HomeChannel.dynamic,
                section: '全部',
                isSignedIn: true,
              ),
            ),
          ),
          GoRoute(
            path: '/topic/:id',
            builder: (_, state) =>
                Scaffold(body: Text('话题 ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(
              _Repository(
                DynamicPost(
                  id: '1',
                  topic: DynamicTopic(name: '话题入口', url: topic),
                  contentCards: [
                    DynamicContentCard(
                      kind: DynamicCardKind.goods,
                      title: '带货入口',
                      url: goods,
                      actionLabel: '去看看',
                      actionUrl: goods,
                    ),
                  ],
                ),
              ),
            ),
            webLinkOpenerProvider.overrideWithValue((uri) async {
              browser.add(uri);
              return true;
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('话题入口'));
      await tester.pumpAndSettle();
      expect(find.text('话题 12'), findsOneWidget);
      expect(browser, isEmpty);
      router.go('/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('带货入口'));
      await tester.pumpAndSettle();
      expect(browser, [goods]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a name-only topic opens internal search without a browser', (
    tester,
  ) async {
    final browser = <Uri>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: HomeContent(
              channel: HomeChannel.dynamic,
              section: '全部',
              isSignedIn: true,
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (_, state) =>
              Scaffold(body: Text('搜索 ${state.uri.queryParameters['q']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(
            _Repository(
              DynamicPost(
                id: '1',
                topic: DynamicTopic(
                  name: '名称话题',
                  url: Uri.https('search.bilibili.com', '/all', {
                    'keyword': '名称话题',
                  }),
                ),
              ),
            ),
          ),
          webLinkOpenerProvider.overrideWithValue((uri) async {
            browser.add(uri);
            return true;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('名称话题'));
    await tester.pumpAndSettle();
    expect(find.text('搜索 名称话题'), findsOneWidget);
    expect(browser, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final forwarded in [false, true]) {
    testWidgets(
      '${forwarded ? 'forwarded' : 'direct'} live card opens the workspace room without a browser',
      (tester) async {
        final browser = <Uri>[];
        final live = DynamicPost(
          id: '2',
          linkTitle: '直播间测试',
          linkUrl: Uri.parse('https://live.bilibili.com/12?from=dynamic'),
        );
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: HomeContent(
                  channel: HomeChannel.dynamic,
                  section: '全部',
                  isSignedIn: true,
                ),
              ),
            ),
            GoRoute(
              path: '/live/:roomId',
              builder: (_, state) =>
                  Scaffold(body: Text('房间 ${state.pathParameters['roomId']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeRepositoryProvider.overrideWithValue(
                _Repository(
                  forwarded ? DynamicPost(id: '1', original: live) : live,
                ),
              ),
              externalLinkOpenerProvider.overrideWithValue((uri) async {
                browser.add(uri);
                return true;
              }),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('直播间测试'));
        await tester.pumpAndSettle();
        expect(find.text('房间 12'), findsOneWidget);
        expect(browser, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _Repository implements HomeRepository {
  _Repository(this.post);
  final DynamicPost post;
  @override
  String get accountScope => 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => HomePage([
    HomeEntry(
      id: post.id,
      title: '',
      kind: HomeEntryKind.dynamic,
      dynamicPost: post,
    ),
  ], hasMore: false);
}
