import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/shared/data/dynamic_post_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/dynamic_fakes.dart';

void main() {
  for (final detail in [false, true]) {
    for (final rich in [false, true]) {
      for (final (scenario, jumpUrl, identity, expected)
          in <(String, String, int?, String)>[
            (
              'mobile alias',
              'https://m.bilibili.com/topic-detail?topic_id=1028161&frommodule=H5',
              rich ? null : 1028161,
              '/topic/1028161',
            ),
            (
              'identity before jump URL',
              'https://m.bilibili.com/topic-detail?topic_id=99',
              1028161,
              '/topic/1028161',
            ),
            (
              'unknown URL with only a name',
              'https://example.test/unrecognised',
              null,
              '/search',
            ),
          ]) {
        testWidgets(
          '${detail ? 'detail' : 'feed'} ${rich ? 'rich hashtag' : 'topic badge'} $scenario stays internal',
          (tester) async {
            final wire = <String, Object?>{
              'id_str': '100',
              'type': 'DYNAMIC_TYPE_WORD',
              'basic': {'comment_id_str': '100', 'comment_type': 17},
              'modules': {
                'module_author': {'mid': '7', 'name': '作者'},
                'module_dynamic': {
                  'desc': {
                    'text': rich ? '#话题标签#' : '正文',
                    'rich_text_nodes': [
                      if (rich)
                        {
                          'type': 'RICH_TEXT_NODE_TYPE_TOPIC',
                          if (identity != null) 'rid': '$identity',
                          'text': '#话题标签#',
                          'jump_url': jumpUrl,
                        },
                    ],
                  },
                  if (!rich)
                    'topic': {
                      'id': ?identity,
                      'name': '话题标签',
                      'jump_url': jumpUrl,
                    },
                },
              },
            };
            final page = await HomeClient(
              BiliApiClient(transport: _Transport(wire)),
            ).load(channel: 'dynamic', section: '全部', page: 1);
            final parsed = page.items.single.dynamicPost;
            expect(parsed, isNotNull);
            final post = mapDynamicPost(parsed!);
            final browser = <Uri>[];
            final auth = DynamicAuthFake();
            addTearDown(auth.stream.close);
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
                  builder: (_, state) => Scaffold(
                    body: Text('内部搜索 ${state.uri.queryParameters['q']}'),
                  ),
                ),
                GoRoute(
                  path: '/topic/:id',
                  builder: (_, state) => Scaffold(
                    body: Text('内部话题 ${state.pathParameters['id']}'),
                  ),
                ),
              ],
            );
            addTearDown(router.dispose);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  authRepositoryProvider.overrideWithValue(auth),
                  commentsRepositoryProvider.overrideWith(
                    (_, _) => DynamicCommentsFake(),
                  ),
                  homeRepositoryProvider.overrideWithValue(_Repository(post)),
                  webLinkOpenerProvider.overrideWithValue((uri) async {
                    browser.add(uri);
                    return true;
                  }),
                ],
                child: MaterialApp.router(routerConfig: router),
              ),
            );
            await tester.pumpAndSettle();
            if (detail) {
              await tester.tap(find.byTooltip('查看动态详情'));
              await tester.pumpAndSettle();
            }
            if (rich) {
              await tester.tapOnText(find.textRange.ofSubstring('#话题标签#').last);
            } else {
              await tester.tap(find.text('话题标签').last);
            }
            await tester.pumpAndSettle();
            expect(browser, isEmpty);
            expect(router.routeInformationProvider.value.uri.path, expected);
            expect(
              find.text(expected == '/search' ? '内部搜索 话题标签' : '内部话题 1028161'),
              findsOneWidget,
            );
            if (detail) expect(find.byType(Dialog), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

class _Transport implements ApiTransport {
  _Transport(this.post);
  final Map<String, Object?> post;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'data': {
            'items': [post],
            'has_more': false,
          },
        }),
      ),
    ),
    {},
  );
}

class _Repository implements HomeRepository {
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
