import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_topic_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_topic_repository.dart';
import 'package:bilisail/features/dynamic/presentation/dynamic_topic_screen.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/content_section_tabs.dart';
import 'package:bilisail/shared/ui/dynamic_compose_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_topic_fakes.dart';

void main() {
  late DynamicTopicRepositoryFake repository;
  late DynamicAuthFake auth;
  setUp(() {
    repository = DynamicTopicRepositoryFake();
    auth = DynamicAuthFake();
  });
  tearDown(() => auth.stream.close());
  Future<void> show(
    WidgetTester tester, {
    double width = 1000,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          dynamicTopicRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: DynamicTopicScreen(id: '12')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (width, scale) in [(320.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      'topic header, sort and retained dynamic cards fit $width / $scale',
      (tester) async {
        await show(tester, width: width, scale: scale);
        expect(find.text('应用内话题'), findsOneWidget);
        expect(find.text('话题简介'), findsOneWidget);
        expect(find.text('话题动态'), findsOneWidget);
        expect(find.text('发起人 发起'), findsOneWidget);
        repository.onFeed = (q) async => DynamicTopicPage(
          posts: [DynamicPost(id: '2', text: '最新话题动态')],
          hasMore: false,
        );
        expect(find.byType(ContentSectionTabs<int>), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.byKey(const ValueKey('topic-favorite')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('topic-sort-2')));
        await tester.pumpAndSettle();
        expect(find.text('最新话题动态'), findsOneWidget);
        expect(find.text('话题动态'), findsNothing);
        expect(repository.queries.last.sort, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (width, scale) in [(320.0, 2.0), (768.0, 1.0), (1280.0, 1.0)]) {
    testWidgets(
      'topic sorting and participation stay pinned at $width / $scale',
      (tester) async {
        repository.page = DynamicTopicPage(
          posts: [
            for (var i = 0; i < 40; i++) DynamicPost(id: '$i', text: '话题内容 $i'),
          ],
          hasMore: false,
          sorts: const [DynamicTopicSort(0, '热门'), DynamicTopicSort(2, '最新')],
        );
        await show(tester, width: width, scale: scale);
        final viewport = find.byType(CustomScrollView);
        final top = tester.getTopLeft(viewport).dy;
        final sort = find.byKey(const ValueKey('topic-sort-2'));
        final compose = find.byKey(const ValueKey('dynamic-compose'));
        expect(
          tester.getCenter(sort).dy,
          closeTo(tester.getCenter(compose).dy, 1),
        );
        expect(
          tester
              .widget<DynamicComposeButton>(find.byType(DynamicComposeButton))
              .compact,
          width == 320,
        );
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: viewport, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        position.jumpTo(650);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(DynamicComposeToolbar)).dy,
          closeTo(top, 1),
        );
        expect(sort.hitTestable(), findsOneWidget);
        expect(compose.hitTestable(), findsOneWidget);
        position.jumpTo(1300);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(DynamicComposeToolbar)).dy,
          closeTo(top, 1),
        );
        await tester.tap(sort);
        await tester.pumpAndSettle();
        expect(repository.queries.last.sort, 2);
        expect(
          tester
              .widget<ContentSectionTabs<int>>(
                find.byType(ContentSectionTabs<int>),
              )
              .value,
          2,
        );
        expect(find.text('应用内话题').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }
  testWidgets(
    'read failures retry in place and folded posts require an explicit action',
    (tester) async {
      repository.onFeed = (_) async =>
          throw const AppFailure(AppFailureKind.network, '网络暂不可用');
      await show(tester);
      expect(find.text('网络暂不可用'), findsOneWidget);
      repository.onFeed = (q) async => DynamicTopicPage(
        posts: [
          DynamicPost(
            id: q.folded ? '2' : '1',
            text: q.folded ? '折叠的动态' : '普通动态',
          ),
        ],
        hasMore: false,
        foldDescription: q.folded ? '' : '查看折叠内容',
      );
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repository.queries.where((q) => q.folded), isEmpty);
      await tester.ensureVisible(find.text('查看折叠内容'));
      await tester.tap(find.text('查看折叠内容'));
      await tester.pumpAndSettle();
      expect(find.text('折叠的动态'), findsOneWidget);
      expect(repository.queries.where((q) => q.folded), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'the real workspace route loads topics and navigates another topic without a browser',
    (tester) async {
      final browser = <Uri>[];
      repository.page = DynamicTopicPage(
        posts: [
          DynamicPost(
            id: '1',
            text: '话题内容',
            topic: DynamicTopic(
              name: '另一个话题',
              url: Uri.https('www.bilibili.com', '/v/topic/detail', {
                'topic_id': '13',
              }),
            ),
          ),
        ],
        hasMore: false,
      );
      final router = createBiliRouter(
        initialLocation: '/topic/12',
        playerBuilder: (_, _, _) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            settingsRepositoryProvider.overrideWithValue(_Settings()),
            dynamicTopicRepositoryProvider.overrideWithValue(repository),
            webLinkOpenerProvider.overrideWithValue((uri) async {
              browser.add(uri);
              return true;
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DynamicTopicScreen), findsOneWidget);
      expect(find.text('应用内话题'), findsOneWidget);
      repository.header = const DynamicTopicDetail(id: '13', name: '另一个话题页');
      await tester.tap(find.text('另一个话题'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/topic/13');
      expect(find.text('另一个话题页'), findsOneWidget);
      expect(browser, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final mode in WorkspaceNavigationMode.values) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'topic route owns navigation without workspace tools in $mode at $width',
        (tester) async {
          final router = createBiliRouter(
            initialLocation: '/topic/12',
            playerBuilder: (_, _, _) => const SizedBox(),
          );
          addTearDown(router.dispose);
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authRepositoryProvider.overrideWithValue(auth),
                settingsRepositoryProvider.overrideWithValue(_Settings(mode)),
                dynamicTopicRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DynamicTopicScreen), findsOneWidget);
          expect(find.text('应用内话题'), findsOneWidget);
          expect(find.text('话题简介'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          expect(
            find.byKey(const ValueKey('search-category-strip')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('workspace-back')), findsNothing);
          expect(find.byKey(const ValueKey('topic-back')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-channel-strip')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('workspace-bottom-navigation')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.windows,
        }),
      );
    }
  }
  test(
    'topic pages retain ordinary bounded workspace identity and Back behavior',
    () {
      final workspace = WorkspaceTabs()..setSingleMode(true);
      workspace.acceptRoute(Uri(path: '/topic/12'));
      final first = workspace.active;
      expect(first.isTopic, isTrue);
      expect(first.title, '话题 · 12');
      workspace.acceptRoute(Uri(path: '/topic/13'));
      expect(workspace.goBack(), isTrue);
      expect(workspace.active.id, first.id);
      expect(
        workspace.tabs.length,
        lessThanOrEqualTo(WorkspaceTabs.maximumTabs),
      );
    },
  );
  testWidgets(
    'compact topic participation stays clear of the workspace playback button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget app(String location) => ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          dynamicTopicRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: BiliAppShell(
            key: const ValueKey('topic-workspace'),
            location: location,
            navigationMode: WorkspaceNavigationMode.dualTabs,
            pageBuilder: (_, tab) => tab.isTopic
                ? const DynamicTopicScreen(id: '12')
                : const SizedBox.expand(),
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpWidget(app('/video/BV17x411w7KC'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app('/topic/12'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('参与话题').hitTestable(), findsOneWidget);
      expect(find.byTooltip('返回播放').hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-back')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Settings implements SettingsRepository {
  _Settings([this.mode = WorkspaceNavigationMode.singlePage]);
  final WorkspaceNavigationMode mode;
  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults(navigationMode: mode);
  @override
  Future<void> save(AppSettings settings) async {}
}
