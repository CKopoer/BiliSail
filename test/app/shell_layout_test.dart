import 'package:bilisail/app/shell.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets(
      'messages hide home navigation across resizing in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: BiliAppShell(
              location: '/messages',
              navigationMode: mode,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(key: ValueKey('message-content')),
            ),
          ),
        );
        for (final width in [320.0, 759.0, 760.0, 1200.0, 400.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('home-channel-strip')),
            findsNothing,
          );
          expect(find.byIcon(Icons.account_circle), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-search')),
            findsOneWidget,
          );
          expect(find.byTooltip('观看历史'), findsOneWidget);
          expect(find.byTooltip('下载'), findsOneWidget);
          expect(find.byTooltip('设置'), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('message-content'))).dy,
            (width < 760 ? 52 : 58) +
                (defaultTargetPlatform == TargetPlatform.windows ? 42 : 0),
          );
          expect(tester.takeException(), isNull, reason: 'window width $width');
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );
  }
  testWidgets('shell fits narrow and wide windows at double text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in [400.0, 720.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const BiliAppShell(location: '/', child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'window width $width');
      expect(find.byKey(const ValueKey('channel-recommended')), findsOneWidget);
    }
  });
}
