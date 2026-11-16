import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/live/presentation/live_super_chat_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unrelated rebuilds do not postpone an active countdown tick', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 11);
    DateTime clock() => now;
    final expiry = now.add(const Duration(seconds: 5));
    Widget frame(int price) => MaterialApp(
      home: Scaffold(
        body: LiveSuperChatCard(
          message: LiveSuperChatMessage(
            id: '1',
            userName: '观众',
            text: 'SC',
            price: price,
            expiresAt: expiry,
          ),
          clock: clock,
        ),
      ),
    );
    await tester.pumpWidget(frame(30));
    for (var index = 0; index < 4; index++) {
      now = now.add(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(frame(31 + index));
    }
    now = now.add(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('4s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'bubble and card show remaining seconds without unrelated rebuilds',
    (tester) async {
      var now = DateTime.utc(2026, 10, 7);
      final message = LiveSuperChatMessage(
        id: '1',
        userName: '观众',
        text: 'SC 内容',
        price: 30,
        startedAt: now.subtract(const Duration(seconds: 58)),
        expiresAt: now.add(const Duration(milliseconds: 1500)),
      );
      var parentBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                parentBuilds++;
                return Column(
                  children: [
                    LiveSuperChatBubble(
                      message: message,
                      selected: false,
                      onPressed: () {},
                      clock: () => now,
                    ),
                    LiveSuperChatCard(message: message, clock: () => now),
                  ],
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('2s'), findsNWidgets(2));
      final before = parentBuilds;
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1s'), findsNWidgets(2));
      expect(parentBuilds, before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('hidden countdown stops ticking and catches up when shown', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 7);
    final message = LiveSuperChatMessage(
      id: '1',
      userName: '观众',
      text: 'SC',
      price: 30,
      expiresAt: now.add(const Duration(seconds: 10)),
    );
    Future<void> show(bool enabled) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: enabled,
            child: LiveSuperChatCard(message: message, clock: () => now),
          ),
        ),
      ),
    );
    await show(true);
    expect(find.text('10s'), findsOneWidget);
    await show(false);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('10s'), findsOneWidget);
    await show(true);
    expect(find.text('7s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unknown lifetime has no invented countdown and narrow card keeps author link',
    (tester) async {
      var opened = false;
      const message = LiveSuperChatMessage(
        id: '1',
        userName: '观众',
        text: 'SC',
        price: 30,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: LiveSuperChatCard(
                    message: message,
                    onOpenUser: () => opened = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining(RegExp(r'^\d+s$')), findsNothing);
      await tester.tap(find.text('观众'));
      expect(opened, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
