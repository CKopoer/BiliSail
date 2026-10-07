import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'live popularity decimal text uses thousand, ten-thousand and hundred-million units',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final (text, label) in [
          ('0', '0'),
          ('999', '999'),
          ('1000', '1.0千'),
          ('1234', '1.2千'),
          ('10000', '1.0万'),
          ('12345', '1.2万'),
          ('100000000', '1.0亿'),
          ('123456789', '1.2亿'),
        ]) {
          await tester.pumpWidget(_app(text));
          expect(find.text('♨ $label'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape('♨ $label'))),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'live popularity preserves server abbreviations and unknown text',
    (tester) async {
      for (final text in ['1.23千', '8万', '2.34亿', '—', '未知']) {
        await tester.pumpWidget(_app(text));
        expect(find.text('♨ $text'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('live popularity omits missing or blank count', (tester) async {
    for (final text in ['', '   ']) {
      await tester.pumpWidget(_app(text));
      expect(find.textContaining('♨'), findsNothing);
      expect(find.text('直播标题'), findsOneWidget);
      expect(find.text('单机游戏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compact live popularity retains narrow card navigation', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      _app('12345', width: 140, scale: 2, onTap: () => opens++),
    );
    expect(find.text('♨ 1.2万'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('直播标题'));
    expect(opens, 1);
  });
}

Widget _app(
  String popularity, {
  double width = 320,
  double scale = 1,
  VoidCallback? onTap,
}) => MaterialApp(
  theme: BiliTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Center(
        child: SizedBox(
          width: width,
          child: LiveRoomCard(
            entry: HomeEntry(
              id: '7777',
              title: '直播标题',
              kind: HomeEntryKind.live,
              authorName: '直播作者',
              popularityText: popularity,
              areaName: '单机游戏',
            ),
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  ),
);
