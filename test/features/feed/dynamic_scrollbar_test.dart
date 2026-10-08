import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final section in HomeChannel.dynamic.sections) {
    testWidgets(
      '$section range and thumb remain stable across mixed-height posts',
      (tester) async {
        await _mount(tester, section: section);
        final position = _position(tester);
        final extent = position.maxScrollExtent;
        final thumbScale = _painter(tester).getTrackToScroll(1);
        for (final offset in [
          300.0,
          1900.0,
          extent / 2,
          extent - 10,
          extent,
          extent / 3,
          1400.0,
          0.0,
        ]) {
          position.jumpTo(offset);
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump();
            expect(position.maxScrollExtent, closeTo(extent, .01));
            expect(position.pixels, closeTo(offset, .01));
            expect(
              _painter(tester).getTrackToScroll(1),
              closeTo(thumbScale, .01),
            );
          }
        }
        expect(
          find.byType(InteractiveDynamicPostCard).evaluate().length,
          lessThan(15),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mouse thumb follows continuous downward and upward dragging', (
    tester,
  ) async {
    await _mount(tester);
    final position = _position(tester);
    final extent = position.maxScrollExtent;
    final gesture = await tester.startGesture(
      const Offset(796, 12),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(796, 40));
    await tester.pump();
    var pointerY = 40.0;
    var thumbY = _painter(tester).getThumbScrollOffset();
    for (final nextY in [80.0, 140.0, 220.0, 320.0, 240.0, 140.0, 80.0]) {
      await gesture.moveTo(Offset(796, nextY));
      await tester.pump();
      final currentY = _painter(tester).getThumbScrollOffset();
      expect(currentY - thumbY, closeTo(nextY - pointerY, .1));
      expect(position.maxScrollExtent, closeTo(extent, .01));
      pointerY = nextY;
      thumbY = currentY;
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, closeTo(extent, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expanded posts survive eviction and a font/width layout change',
    (tester) async {
      final scaler = ValueNotifier<TextScaler>(TextScaler.noScaling);
      addTearDown(scaler.dispose);
      await _mount(tester, scaler: scaler);
      final position = _position(tester);
      final collapsed = position.maxScrollExtent;
      await tester.tap(find.text('展开全文').first);
      await tester.pumpAndSettle();
      final expanded = position.maxScrollExtent;
      expect(expanded, greaterThan(collapsed));
      position.jumpTo(6000);
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsNothing);
      expect(position.maxScrollExtent, closeTo(expanded, .01));
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      expect(position.maxScrollExtent, closeTo(expanded, .01));

      tester.view.physicalSize = const Size(430, 600);
      scaler.value = const TextScaler.linear(1.5);
      await tester.pumpAndSettle();
      final resized = position.maxScrollExtent;
      expect(resized, greaterThan(expanded));
      for (final offset in [6000.0, resized, 0.0]) {
        position.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(position.maxScrollExtent, closeTo(resized, .01));
      }
      expect(find.text('收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination extends the range once and preserves its earlier anchor',
    (tester) async {
      final repository = _Repository(_posts(24), hasMore: true);
      await _mount(tester, repository: repository);
      final position = _position(tester);
      position.jumpTo(500);
      await tester.pumpAndSettle();
      final offset = position.pixels;
      final extent = position.maxScrollExtent;
      final card = find.byType(InteractiveDynamicPostCard).at(1);
      final anchor = tester.getTopLeft(card);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeContent)),
      );
      final provider = homeControllerProvider((
        channel: HomeChannel.dynamic,
        section: '全部',
        scope: repository.accountScope,
        folderId: null,
      ));
      await container.read(provider.notifier).loadMore();
      await tester.pumpAndSettle();
      expect(container.read(provider).items.requireValue.length, 36);
      final appended = position.maxScrollExtent;
      expect(appended, greaterThan(extent));
      expect(position.pixels, closeTo(offset, .01));
      expect(tester.getTopLeft(card), anchor);
      for (final offset in [2000.0, appended, 0.0]) {
        position.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(position.maxScrollExtent, closeTo(appended, .01));
      }
      expect(repository.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(
  WidgetTester tester, {
  String section = '全部',
  _Repository? repository,
  ValueNotifier<TextScaler>? scaler,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeRepositoryProvider.overrideWithValue(
          repository ?? _Repository(_posts(60)),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.windows,
          scrollbarTheme: const ScrollbarThemeData(
            thumbVisibility: WidgetStatePropertyAll(true),
            thickness: WidgetStatePropertyAll(10),
          ),
        ),
        scrollBehavior: const SmoothScrollBehavior(),
        home: Scaffold(
          body: scaler == null
              ? HomeContent(
                  channel: HomeChannel.dynamic,
                  section: section,
                  isSignedIn: true,
                )
              : ValueListenableBuilder(
                  valueListenable: scaler,
                  builder: (context, value, _) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: value),
                    child: HomeContent(
                      channel: HomeChannel.dynamic,
                      section: section,
                      isSignedIn: true,
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

ScrollbarPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.foregroundPainter)
    .whereType<ScrollbarPainter>()
    .single;

List<DynamicPost> _posts(int count, {int start = 0}) {
  final images = [
    for (var i = 0; i < 9; i++) Uri.https('i0.hdslb.com', '/bfs/test-$i.png'),
  ];
  return [
    for (var i = start; i < start + count; i++)
      switch (i % 6) {
        0 => DynamicPost(
          id: '$i',
          authorName: 'Short post',
          text: 'Short text',
        ),
        1 => DynamicPost(
          id: '$i',
          authorName: 'Long post',
          text: List.filled(30, 'Long text on a separate line').join('\n'),
        ),
        2 => DynamicPost(
          id: '$i',
          authorName: 'Picture post',
          imageUrls: [images.first],
          imageAspectRatios: {images.first: 1.8},
        ),
        3 => DynamicPost(
          id: '$i',
          authorName: 'Tall picture',
          imageUrls: [images.first],
          imageAspectRatios: {images.first: .2},
        ),
        4 => DynamicPost(
          id: '$i',
          authorName: 'Nine pictures',
          imageUrls: images,
        ),
        _ => DynamicPost(
          id: '$i',
          authorName: 'Forwarded post',
          original: DynamicPost(
            id: 'original-$i',
            title: 'Original title',
            authorName: 'Original author',
            spans: [
              const DynamicTextSpan(text: 'Text and inline emoji '),
              DynamicTextSpan(
                kind: DynamicTextKind.emoji,
                text: '[emoji]',
                imageUrl: images.first,
                emojiSize: 2,
              ),
            ],
            video: const VideoSummary(
              id: VideoId('BV1234567890'),
              title: 'A video title',
              coverUrl: '',
              author: 'author',
              duration: Duration(minutes: 5),
            ),
            linkTitle: 'Link title',
            linkDescription: 'Link description',
            linkCoverUrl: images.first,
          ),
        ),
      },
  ];
}

class _Repository implements HomeRepository {
  _Repository(this.posts, {this.hasMore = false});
  final List<DynamicPost> posts;
  final bool hasMore;
  int calls = 0;
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    final result = page == 1 ? posts : _posts(12, start: posts.length);
    return HomePage(
      [
        for (final post in result)
          HomeEntry(
            id: post.id,
            title: '',
            kind: HomeEntryKind.dynamic,
            dynamicPost: post,
          ),
      ],
      hasMore: hasMore && page == 1,
      nextCursor: page == 1 ? 'next' : null,
    );
  }
}
