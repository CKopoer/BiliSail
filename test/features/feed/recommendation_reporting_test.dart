import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/recommendation_card.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/recommendation_reporter.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../support/memory_settings_repository.dart';

RecommendationCard _card(int id, {int epoch = 0}) => RecommendationCard(
  source: RecommendationSource.web,
  epoch: epoch,
  id: '$id',
  goto: 'av',
  trackId: 'track-$id',
);

class _Repository extends Fake
    implements FeedRepository, RecommendationReportingRepository {
  final batches = <List<RecommendationEvent>>[];
  final signals = <RequestCancellation>[];
  final response = Completer<void>();
  @override
  Future<void> reportRecommendations(
    List<RecommendationEvent> events, {
    required RequestCancellation cancellation,
  }) {
    batches.add(events);
    signals.add(cancellation);
    return response.future;
  }
}

void main() {
  testWidgets(
    'slow delivery is bounded; stale impressions and failed batches are discarded',
    (tester) async {
      final repository = _Repository();
      var epoch = 0;
      final reporter = RecommendationReporter(
        repository,
        accepts: (card) => card.epoch == epoch,
      );
      void show(RecommendationCard card) => reporter.record(
        card,
        RecommendationInteraction.exposure,
        position: 1,
        row: 1,
        column: 1,
      );
      final first = _card(1);
      show(first);
      show(first);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.batches.single.single.card, same(first));
      for (var i = 2; i < 80; i++) {
        show(_card(i));
      }
      reporter.record(
        first,
        RecommendationInteraction.click,
        position: 1,
        row: 1,
        column: 1,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(repository.batches.length, 1);
      repository.response.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.batches.last.length, 32);
      expect(
        repository.batches.last.last.interaction,
        RecommendationInteraction.click,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(repository.batches.length, 2);
      show(_card(100));
      epoch++;
      await tester.pump(const Duration(seconds: 1));
      expect(repository.batches.length, 2);
      show(_card(101, epoch: epoch));
      reporter.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.batches.length, 2);
    },
  );

  testWidgets(
    'default reporting waits for settings, measures visible cards and does not delay navigation',
    (tester) async {
      final detector = VisibilityDetectorController.instance;
      final interval = detector.updateInterval;
      detector.updateInterval = Duration.zero;
      addTearDown(() => detector.updateInterval = interval);
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          feedRepositoryProvider.overrideWithValue(repository),
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(recommendationReporterProvider), isNull);
      final active = ValueNotifier(false);
      final scroll = ScrollController();
      addTearDown(active.dispose);
      addTearDown(scroll.dispose);
      final items = List.generate(
        60,
        (i) => VideoSummary(
          id: VideoId('BV${i.toString().padLeft(10, '0')}'),
          title: '推荐 $i',
          coverUrl: '',
          author: '',
          duration: Duration.zero,
          publishedAt: DateTime.utc(2026),
          recommendationCard: _card(i + 1),
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ValueListenableBuilder(
                valueListenable: active,
                builder: (_, visible, child) =>
                    WorkspaceActivity(active: visible, child: child!),
                child: CustomScrollView(
                  controller: scroll,
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
          GoRoute(
            path: '/video/:id',
            builder: (_, _) => const Scaffold(body: Text('播放页')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(recommendationReporterProvider), isNotNull);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.batches, isEmpty);

      active.value = true;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final visible = <String>{};
      final cards = find.byType(VideoCard);
      for (var i = 0; i < cards.evaluate().length; i++) {
        final rect = tester.getRect(cards.at(i));
        if (rect.intersect(viewport).height >= rect.height / 2) {
          visible.add(
            tester.widget<VideoCard>(cards.at(i)).video.recommendationCard!.id,
          );
        }
      }
      expect(visible, isNotEmpty);
      expect(repository.batches.single.map((e) => e.card.id).toSet(), visible);
      expect(visible.length, lessThan(cards.evaluate().length));

      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('推荐 0'));
      await tester.pumpAndSettle();
      expect(find.text('播放页'), findsOneWidget);
      expect(repository.batches.length, 1);
      repository.response.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final events = repository.batches.expand((b) => b);
      expect(events.where((e) => e.card.id == '1').map((e) => e.interaction), [
        RecommendationInteraction.exposure,
        RecommendationInteraction.click,
      ]);
      expect(tester.takeException(), isNull);
      await container
          .read(settingsControllerProvider.notifier)
          .setRecommendations(
            RecommendationSettings(reportInteractions: false),
          );
      expect(container.read(recommendationReporterProvider), isNull);
    },
  );

  testWidgets('disabling reporting cancels delivery and drops queued work', (
    tester,
  ) async {
    final repo = _Repository();
    final reporter = RecommendationReporter(repo, accepts: (_) => true);
    void click() => reporter.record(
      _card(1),
      RecommendationInteraction.click,
      position: 1,
      row: 1,
      column: 1,
    );
    click();
    await tester.pump(const Duration(seconds: 1));
    click();
    reporter.dispose();
    expect(repo.signals.single.isCancelled, isTrue);
    repo.response.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.batches.length, 1);
  });
}
