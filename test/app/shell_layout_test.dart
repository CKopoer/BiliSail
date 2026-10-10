import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keyboard height changes retain active and hidden page widgets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BiliAppShell(
          location: '/video/BV1abc123456',
          navigationMode: WorkspaceNavigationMode.singlePage,
          pageBuilder: (_, tab) {
            builds++;
            return SizedBox.expand(key: ValueKey('page-${tab.location.path}'));
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('page-/video/BV1abc123456'));
    final element = tester.element(active);
    final before = tester.getSize(active);
    builds = 0;
    for (final inset in [100.0, 200.0, 320.0, 160.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      expect(builds, 0);
      expect(tester.element(active), same(element));
      expect(tester.getSize(active).height, before.height - inset);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final dark in [false, true]) {
    testWidgets('home labels follow font changes in dark=$dark', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [375.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 800);
        Element? firstTab;
        for (final (font, family) in [
          (AppFontPreference.harmonyOsSans, ''),
          (AppFontPreference.installed, 'Microsoft YaHei'),
          (AppFontPreference.installed, 'Segoe UI'),
          (AppFontPreference.system, ''),
          (AppFontPreference.harmonyOsSans, ''),
        ]) {
          final theme = (dark ? BiliTheme.dark : BiliTheme.light)(
            font: font,
            systemFontFamily: family,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const BiliAppShell(location: '/', child: SizedBox.expand()),
            ),
          );
          await tester.pumpAndSettle();
          for (final channel in HomeChannel.values) {
            final tab = find.byKey(ValueKey('channel-${channel.name}'));
            final label = find.descendant(
              of: find.descendant(of: tab, matching: find.text(channel.label)),
              matching: find.byType(RichText),
            );
            final style = tester
                .renderObject<RenderParagraph>(label)
                .text
                .style;
            expect(
              style?.fontFamily,
              theme.textTheme.labelLarge?.fontFamily,
              reason: '${channel.name} font=$font family=$family width=$width',
            );
            expect(style?.fontSize, 14);
            expect(style?.fontWeight, FontWeight.w500);
          }
          final element = tester.element(
            find.byKey(const ValueKey('channel-recommended')),
          );
          firstTab ??= element;
          expect(element, same(firstTab));
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
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
