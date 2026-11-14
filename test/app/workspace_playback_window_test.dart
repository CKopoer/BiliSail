import 'dart:async';
import 'dart:io';

import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/shared/ui/responsive_layout_scope.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/native_window_events.dart';
import '../support/window_service_fake.dart';

void main() {
  testWidgets('detached playback navigator receives updated layout settings', (
    tester,
  ) async {
    Widget build(int threshold) => WorkspacePlaybackWindow(
      shortcuts: const ShortcutSettings.defaults(),
      theme: ThemeData(),
      responsiveLayout: ResponsiveLayoutSettings(
        playbackSideBySideWidth: threshold,
      ),
      onBack: () {},
      onClose: () {},
      onActivateBrowser: () {},
      child: Builder(
        builder: (context) => Text(
          'threshold ${ResponsiveLayoutScope.of(context).playbackSideBySideWidth}',
        ),
      ),
    );
    await tester.pumpWidget(build(900));
    await tester.pumpAndSettle();
    expect(find.text('threshold 900'), findsOneWidget);
    await tester.pumpWidget(build(1200));
    await tester.pumpAndSettle();
    expect(find.text('threshold 1200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Apple playback window uses configured tab shortcuts', (
    tester,
  ) async {
    var activations = 0, backs = 0;
    var shortcuts = const ShortcutSettings.defaults(useAppleDefaults: true);
    Widget build() => WorkspacePlaybackWindow(
      shortcuts: shortcuts,
      theme: ThemeData(),
      onBack: () => backs++,
      onClose: () {},
      onActivateBrowser: () => activations++,
      child: const SizedBox.expand(),
    );
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(activations, 2);
    shortcuts = shortcuts.withKeys(ShortcutAction.nextTab, ['Meta+K']);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(activations, 3);
    expect(backs, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('native frame follows app theme independently of system theme', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    final themes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setPlaybackTitleBar') themes.add(call.arguments);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    final window = WindowService.forView(
      viewId: 52,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    Widget build(ThemeData theme) => WindowServiceScope(
      service: window,
      child: WorkspacePlaybackWindow(
        shortcuts: const ShortcutSettings.defaults(),
        theme: theme,
        onBack: () {},
        onClose: () {},
        onActivateBrowser: () {},
        child: const SizedBox.expand(),
      ),
    );
    final dark = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xff151f29),
    );
    await tester.pumpWidget(build(dark));
    await tester.pumpAndSettle();
    expect(themes, [
      {'viewId': 52, 'dark': true, 'backgroundColor': 0x151f29},
    ]);
    themes.clear();
    await tester.pumpWidget(build(dark));
    await tester.pumpAndSettle();
    expect(themes, isEmpty);
    await tester.pumpWidget(
      build(
        ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xfff5f7fb),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(themes, [
      {'viewId': 52, 'dark': false, 'backgroundColor': 0xf5f7fb},
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets(
    'caption Back respects modal isolation and keeps one content row',
    (tester) async {
      final calls = <MethodCall>[];
      for (final channel in [
        'bilisail/desktop_window',
        'bilisail/text_input',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (call) async {
            calls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel(channel),
            null,
          ),
        );
      }
      var backs = 0;
      var homes = 0;
      final service = FakePlaybackWindowService(
        viewId: 42,
        setFullScreen: (_) async {},
        activate: () async {},
      );
      await tester.pumpWidget(
        WindowServiceScope(
          service: service,
          child: WorkspacePlaybackWindow(
            shortcuts: const ShortcutSettings.defaults(),
            theme: ThemeData(),
            onBack: () => backs++,
            onHome: () => homes++,
            onClose: () {},
            onActivateBrowser: () {},
            child: const SizedBox.expand(key: ValueKey('playback-content')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playback-window-back')), findsNothing);
      expect(find.text('浏览窗口'), findsNothing);
      final captionHeight = Platform.isWindows ? 44.0 : 0.0;
      expect(
        tester.getSize(find.byKey(const ValueKey('playback-content'))),
        Size(
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
          tester.view.physicalSize.height / tester.view.devicePixelRatio -
              captionHeight,
        ),
      );
      expect(calls.any((call) => call.method == 'setBackButton'), isTrue);
      await sendNativeWindowBack(tester, 42);
      expect(backs, 1);
      await sendNativeWindowHome(tester, 42);
      expect(homes, 1);

      unawaited(
        showDialog<void>(
          context: tester.element(
            find.byKey(const ValueKey('playback-content')),
          ),
          builder: (_) => const AlertDialog(content: Text('modal')),
        ),
      );
      await tester.pumpAndSettle();
      await sendNativeWindowBack(tester, 42);
      await sendNativeWindowHome(tester, 42);
      expect(backs, 1);
      expect(homes, 1);
      expect(find.text('modal'), findsOneWidget);
      Navigator.of(tester.element(find.text('modal'))).pop();
      await tester.pumpAndSettle();
      await sendNativeWindowBack(tester, 42);
      expect(backs, 2);
      if (Platform.isWindows) {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('playback-window-caption')))
              .height,
          44,
        );
        await tester.tap(find.byTooltip('返回上一视频'));
        expect(backs, 3);
        await tester.tap(find.byTooltip('回到主页'));
        expect(homes, 2);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await sendNativeWindowBack(tester, 42);
      await sendNativeWindowHome(tester, 42);
      expect(backs, Platform.isWindows ? 3 : 2);
      expect(homes, Platform.isWindows ? 2 : 1);
      expect(calls.any((call) => call.method == 'removeBackButton'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
