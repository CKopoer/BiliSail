import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/home_channel_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('touch swipes move one channel and stop at both ends', (
    tester,
  ) async {
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
    expect(changes, isEmpty, reason: 'short drag');
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(-240, 0));
    await gesture.cancel();
    expect(changes, isEmpty, reason: 'cancelled drag');
    await tester.drag(
      surface,
      const Offset(-240, 0),
      kind: PointerDeviceKind.mouse,
    );
    expect(changes, isEmpty);
    await tester.fling(surface, const Offset(-60, 0), 1000);
    expect(changes, [HomeChannel.dynamic]);
  });

  testWidgets('hidden pages and a channel change cancel an in-flight swipe', (
    tester,
  ) async {
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
    expect(changes, isEmpty);
    await tester.pumpWidget(_app(channel, changes.add, active: false));
    await tester.drag(surface, const Offset(-240, 0));
    expect(changes, isEmpty);
  });

  testWidgets('nested horizontal scrolling and vertical refresh win gestures', (
    tester,
  ) async {
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
    expect(changes, [HomeChannel.dynamic]);
  });
}

Widget _app(
  ValueNotifier<HomeChannel> channel,
  ValueChanged<HomeChannel> onChanged, {
  bool active = true,
  Widget child = const SizedBox.expand(),
}) => MaterialApp(
  home: Scaffold(
    body: WorkspaceActivity(
      active: active,
      child: ValueListenableBuilder(
        valueListenable: channel,
        builder: (_, value, _) => HomeChannelSwipe(
          channel: value,
          onChanged: onChanged,
          child: child,
        ),
      ),
    ),
  ),
);
