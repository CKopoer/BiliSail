import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/recommendation_cover43.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/responsive_layout_scope.dart';
import 'package:bilisail/shared/ui/video_card.dart';
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
        overrides: [feedRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final providers = [
        for (var index = 1; index <= 32; index++)
          recommendationCover43Provider((id: _id(index), epoch: 0)),
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
        overrides: [feedRepositoryProvider.overrideWithValue(repository)],
      );
      final provider = recommendationCover43Provider((id: _id(1), epoch: 0));
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

  testWidgets(
    '4:3 recommendation cards independently choose a cover after a partial batch result',
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
          overrides: [feedRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: ratio,
                builder: (_, value, _) => ResponsiveLayoutScope(
                  settings: ResponsiveLayoutSettings.defaults(
                    cardCoverRatio: value,
                  ),
                  child: CustomScrollView(
                    slivers: [
                      FeedVideoGrid(
                        items: items,
                        channel: HomeChannel.recommended,
                        onReject: (_) {},
                        onUndo: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Finder coverImage(int index) => find.descendant(
        of: find.byKey(ValueKey(items[index].id)),
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
}

final class _Repository
    implements FeedRepository, RecommendationCoverRepository {
  final calls =
      <
        ({
          List<VideoId> ids,
          RequestCancellation cancellation,
          Completer<Map<VideoId, Uri>> result,
        })
      >[];

  @override
  Future<Map<VideoId, Uri>> loadRecommendationCover43Urls(
    List<VideoId> ids, {
    required RequestCancellation cancellation,
  }) {
    final result = Completer<Map<VideoId, Uri>>();
    calls.add((ids: ids, cancellation: cancellation, result: result));
    return result.future;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
