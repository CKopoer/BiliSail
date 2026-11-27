import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/video_cover_repository.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/shared/application/video_cover43.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/responsive_layout_scope.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/primary_switch_app.dart' show SwitchHomeRepository;

VideoId _id(int index) => VideoId('BV${index.toString().padLeft(10, '0')}');
final _cover = Uri.parse('https://i0.hdslb.com/4x3.jpg');

void main() {
  test('waits for capacity and resolves each batch independently', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [videoCoverRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final providers = [
      for (var index = 1; index <= 62; index++)
        videoCover43Provider(_id(index)),
    ];
    for (final provider in providers) {
      container.listen(provider, (_, _) {});
    }
    final scrolledAway = container.listen(
      videoCover43Provider(_id(63)),
      (_, _) {},
    );
    expect(scrolledAway.read().isLoading, isTrue);
    scrolledAway.close();
    await container.pump();
    final results = [
      for (final provider in providers) container.read(provider.future),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(container.read(providers.last).isLoading, isTrue);
    expect(repository.calls.single.ids, [for (var i = 1; i <= 30; i++) _id(i)]);
    repository.calls.single.result.complete({_id(1): _cover});
    expect(await results.first, _cover);
    expect(await results[1], isNull);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.last.ids, [for (var i = 31; i <= 60; i++) _id(i)]);
    repository.calls.last.result.completeError(
      const AppFailure(AppFailureKind.network, '网络失败'),
    );
    expect(await Future.wait(results.skip(30).take(30)), everyElement(isNull));
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.last.ids, [_id(61), _id(62)]);
    repository.calls.last.result.complete({_id(62): _cover});
    expect(await Future.wait(results.skip(60)), [null, _cover]);
    expect(repository.calls, hasLength(3));
  });

  testWidgets('unattempted covers wait out the endpoint cooldown', (
    tester,
  ) async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [videoCoverRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final first = videoCover43Provider(_id(1));
    final next = videoCover43Provider(_id(2));
    container.listen(first, (_, _) {});
    await tester.pump(const Duration(milliseconds: 1));
    container.listen(next, (_, _) {});
    repository.cover43Cooldown = const Duration(seconds: 30);
    repository.calls.single.result.completeError(
      const AppFailure(AppFailureKind.rateLimited, '限流'),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(container.read(first).requireValue, isNull);
    expect(container.read(next).isLoading, isTrue);
    expect(repository.calls, hasLength(1));
    repository.cover43Cooldown = Duration.zero;
    await tester.pump(const Duration(seconds: 1));
    expect(repository.calls.last.ids, [_id(2)]);
    repository.calls.last.result.complete({_id(2): _cover});
    await tester.pump();
    expect(container.read(next).requireValue, _cover);
  });

  test(
    'an obsolete scope cancels its batch and discards late results',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [videoCoverRepositoryProvider.overrideWithValue(repository)],
      );
      final provider = videoCover43Provider(_id(1));
      container.listen(provider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final old = repository.calls.single;
      container.dispose();
      expect(old.cancellation.isCancelled, isTrue);
      old.result.complete({_id(1): _cover});
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, hasLength(1));
    },
  );

  test('a new session cancels the old batch for the same video', () async {
    final repository = _Repository();
    var epoch = 0;
    final container = ProviderContainer(
      overrides: [
        videoCoverRepositoryProvider.overrideWithValue(repository),
        videoCoverSessionEpochProvider.overrideWith((ref) => epoch),
      ],
    );
    addTearDown(container.dispose);
    final id = _id(1);
    final provider = videoCover43Provider(id);
    container.listen(provider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final old = repository.calls.single;
    epoch++;
    container.invalidate(videoCoverSessionEpochProvider);
    final current = container.read(provider.future);
    await Future<void>.delayed(Duration.zero);
    expect(old.cancellation.isCancelled, isTrue);
    expect(repository.calls, hasLength(2));
    old.result.complete({id: _cover});
    repository.calls.last.result.complete({});
    expect(await current, isNull);
  });

  testWidgets(
    'the shared video grid independently chooses each cover after a partial batch',
    (tester) async {
      final repository = _Repository();
      final ratio = ValueNotifier(CardCoverRatio.widescreen);
      final embeddedCover = Uri.parse('https://i1.hdslb.com/embedded4x3.jpg');
      addTearDown(ratio.dispose);
      final items = [
        for (var index = 1; index <= 4; index++)
          VideoSummary(
            id: index == 4 ? const VideoId('app:bangumi:1') : _id(index),
            title: '视频$index',
            coverUrl: 'https://i0.hdslb.com/ordinary$index.jpg',
            cover43Url: index == 3 ? embeddedCover : null,
            author: 'UP',
            duration: const Duration(minutes: 1),
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoCoverRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: ratio,
                builder: (_, value, _) => ResponsiveLayoutScope(
                  settings: ResponsiveLayoutSettings.defaults(
                    cardCoverRatio: value,
                  ),
                  child: CustomScrollView(
                    slivers: [SliverVideoGrid(items: items, onOpen: (_) {})],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Finder coverImage(int index) => find.descendant(
        of: find.byKey(ValueKey((items[index].id, index))),
        matching: find.byType(AppCoverImage),
      );
      String coverUrl(int index) =>
          tester.widget<AppCoverImage>(coverImage(index)).url;
      await tester.pump();
      expect(repository.calls, isEmpty);
      expect(coverUrl(0), items[0].coverUrl);
      ratio.value = CardCoverRatio.standard;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls.single.ids, [_id(1), _id(2)]);
      expect(find.byType(VideoCard), findsNWidgets(4));
      expect(coverImage(0), findsNothing);
      expect(coverImage(1), findsNothing);
      expect(coverUrl(2), embeddedCover.toString());
      expect(coverUrl(3), items[3].coverUrl);
      repository.calls.single.result.complete({_id(1): _cover});
      await tester.pumpAndSettle();
      expect(coverUrl(0), _cover.toString());
      expect(coverUrl(1), items[1].coverUrl);
    },
  );

  for (final channel in [HomeChannel.watchLater, HomeChannel.recommended]) {
    testWidgets('$channel waits for its own covers during a long scroll', (
      tester,
    ) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoCoverRepositoryProvider.overrideWithValue(repository),
            homeRepositoryProvider.overrideWithValue(SwitchHomeRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ResponsiveLayoutScope(
                settings: const ResponsiveLayoutSettings.defaults(
                  cardCoverRatio: CardCoverRatio.standard,
                ),
                child: channel == HomeChannel.watchLater
                    ? const HomeContent(
                        channel: HomeChannel.watchLater,
                        section: '全部',
                        isSignedIn: true,
                      )
                    : CustomScrollView(
                        slivers: [
                          FeedVideoGrid(
                            channel: channel,
                            items: [
                              for (var i = 0; i < 160; i++)
                                VideoSummary(
                                  id: _id(i),
                                  title: '视频$i',
                                  coverUrl: 'https://i0.hdslb.com/wide$i.jpg',
                                  author: 'UP',
                                  duration: Duration.zero,
                                ),
                            ],
                            onReject: (_) {},
                            onUndo: (_) {},
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final cards = find.byType(VideoCard);
      final visited = <VideoId>{};
      for (var step = 0; visited.length < 85 && step < 40; step++) {
        position.jumpTo(position.pixels + 500);
        await tester.pumpAndSettle();
        visited.addAll(
          tester.widgetList<VideoCard>(cards).map((c) => c.video.id),
        );
      }
      expect(visited.length, greaterThanOrEqualTo(85));
      expect(repository.calls, hasLength(1));
      expect(find.byType(AppCoverImage), findsNothing);

      Uri coverFor(VideoId id) =>
          Uri.https('i0.hdslb.com', '/${id.value}-43.jpg');
      for (var i = 0; i < repository.calls.length; i++) {
        final call = repository.calls[i];
        expect(call.ids.length, inInclusiveRange(1, 30));
        call.result.complete({for (final id in call.ids) id: coverFor(id)});
        await tester.pumpAndSettle();
      }
      for (final card in tester.widgetList<VideoCard>(cards)) {
        final image = find.descendant(
          of: find.byWidget(card),
          matching: find.byType(AppCoverImage),
        );
        expect(
          tester.widget<AppCoverImage>(image).url,
          coverFor(card.video.id).toString(),
        );
      }
    });
  }

  testWidgets(
    'home and search cards share a batch when their workspace is active',
    (tester) async {
      final repository = _Repository();
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      final id = _id(1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoCoverRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: active,
                builder: (_, value, _) => WorkspaceActivity(
                  active: value,
                  child: ResponsiveLayoutScope(
                    settings: const ResponsiveLayoutSettings.defaults(
                      cardCoverRatio: CardCoverRatio.standard,
                    ),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 168,
                              child: HomeVideoCard(
                                entry: HomeEntry(
                                  id: id.value,
                                  bvid: id.value,
                                  coverUrl: Uri.https(
                                    'i0.hdslb.com',
                                    '/wide.jpg',
                                  ),
                                  title: '稍后再看',
                                  kind: HomeEntryKind.video,
                                ),
                                onTap: () {},
                              ),
                            ),
                          ),
                        ),
                        SliverVideoGrid(
                          items: [
                            VideoSummary(
                              id: id,
                              title: '搜索结果',
                              coverUrl: 'https://i0.hdslb.com/wide.jpg',
                              author: '',
                              duration: Duration.zero,
                            ),
                          ],
                          onOpen: (_) {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(repository.calls, isEmpty);
      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls.single.ids, [id]);
      repository.calls.single.result.complete({});
      await tester.pumpAndSettle();
      expect(find.byType(AppCoverImage), findsNWidgets(2));
      active.value = false;
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls, hasLength(2));
      expect(find.byType(AppCoverImage), findsNothing);
      repository.calls.last.result.complete({id: _cover});
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AppCoverImage>(find.byType(AppCoverImage))
            .map((it) => it.url),
        [_cover.toString(), _cover.toString()],
      );
    },
  );
}

final class _Repository implements VideoCoverRepository {
  @override
  Duration cover43Cooldown = Duration.zero;

  final calls =
      <
        ({
          List<VideoId> ids,
          RequestCancellation cancellation,
          Completer<Map<VideoId, Uri>> result,
        })
      >[];

  @override
  Future<Map<VideoId, Uri>> loadCover43Urls(
    List<VideoId> ids, {
    required RequestCancellation cancellation,
  }) {
    final result = Completer<Map<VideoId, Uri>>();
    calls.add((ids: ids, cancellation: cancellation, result: result));
    return result.future;
  }
}
