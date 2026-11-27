import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/video_cover_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/shared/application/video_cover43.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/responsive_layout_scope.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

VideoId _id(int index) => VideoId('BV${index.toString().padLeft(10, '0')}');
final _cover = Uri.parse('https://i0.hdslb.com/4x3.jpg');

void main() {
  test(
    'coalesces requests, sends at most 30 and falls back after failure',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [videoCoverRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final providers = [
        for (var index = 1; index <= 32; index++)
          videoCover43Provider(_id(index)),
      ];
      for (final provider in providers) {
        container.listen(provider, (_, _) {});
      }
      final results = [
        for (final provider in providers) container.read(provider.future),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls.single.ids, [
        for (var i = 1; i <= 30; i++) _id(i),
      ]);
      repository.calls.single.result.complete({_id(1): _cover});
      expect(await results.first, _cover);
      expect(await results[1], isNull);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls.last.ids, [_id(31), _id(32)]);
      repository.calls.last.result.completeError(
        const AppFailure(AppFailureKind.network, '网络失败'),
      );
      expect(await Future.wait(results.skip(30)), [null, null]);
      expect(repository.calls, hasLength(2));
    },
  );

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
                              coverUrl: '',
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
      repository.calls.single.result.complete({id: _cover});
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
