import '../../support/input_test_app.dart';

import 'dart:async';

import 'package:bilisail/shared/ui/playback_page_commands.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_episode_panel.dart';
import 'package:bilisail/features/pgc/presentation/pgc_screen.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _season = PgcSeason(
  id: const PgcSeasonId('s1'),
  title: '测试番剧',
  description: '剧集简介内容',
  relatedSeasons: const [
    PgcSeasonSummary(id: PgcSeasonId('s1'), title: '测试番剧'),
    PgcSeasonSummary(id: PgcSeasonId('s2'), title: '测试番剧续作'),
  ],
  episodes: const [
    PgcEpisode(
      id: PgcEpisodeId('e1'),
      title: '第 1 集',
      longTitle: '开始',
      bvid: 'BV1ab411c7mD',
      cid: '101',
    ),
    PgcEpisode(
      id: PgcEpisodeId('e2'),
      title: '第 2 集',
      longTitle: '继续',
      bvid: 'BV1cd411c7mD',
      cid: '102',
    ),
    PgcEpisode(
      id: PgcEpisodeId('e3'),
      title: '第 3 集',
      available: false,
      permissionText: '会员专享',
    ),
  ],
);

void main() {
  test('new request cancels and rejects a late season response', () async {
    final repo = _Repo();
    final auth = _Auth();
    final container = ProviderContainer(
      overrides: [
        pgcRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(() {
      container.dispose();
      auth.dispose();
    });
    const locator = PgcLocator(
      seasonId: PgcSeasonId('s1'),
      episodeId: PgcEpisodeId('e2'),
    );
    container.listen(pgcControllerProvider(locator), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(pgcControllerProvider(locator).notifier);
    expect(
      container.read(pgcControllerProvider(locator)).selectedEpisodeId,
      const PgcEpisodeId('e2'),
    );

    final late = Completer<PgcSeason>();
    repo.pending = late;
    final old = controller.load();
    final oldCancellation = repo.lastCancellation;
    repo.pending = null;
    await controller.load();
    expect(oldCancellation?.isCancelled, true);
    late.complete(
      PgcSeason(id: const PgcSeasonId('s1'), title: '过期结果', episodes: const []),
    );
    await old;
    expect(
      container.read(pgcControllerProvider(locator)).season?.title,
      '测试番剧',
    );
  });

  test('account transition clears detail and cancels previous read', () async {
    final repo = _Repo();
    final auth = _Auth();
    final container = ProviderContainer(
      overrides: [
        pgcRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(() {
      container.dispose();
      auth.dispose();
    });
    const locator = PgcLocator(seasonId: PgcSeasonId('s1'));
    container.listen(pgcControllerProvider(locator), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final pending = Completer<PgcSeason>();
    repo.pending = pending;
    final old = container.read(pgcControllerProvider(locator).notifier).load();
    final oldCancellation = repo.lastCancellation;
    repo.pending = null;
    repo.scope = 'user:2';
    repo.epoch++;
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '2'));
    await Future<void>.delayed(Duration.zero);
    expect(oldCancellation?.isCancelled, true);
    pending.complete(
      PgcSeason(
        id: const PgcSeasonId('s1'),
        title: '旧账号结果',
        episodes: const [],
      ),
    );
    await old;
    expect(
      container.read(pgcControllerProvider(locator)).season?.title,
      '测试番剧',
    );
  });

  testWidgets('selection and responsive layout retain the player state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repo = _Repo();
    final auth = _Auth();
    addTearDown(auth.dispose);
    var created = 0;
    var disposed = 0;
    PgcEpisode? changed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pgcRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: PgcScreen(
              seasonId: 's1',
              episodeId: 'e1',
              onEpisodeChanged: (episode) => changed = episode,
              playerBuilder: (context, _, episode) => _TrackedPlayer(
                title: episode.displayTitle,
                onCreate: () => created++,
                onDispose: () => disposed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 集 开始'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('pgc-episode-e2')));
    await tester.pumpAndSettle();
    expect(changed?.episodeId, 'e2');
    expect(find.text('第 2 集 继续'), findsWidgets);
    tester.view.physicalSize = const Size(480, 800);
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(disposed, 0);
    final commands = tester.element(find.byType(_TrackedPlayer));
    PlaybackPageCommands.maybeOf(commands)?.previousPart();
    await tester.pumpAndSettle();
    expect(changed?.episodeId, 'e1');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'episode-only deep link keeps player mounted on same-season choice',
    (tester) async {
      final repo = _Repo();
      final auth = _Auth();
      addTearDown(auth.dispose);
      var currentEpisodeId = 'e1';
      var created = 0;
      var disposed = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pgcRepositoryProvider.overrideWithValue(repo),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => PgcScreen(
                  episodeId: currentEpisodeId,
                  onEpisodeChanged: (episode) =>
                      update(() => currentEpisodeId = episode.episodeId),
                  playerBuilder: (_, _, episode) => _TrackedPlayer(
                    title: episode.displayTitle,
                    onCreate: () => created++,
                    onDispose: () => disposed++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pgc-episode-e2')));
      await tester.tap(find.byKey(const ValueKey('pgc-episode-e2')));
      await tester.pumpAndSettle();
      expect(currentEpisodeId, 'e2');
      expect(created, 1);
      expect(disposed, 0);
      expect(find.text('第 2 集 继续'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restricted episode shows reason without invoking player', (
    tester,
  ) async {
    final repo = _Repo();
    final auth = _Auth();
    addTearDown(auth.dispose);
    var playerCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pgcRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: PgcScreen(
              seasonId: 's1',
              episodeId: 'e3',
              playerBuilder: (_, _, _) {
                playerCalls++;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('会员专享'), findsWidgets);
    expect(playerCalls, 0);
  });

  testWidgets(
    'introduction includes episodes and switches to injected comments',
    (tester) async {
      final repo = _Repo();
      final auth = _Auth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pgcRepositoryProvider.overrideWithValue(repo),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: PgcScreen(
                seasonId: 's1',
                playerBuilder: (_, _, _) => const SizedBox(),
                commentsBuilder: (_, _, _) =>
                    const Center(child: Text('评论区已接入')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pgc-episode-e1')), findsOneWidget);
      expect(find.text('剧集简介内容'), findsOneWidget);
      expect(find.text('评论区已接入'), findsNothing);
      expect(find.byKey(const ValueKey('pgc-tab-选集')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pgc-tab-简介')));
      await tester.pumpAndSettle();
      expect(find.text('剧集简介内容'), findsOneWidget);
      expect(find.text('评论区已接入'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pgc-tab-评论')));
      await tester.pumpAndSettle();
      expect(find.text('评论区已接入'), findsOneWidget);
      expect(find.text('剧集简介内容'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('invalid playback identifiers are visibly unavailable', () {
    const invalid = PgcEpisode(
      id: PgcEpisodeId('e4'),
      title: '编号异常',
      bvid: 'BV111',
      cid: '0',
    );
    expect(invalid.playable, false);
    expect(invalid.unavailableReason, contains('播放标识'));
  });

  testWidgets(
    'long season locates current episode across sort, grid and groups',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(380, 650);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final season = PgcSeason(
        id: const PgcSeasonId('s1'),
        title: '长篇番剧',
        episodes: [
          for (var index = 1; index <= 1275; index++)
            PgcEpisode(
              id: PgcEpisodeId('e$index'),
              title: '第$index话',
              bvid: 'BV1ab411c7mD',
              cid: '$index',
            ),
          const PgcEpisode(
            id: PgcEpisodeId('sp1'),
            title: '特别篇 1',
            sectionTitle: 'SP',
            bvid: 'BV1ab411c7mD',
            cid: '2001',
          ),
          const PgcEpisode(
            id: PgcEpisodeId('sp2'),
            title: '特别篇 2',
            sectionTitle: 'SP',
            bvid: 'BV1ab411c7mD',
            cid: '2002',
          ),
        ],
      );
      var selected = season.episodes[1000];
      await tester.pumpWidget(
        InputTestApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => PgcEpisodePanel(
                season: season,
                selected: selected,
                onSelect: (episode) => update(() => selected = episode),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('选集 (1001/1277)'), findsOneWidget);
      expect(find.byKey(const ValueKey('pgc-episode-e1001')), findsOneWidget);
      expect(find.byKey(const ValueKey('pgc-episode-e1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pgc-episode-order')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pgc-episode-e1001')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pgc-episode-view')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pgc-episode-e1001')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pgc-section-SP')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pgc-episode-sp2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pgc-episode-sp2')));
      await tester.pumpAndSettle();
      expect(selected.episodeId, 'sp2');
      expect(find.text('选集 (1277/1277)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('episode viewport grows rows for compact double-scale text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 650);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      InputTestApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: PgcEpisodePanel(
              season: _season,
              selected: _season.episodes.first,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListView>(find.byKey(const ValueKey('pgc-episode-list')))
          .itemExtent,
      88,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('intro state and player survive compact and collapsed layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 450);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repo = _Repo();
    final auth = _Auth();
    addTearDown(auth.dispose);
    var created = 0;
    var disposed = 0;
    PgcSeasonSummary? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pgcRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: PgcScreen(
              seasonId: 's1',
              onOpenSeason: (summary) => opened = summary,
              playerBuilder: (_, _, episode) => _TrackedPlayer(
                title: episode.displayTitle,
                onCreate: () => created++,
                onDispose: () => disposed++,
              ),
              commentsBuilder: (_, _, _) => const Text('评论区已接入'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pgc-episode-order')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换为正序'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('pgc-related-s2')));
    await tester.tap(find.byKey(const ValueKey('pgc-related-s2')));
    expect(opened?.seasonId, 's2');
    final introScroll = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('pgc-intro')))
        .controller;
    introScroll?.jumpTo(40);
    await tester.pump();
    expect(introScroll?.offset, 40);
    await tester.tap(find.byKey(const ValueKey('pgc-tab-评论')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(480, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开影视信息'), findsOneWidget);
    expect(created, 1);
    expect(disposed, 0);
    await tester.tap(find.byTooltip('展开影视信息'));
    await tester.pumpAndSettle();
    expect(find.text('评论区已接入'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pgc-tab-简介')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换为正序'), findsOneWidget);
    expect(introScroll?.offset, 40);
    await tester.tap(find.byTooltip('收起影视信息'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1200, 450);
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开影视信息'), findsOneWidget);
    expect(created, 1);
    expect(disposed, 0);
    await tester.tap(find.byTooltip('展开影视信息'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换为正序'), findsOneWidget);
    expect(introScroll?.offset, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh binding reloads retained episode during loading and when restricted',
    (tester) async {
      final repo = _Repo();
      final pending = Completer<PgcSeason>();
      repo.pending = pending;
      final auth = _Auth();
      final active = ValueNotifier<bool>(true);
      final settings = _SettingsRepo(
        AppSettings(
          shortcuts: ShortcutSettings(
            overrides: const {
              ShortcutAction.refresh: ['F8', 'MouseForward'],
            },
          ),
        ),
      );
      addTearDown(() {
        auth.dispose();
        active.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pgcRepositoryProvider.overrideWithValue(repo),
            authRepositoryProvider.overrideWithValue(auth),
            settingsRepositoryProvider.overrideWithValue(settings),
          ],
          child: InputTestApp(
            shortcuts: settings.value.shortcuts,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(settingsControllerProvider);
                  return ValueListenableBuilder<bool>(
                    valueListenable: active,
                    builder: (context, isActive, _) => WorkspaceActivity(
                      active: isActive,
                      child: PgcScreen(
                        episodeId: 'e3',
                        playerBuilder: (_, _, _) => const SizedBox(),
                        commentsBuilder: (_, _, _) => const TextField(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(repo.reads, 1);
      expect(repo.lastEpisodeId, const PgcEpisodeId('e3'));
      final oldCancellation = repo.lastCancellation;
      repo.pending = null;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(repo.reads, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(oldCancellation?.isCancelled, true);
      expect(repo.lastEpisodeId, const PgcEpisodeId('e3'));
      expect(find.text('会员专享'), findsWidgets);
      pending.complete(_season);
      await tester.pump();
      final pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kForwardMouseButton,
      );
      await pointer.down(
        tester.getCenter(find.byKey(const ValueKey('pgc-tab-简介'))),
      );
      await pointer.up();
      await tester.pumpAndSettle();
      expect(repo.reads, 3);
      await tester.tap(find.byKey(const ValueKey('pgc-tab-评论')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pump();
      expect(repo.reads, 3);
      FocusManager.instance.primaryFocus?.unfocus();
      active.value = false;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pump();
      expect(repo.reads, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh binding recovers detail error without a player', (
    tester,
  ) async {
    final repo = _Repo()
      ..failure = const AppFailure(AppFailureKind.network, '详情错误');
    final auth = _Auth();
    final settings = _SettingsRepo(const AppSettings.defaults());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pgcRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: PgcScreen(
              seasonId: 's1',
              playerBuilder: (_, _, _) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('详情错误'), findsOneWidget);
    repo.failure = null;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(repo.reads, 2);
    expect(find.text('测试番剧'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

final class _Repo implements PgcRepository {
  String scope = 'guest';
  int epoch = 0;
  int reads = 0;
  Completer<PgcSeason>? pending;
  Object? failure;
  RequestCancellation? lastCancellation;
  PgcEpisodeId? lastEpisodeId;
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    required RequestCancellation cancellation,
  }) {
    reads++;
    lastCancellation = cancellation;
    lastEpisodeId = episodeId;
    if (failure case final Object error) return Future<PgcSeason>.error(error);
    return pending?.future ?? Future.value(_season);
  }
}

final class _SettingsRepo implements SettingsRepository {
  _SettingsRepo(this.value);
  AppSettings value;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

final class _Auth implements AuthRepository {
  final controller = StreamController<AuthState>.broadcast(sync: true);
  AuthState state = const AuthState();
  void emit(AuthState next) {
    state = next;
    controller.add(next);
  }

  void dispose() => controller.close();
  @override
  AuthState get current => state;
  @override
  Stream<AuthState> get changes => controller.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async {}
}

final class _TrackedPlayer extends StatefulWidget {
  const _TrackedPlayer({
    required this.title,
    required this.onCreate,
    required this.onDispose,
  });
  final String title;
  final VoidCallback onCreate, onDispose;
  @override
  State<_TrackedPlayer> createState() => _TrackedPlayerState();
}

final class _TrackedPlayerState extends State<_TrackedPlayer> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Text(widget.title, style: const TextStyle(color: Colors.white)),
  );
}
