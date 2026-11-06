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
