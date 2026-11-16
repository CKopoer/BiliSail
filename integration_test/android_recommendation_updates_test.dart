import 'dart:ui' as ui;

import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/primary_switch_app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile recommendation append and single-card feedback', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 480, 270),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(480, 270), [
          Colors.blue,
          Colors.amber,
        ]),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 270);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final fixture = PrimarySwitchFixture(
      data!.buffer.asUint8List(),
      feed: _UpdatingFeed(),
    );
    image.dispose();
    picture.dispose();
    await tester.pumpWidget(fixture.app);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    );
    final controller = container.read(feedControllerProvider.notifier);
    final video = container
        .read(feedControllerProvider)
        .items
        .requireValue
        .first;
    final timings = <ui.FrameTiming>[];
    final samples = <Map<String, Object>>[];
    void collect(List<ui.FrameTiming> frames) => timings.addAll(frames);
    Future<void> settle() async {
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
    }

    // Warm each update path and drain delayed FrameTiming batches.
    await controller.loadMore();
    await settle();
    await controller.rejectRecommendation(video);
    await settle();
    await controller.undoRecommendationFeedback(video.id);
    await settle();
    binding.addTimingsCallback(collect);
    try {
      for (var round = 0; round < 8; round++) {
        for (final (name, action) in <(String, Future<void> Function())>[
          ('append', controller.loadMore),
          ('reject', () => controller.rejectRecommendation(video)),
          ('undo', () => controller.undoRecommendationFeedback(video.id)),
        ]) {
          timings.clear();
          await action();
          await settle();
          samples.add({
            'target': name,
            'uiUs': timings.map((f) => f.buildDuration.inMicroseconds).toList(),
            'rasterUs': timings
                .map((f) => f.rasterDuration.inMicroseconds)
                .toList(),
          });
          expect(
            container.read(feedControllerProvider).rejected.contains(video.id),
            name == 'reject',
          );
        }
      }
    } finally {
      binding.removeTimingsCallback(collect);
    }
    binding.reportData = {
      'recommendationUpdates': {
        'label': const String.fromEnvironment(
          'SWITCH_LABEL',
          defaultValue: 'current',
        ),
        'samples': samples,
        'feedReads': fixture.feed.reads,
        'refreshRate':
            ui.PlatformDispatcher.instance.views.first.display.refreshRate,
      },
    };
    expect(samples.every((s) => (s['uiUs']! as List).isNotEmpty), isTrue);
    expect(
      container.read(feedControllerProvider).items.requireValue.length,
      480,
    );
    expect(fixture.feed.reads, 10);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await fixture.dispose();
  });
}

// All feedback is in memory; this fixture never issues account writes.
class _UpdatingFeed extends SwitchFeedRepository
    implements RecommendationFeedbackRepository {
  @override
  String get feedbackScope => 'fixture';

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    final start = page == 1 ? 0 : 300 + (page - 2) * 20;
    return PageResult(
      items: List.generate(page == 1 ? 300 : 20, (offset) {
        final i = start + offset;
        return VideoSummary(
          id: VideoId('BV1abc${i.toString().padLeft(6, '0')}'),
          title: '推荐视频 $i：分页追加与局部反馈性能测试',
          author: '测试作者',
          coverUrl: 'https://i0.hdslb.com/switch-cover-$i.png',
          duration: const Duration(minutes: 3),
          recommendationReason: '推荐理由',
          recommendationFeedback: RecommendationFeedback(
            aid: '$i',
            goto: 'av',
            trackId: 'fixture',
            ownerMid: '7',
          ),
        );
      }),
      hasMore: true,
    );
  }

  @override
  Future<void> rejectRecommendation(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) async {}

  @override
  Future<void> undoRecommendationFeedback(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) async {}
}
