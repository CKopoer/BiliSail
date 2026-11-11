import 'dart:async';

import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/presentation/video_collection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

VideoPart _part(int number) => VideoPart(
  cid: '$number',
  page: number,
  title: '分 P $number',
  duration: const Duration(minutes: 1),
);

VideoDetail _video({int current = 40, bool unknownParts = false}) =>
    VideoDetail(
      summary: VideoSummary(
        id: VideoId('BV${current.toString().padLeft(10, '0')}'),
        title: '当前视频',
        coverUrl: '',
        author: 'UP',
        duration: const Duration(minutes: 10),
      ),
      description: '',
      parts: List.generate(12, (index) => _part(index + 1)),
      collection: VideoCollection(
        id: '1',
        title: '测试合集',
        entries: List.generate(
          80,
          (index) => VideoCollectionEntry(
            id: VideoId('BV${index.toString().padLeft(10, '0')}'),
            title: '合集视频 $index',
            parts: unknownParts && index == 0 ? const [] : [_part(1), _part(2)],
          ),
        ),
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  VideoDetail video, {
  double width = 356,
  double textScale = 1,
  Future<VideoDetail>? pendingDetail,
  VoidCallback? onTogglePlaybackOrder,
}) async {
  var displayReversed = false;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        if (pendingDetail != null)
          videoDetailProvider(video.collection!.entries.first.id)
              .overrideWith((_) => pendingDetail),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SizedBox(
                width: width,
                child: StatefulBuilder(
                  builder: (_, update) => VideoCollectionPanel(
                    video: video,
                    selected: video.parts[9],
                    onSelectPart: (_) {},
                    onTogglePlaybackOrder: onTogglePlaybackOrder,
                    displayReversed: displayReversed,
                    onToggleDisplayOrder: () =>
                        update(() => displayReversed = !displayReversed),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollController _controller(WidgetTester tester) => tester
    .widget<ListView>(
      find.descendant(
        of: find.byType(VideoCollectionPanel),
        matching: find.byType(ListView),
      ),
    )
    .controller!;

Future<void> _tap(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

void _expectVisible(WidgetTester tester, String title) {
  final item = tester.getRect(find.text(title));
  final viewport = tester.getRect(find.byType(ListView));
  expect(item.top, greaterThanOrEqualTo(viewport.top));
  expect(item.bottom, lessThanOrEqualTo(viewport.bottom));
}

void main() {
  for (final reversed in [false, true]) {
    testWidgets('collection jumps respect display reversed=$reversed', (
      tester,
    ) async {
      var playbackToggles = 0;
      final video = _video();
      await _pump(
        tester,
        video,
        onTogglePlaybackOrder: () => playbackToggles++,
      );
      if (reversed) await _tap(tester, '倒序');
      expect(playbackToggles, 0);
      final controller = _controller(tester);
      await _tap(tester, '跳至顶部');
      expect(controller.offset, 0);
      _expectVisible(tester, '合集视频 ${reversed ? 79 : 0}');

      final entry = find
          .ancestor(
            of: find.text('合集视频 ${reversed ? 79 : 0}'),
            matching: find.byType(Material),
          )
          .first;
      await tester.tap(
        find.descendant(of: entry, matching: find.byTooltip('展开分 P')),
      );
      await tester.pumpAndSettle();
      await _tap(tester, '跳至底部');
      expect(controller.offset, controller.position.maxScrollExtent);
      _expectVisible(tester, '合集视频 ${reversed ? 0 : 79}');

      await _tap(tester, '跳至当前');
      _expectVisible(tester, 'P10 分 P 10');
      // The current part can be far below its collection heading.
      expect(find.text('合集视频 40'), findsNothing);
      await _tap(tester, '倒序播放');
      expect(playbackToggles, 1);
      _expectVisible(tester, 'P10 分 P 10');
      expect(video.collection!.entries.first.title, '合集视频 0');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loaded nested parts retain exact long-distance positioning', (
    tester,
  ) async {
    final video = _video(unknownParts: true);
    final pending = Completer<VideoDetail>();
    await _pump(tester, video, pendingDetail: pending.future);
    await _tap(tester, '跳至顶部');
    final first = find
        .ancestor(of: find.text('合集视频 0'), matching: find.byType(Material))
        .first;
    await tester.tap(
      find.descendant(of: first, matching: find.byTooltip('展开分 P')),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(video);
    await tester.pumpAndSettle();
    await _tap(tester, '跳至底部');
    _expectVisible(tester, '合集视频 79');
    await _tap(tester, '跳至当前');
    _expectVisible(tester, 'P10 分 P 10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar wraps on narrow layouts with large text', (
    tester,
  ) async {
    final video = _video();
    await _pump(tester, video, width: 240, textScale: 2);
    for (final tooltip in ['跳至顶部', '跳至底部', '跳至当前', '倒序播放', '倒序']) {
      expect(find.byTooltip(tooltip), findsOneWidget);
    }
    await _tap(tester, '跳至底部');
    _expectVisible(tester, '合集视频 79');
    await _tap(tester, '倒序');
    await _tap(tester, '跳至当前');
    _expectVisible(tester, 'P10 分 P 10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing current entry disables locating and playback changes', (
    tester,
  ) async {
    await _pump(tester, _video(current: 90));
    for (final tooltip in ['跳至当前', '倒序播放']) {
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthState();
}
