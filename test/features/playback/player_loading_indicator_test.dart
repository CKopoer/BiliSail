import 'package:bilisail/features/playback/presentation/player_loading_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget indicator({
  bool preparing = false,
  bool deferPreparation = false,
  bool recovering = false,
  bool buffering = false,
  int source = 0,
}) => MaterialApp(
  home: PlayerLoadingIndicator(
    key: ValueKey(source),
    preparing: preparing,
    deferPreparation: deferPreparation,
    recovering: recovering,
    buffering: buffering,
  ),
);

void main() {
  testWidgets(
    'featured switches hide a short warm handoff and show a sustained cold open',
    (tester) async {
      await tester.pumpWidget(
        indicator(preparing: true, deferPreparation: true),
      );
      await tester.pump(const Duration(milliseconds: 175));
      expect(find.text('正在准备音视频…'), findsNothing);
      await tester.pumpWidget(indicator(deferPreparation: true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(
        indicator(preparing: true, deferPreparation: true, source: 2),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在准备音视频…'), findsOneWidget);
    },
  );

  testWidgets('preparation and recovery have immediate distinct hints', (
    tester,
  ) async {
    await tester.pumpWidget(indicator(preparing: true));
    expect(find.text('正在准备音视频…'), findsOneWidget);
    await tester.pumpWidget(indicator(recovering: true));
    expect(find.text('正在准备音视频…'), findsNothing);
    expect(find.text('正在恢复播放…'), findsOneWidget);
    await tester.pumpWidget(indicator());
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('short native buffering pulses never show a loading overlay', (
    tester,
  ) async {
    await tester.pumpWidget(indicator(buffering: true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(indicator());
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sustained buffering shows once and clears immediately', (
    tester,
  ) async {
    await tester.pumpWidget(indicator(buffering: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('播放缓冲中…'), findsOneWidget);
    expect(find.text('网络缓冲中…'), findsNothing);
    expect(find.text('正在准备音视频…'), findsNothing);
    await tester.pumpWidget(indicator());
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('source replacement and disposal retire pending indicators', (
    tester,
  ) async {
    await tester.pumpWidget(indicator(buffering: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(indicator(buffering: true, source: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
