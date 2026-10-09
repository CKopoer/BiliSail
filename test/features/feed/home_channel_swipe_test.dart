import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/home_channel_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the pager preserves desktop scrollbars and inner mouse dragging',
    (tester) async {
      _viewport(tester);
      final channel = ValueNotifier(HomeChannel.recommended);
      addTearDown(channel.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final changes = <HomeChannel>[];
      await tester.pumpWidget(
        _app(
          channel,
          changes.add,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          ),
          child: Theme(
            data: ThemeData(platform: TargetPlatform.windows),
            child: ListView.builder(
              controller: scroll,
              itemCount: 100,
              itemBuilder: (_, index) =>
                  SizedBox(height: 60, child: Text('$index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget);
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -240),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(100));
      expect(changes, isEmpty);
    },
  );

  testWidgets('pages follow the finger and a short swipe animates back', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.recommended);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    await tester.pumpWidget(_app(channel, changes.add));
    channel.value = HomeChannel.popular;
    await tester.pumpAndSettle();
    channel.value = HomeChannel.recommended;
    await tester.pumpAndSettle();
    final recommended = find.byKey(const ValueKey('page-recommended'));
    final popular = find.byKey(const ValueKey('page-popular'));
    final surface = find.byKey(const ValueKey('home-channel-swipe'));
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(tester.getRect(recommended).left, closeTo(-80, 1));
    expect(tester.getRect(popular).left, closeTo(295, 1));
    expect(changes, isEmpty);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getRect(recommended).left, inExclusiveRange(-80, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(recommended).left, closeTo(0, 0.1));
    expect(changes, isEmpty);
  });

  testWidgets(
    'a full swipe animates into the incoming page before committing',
    (tester) async {
      _viewport(tester);
      final channel = ValueNotifier(HomeChannel.recommended);
      addTearDown(channel.dispose);
      final changes = <HomeChannel>[];
      await tester.pumpWidget(_app(channel, changes.add));
      channel.value = HomeChannel.popular;
      await tester.pumpAndSettle();
      channel.value = HomeChannel.recommended;
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('home-channel-swipe'));
      final incoming = find.byKey(const ValueKey('page-popular'));
      final gesture = await tester.startGesture(tester.getCenter(surface));
      await gesture.moveBy(const Offset(-220, 0));
      await tester.pump();
      expect(tester.getRect(incoming).left, closeTo(155, 1));
      expect(channel.value, HomeChannel.recommended);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getRect(incoming).left, inExclusiveRange(0, 155));
      expect(changes, isEmpty);
      await tester.pumpAndSettle();
      expect(tester.getRect(incoming).left, closeTo(0, 0.1));
      expect(changes, [HomeChannel.popular]);
    },
  );

  testWidgets('non-adjacent taps animate only between the source and target', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.recommended);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    await tester.pumpWidget(_app(channel, changes.add));
    channel.value = HomeChannel.favorites;
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final outgoing = find.byKey(const ValueKey('page-recommended'));
    final incoming = find.byKey(const ValueKey('page-favorites'));
    expect(tester.getRect(outgoing).left, inExclusiveRange(-375, 0));
    expect(tester.getRect(incoming).left, inExclusiveRange(0, 375));
    expect(find.byKey(const ValueKey('page-popular')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.getRect(incoming).left, closeTo(0, 0.1));
    expect(changes, isEmpty);
  });

  for (final reverse in [false, true]) {
    testWidgets('a new swipe takes over an unfinished snap: reverse=$reverse', (
      tester,
    ) async {
      _viewport(tester);
      final channel = ValueNotifier(HomeChannel.recommended);
      addTearDown(channel.dispose);
      final changes = <HomeChannel>[];
      await tester.pumpWidget(_app(channel, changes.add));
      final surface = find.byKey(const ValueKey('home-channel-swipe'));
      final position = _pagePosition(tester);
      final first = await tester.startGesture(tester.getCenter(surface));
      await first.moveBy(const Offset(-220, 0));
      await tester.pump();
      await first.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(position.isScrollingNotifier.value, isTrue);
      final interruptedPixels = position.pixels;
      final second = await tester.startGesture(tester.getCenter(surface));
      await tester.pump();
      await tester.pump();
      expect(changes, isEmpty);
      expect(position.pixels, closeTo(interruptedPixels, .1));
      final dx = reverse ? 220.0 : -350.0;
      await second.moveBy(Offset(dx, 0));
      await tester.pump();
      expect(position.pixels, closeTo(interruptedPixels - dx, 1));
      await second.up();
      await tester.pumpAndSettle();
      expect(
        channel.value,
        reverse ? HomeChannel.recommended : HomeChannel.dynamic,
      );
      expect(changes, reverse ? isEmpty : [HomeChannel.dynamic]);
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'holding an unfinished snap then releasing or cancelling: cancel=$cancel',
      (tester) async {
        _viewport(tester);
        final channel = ValueNotifier(HomeChannel.recommended);
        addTearDown(channel.dispose);
        final changes = <HomeChannel>[];
        await tester.pumpWidget(_app(channel, changes.add));
        final surface = find.byKey(const ValueKey('home-channel-swipe'));
        await tester.drag(surface, const Offset(-220, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        final position = _pagePosition(tester);
        final interruptedPixels = position.pixels;
        final hold = await tester.startGesture(tester.getCenter(surface));
        await tester.pump(const Duration(milliseconds: 100));
        expect(changes, isEmpty);
        expect(position.pixels, closeTo(interruptedPixels, .1));
        if (cancel) {
          await hold.cancel();
        } else {
          await hold.up();
        }
        await tester.pumpAndSettle();
        expect(
          channel.value,
          cancel ? HomeChannel.recommended : HomeChannel.popular,
        );
        expect(changes, cancel ? isEmpty : [HomeChannel.popular]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a new drag supersedes a queued settled selection', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.recommended);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    await tester.pumpWidget(_app(channel, changes.add));
    final surface = find.byKey(const ValueKey('home-channel-swipe'));
    final first = await tester.startGesture(tester.getCenter(surface));
    await first.moveBy(const Offset(-375, 0));
    await tester.pump();
    await first.up();
    // The first selection is queued for the next frame; a new drag starts
    // before that callback can update the route and reset its controller.
    final second = await tester.startGesture(tester.getCenter(surface));
    await second.moveBy(const Offset(-220, 0));
    await tester.pump();
    await tester.pump();
    expect(changes, isEmpty);
    expect(_pagePosition(tester).pixels, closeTo(595, 1));
    await second.up();
    await tester.pumpAndSettle();
    expect(channel.value, HomeChannel.dynamic);
    expect(changes, [HomeChannel.dynamic]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion skips tap animation and rapid taps end on target',
    (tester) async {
      _viewport(tester);
      final channel = ValueNotifier(HomeChannel.recommended);
      addTearDown(channel.dispose);
      final changes = <HomeChannel>[];
      await tester.pumpWidget(
        _app(channel, changes.add, disableAnimations: true),
      );
      channel.value = HomeChannel.live;
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('page-live'))).left, 0);
      await tester.pumpWidget(_app(channel, changes.add));
      channel.value = HomeChannel.favorites;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      channel.value = HomeChannel.popular;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('page-popular'))).left,
        0,
      );
      expect(changes, isEmpty);
    },
  );

  testWidgets('touch swipes move one channel and stop at both ends', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.recommended);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    await tester.pumpWidget(
      _app(channel, (value) {
        changes.add(value);
        channel.value = value;
      }),
    );
    final surface = find.byKey(const ValueKey('home-channel-swipe'));
    await tester.drag(surface, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.drag(surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    await tester.drag(surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(changes, [HomeChannel.popular, HomeChannel.dynamic]);
    await tester.drag(surface, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(channel.value, HomeChannel.popular);
    channel.value = HomeChannel.favorites;
    await tester.pump();
    await tester.drag(surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(channel.value, HomeChannel.favorites);
  });

  testWidgets('short, cancelled and mouse drags do not navigate', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.popular);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    await tester.pumpWidget(_app(channel, changes.add));
    final surface = find.byKey(const ValueKey('home-channel-swipe'));
    await tester.timedDrag(
      surface,
      const Offset(-35, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(changes, isEmpty, reason: 'short drag');
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(-240, 0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(changes, isEmpty, reason: 'cancelled drag');
    await tester.drag(
      surface,
      const Offset(-240, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.fling(surface, const Offset(-60, 0), 1000);
    await tester.pumpAndSettle();
    expect(changes, [HomeChannel.dynamic]);
  });

  testWidgets('hidden pages and a channel change cancel an in-flight swipe', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.popular);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    await tester.pumpWidget(_app(channel, changes.add));
    final surface = find.byKey(const ValueKey('home-channel-swipe'));
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(-240, 0));
    channel.value = HomeChannel.live;
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.pumpWidget(_app(channel, changes.add, active: false));
    await tester.drag(surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('nested horizontal scrolling and vertical refresh win gestures', (
    tester,
  ) async {
    _viewport(tester);
    final channel = ValueNotifier(HomeChannel.popular);
    addTearDown(channel.dispose);
    final changes = <HomeChannel>[];
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    var refreshes = 0;
    await tester.pumpWidget(
      _app(
        channel,
        changes.add,
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: SingleChildScrollView(
                key: const ValueKey('inner-strip'),
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: const SizedBox(width: 2000, height: 60),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => refreshes++,
                child: ListView.builder(
                  key: const ValueKey('inner-list'),
                  controller: vertical,
                  itemCount: 100,
                  itemBuilder: (_, index) =>
                      SizedBox(height: 60, child: Text('item $index')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('inner-strip')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    expect(horizontal.offset, greaterThan(100));
    final list = find.byKey(const ValueKey('inner-list'));
    await tester.drag(list, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(vertical.offset, greaterThan(100));
    vertical.jumpTo(0);
    await tester.pump();
    await tester.drag(list, const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(changes, isEmpty);
    await tester.drag(list, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(changes, [HomeChannel.dynamic]);
  });
}

Widget _app(
  ValueNotifier<HomeChannel> channel,
  ValueChanged<HomeChannel> onChanged, {
  bool active = true,
  bool disableAnimations = false,
  ScrollBehavior? scrollBehavior,
  Widget child = const SizedBox.expand(),
}) {
  final contentChannel = channel.value;
  return MaterialApp(
    scrollBehavior: scrollBehavior,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: disableAnimations),
      child: child ?? const SizedBox.shrink(),
    ),
    home: Scaffold(
      body: WorkspaceActivity(
        active: active,
        child: ValueListenableBuilder(
          valueListenable: channel,
          builder: (_, value, _) => HomeChannelSwipe(
            channel: value,
            onChanged: (value) {
              onChanged(value);
              channel.value = value;
            },
            pageBuilder: (_, channel, _) => SizedBox.expand(
              key: ValueKey('page-${channel.name}'),
              child: channel == contentChannel
                  ? child
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ScrollPosition _pagePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('home-channel-swipe')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;
