import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('HarmonyOS Sans');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      fonts.addFont(
        rootBundle.load(
          'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_$weight.ttf',
        ),
      );
    }
    await fonts.load();
  });

  for (final density in [1.0, 2.625]) {
    testWidgets(
      'tablet recommendation grid retains data across resizing at density=$density',
      (tester) async {
        _configure(tester, density);
        final repository = _OfflineFeed();
        await tester.pumpWidget(_app(repository));
        await tester.pumpAndSettle();
        final feed = tester.element(find.byType(FeedScreen));

        // Include portrait/landscape sizes and both sides of layout boundaries.
        for (final (size, columns, rail) in [
          (const Size(480, 900), 2, 0.0),
          (const Size(600, 960), 3, 76.0),
          (const Size(720, 1280), 3, 76.0),
          (const Size(800, 1280), 3, 76.0),
          (const Size(840, 1344), 3, 76.0),
          (const Size(960, 600), 3, 76.0),
          (const Size(1024, 600), 3, 76.0),
          (const Size(1180, 800), 3, 76.0),
          (const Size(1231, 900), 3, 76.0),
          (const Size(1232, 900), 4, 76.0),
          (const Size(1280, 800), 4, 76.0),
          (const Size(1440, 900), 4, 76.0),
          (const Size(1511, 960), 4, 76.0),
          (const Size(1512, 960), 5, 76.0),
          (const Size(1536, 960), 5, 76.0),
          (const Size(1599, 1000), 5, 76.0),
          (const Size(1600, 1000), 5, 164.0),
          (const Size(1920, 1080), 6, 164.0),
          (const Size(600, 960), 3, 76.0),
        ]) {
          tester.view.physicalSize = size * density;
          await tester.pumpAndSettle();
          _expectGrid(tester, columns, size.width);
          if (rail == 0) {
            expect(find.byType(NavigationBar), findsOneWidget);
          } else {
            expect(find.byType(NavigationBar), findsNothing);
            expect(
              tester
                  .getSize(
                    find.byKey(const ValueKey('workspace-side-navigation')),
                  )
                  .width,
              rail,
            );
          }
          expect(find.text('哔帆'), rail == 164 ? findsOneWidget : findsNothing);
          expect(tester.element(find.byType(FeedScreen)), same(feed));
          expect(
            repository.calls,
            1,
            reason: 'resizing must reuse loaded data',
          );
          expect(tester.takeException(), isNull, reason: '$size');
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('enlarged text reduces columns only when cards need more room', (
    tester,
  ) async {
    _configure(tester, 2);
    await tester.pumpWidget(_app(_OfflineFeed()));
    await tester.pumpAndSettle();
    for (final (width, scale, columns) in [
      (600.0, 1.3, 2),
      (800.0, 1.3, 3),
      (1024.0, 1.3, 3),
      (1280.0, 1.3, 3),
      (1543.0, 1.3, 3),
      (1544.0, 1.3, 4),
      (600.0, 2.0, 2),
      (800.0, 2.0, 2),
      (1024.0, 2.0, 3),
      (1280.0, 2.0, 3),
      (1440.0, 2.0, 3),
    ]) {
      tester.view.physicalSize = Size(width, 1000) * 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      _expectGrid(tester, columns, width);
      final titleContext = tester.element(find.text(_title(0)));
      expect(MediaQuery.textScalerOf(titleContext).scale(15), 15 * scale);
      expect(tester.takeException(), isNull, reason: '$width text=$scale');
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

void _configure(WidgetTester tester, double density) {
  tester.view.devicePixelRatio = density;
  tester.view.physicalSize = const Size(800, 1280) * density;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void _expectGrid(WidgetTester tester, int columns, double windowWidth) {
  final cards = find.byType(VideoCard);
  final first = tester.getRect(cards.first);
  final last = tester.getRect(cards.at(columns - 1));
  final next = tester.getRect(cards.at(columns));
  expect(last.top, closeTo(first.top, .01));
  expect(next.top, greaterThan(first.bottom));
  expect(last.right, lessThanOrEqualTo(windowWidth));
  final cover = tester.getSize(
    find.descendant(of: cards.first, matching: find.byType(AspectRatio)).first,
  );
  expect(cover.aspectRatio, closeTo(16 / 9, .01));
  final title = tester.getRect(find.text(_title(0)));
  final author = tester.getRect(
    find.descendant(of: cards.first, matching: find.text('离线布局样本')),
  );
  expect(title.bottom, lessThanOrEqualTo(author.top));
  expect(author.bottom, lessThanOrEqualTo(first.bottom));
}

String _title(int index) => '用于平板尺寸核查的长标题推荐视频 $index，包含中文与 English';

Widget _app(_OfflineFeed repository) => ProviderScope(
  overrides: [feedRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: BiliTheme.light(),
    home: const BiliAppShell(
      location: '/',
      navigationMode: WorkspaceNavigationMode.dualTabs,
      child: FeedScreen(),
    ),
  ),
);

final class _OfflineFeed implements FeedRepository {
  int calls = 0;

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [];

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    return PageResult(
      items: List.generate(
        12,
        (index) => VideoSummary(
          id: VideoId('BV1audit${index.toString().padLeft(4, '0')}'),
          title: _title(index),
          coverUrl: '',
          author: '离线布局样本',
          duration: const Duration(minutes: 123, seconds: 45),
          playCount: 1234567,
          danmakuCount: 12345,
          recommendationReason: '3万点赞',
        ),
      ),
      hasMore: false,
    );
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);
}
