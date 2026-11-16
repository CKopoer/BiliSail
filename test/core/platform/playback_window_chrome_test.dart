import '../../support/material_tooltip_finder.dart';

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/desktop_window_chrome.dart';
import 'package:bilisail/core/platform/playback_window_chrome.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  const channel = MethodChannel('window_manager');

  for (final dark in [false, true]) {
    testWidgets(
      'main and playback captions match at desktop widths, dark=$dark',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => false,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final window = _Window();
        for (final width in [420.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 844);
          for (final scale in [1.0, 1.5]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BiliTheme.dark() : BiliTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: BiliAppShell(
                          location: '/search?q=test',
                          navigationMode: WorkspaceNavigationMode.dualTabs,
                          windowControlsBuilder: (_) =>
                              const DesktopWindowControls(),
                          dragRegionBuilder: (_, child) => child,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      PlaybackWindowChrome(
                        window: window,
                        onBack: () {},
                        onHome: () {},
                        onClose: () {},
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final main = find.byKey(const ValueKey('dual-window-caption'));
            final playback = find.byKey(
              const ValueKey('playback-window-caption'),
            );
            expect(tester.getSize(main).height, 44);
            expect(tester.getSize(main), tester.getSize(playback));
            expect(
              tester.widget<Text>(find.text('哔帆')).style,
              tester.widget<Text>(find.text('哔帆 · 播放')).style,
            );
            for (final (mainTooltip, playbackTooltip) in [
              ('返回上一页', '返回上一视频'),
              ('最小化', '最小化'),
              ('最大化', '最大化'),
              ('关闭窗口', '关闭播放'),
            ]) {
              final mainButton = find.descendant(
                of: main,
                matching: findMaterialTooltip(mainTooltip),
              );
              final playbackButton = find.descendant(
                of: playback,
                matching: findMaterialTooltip(playbackTooltip),
              );
              expect(tester.getSize(mainButton), const Size(46, 44));
              expect(
                tester.getSize(mainButton),
                tester.getSize(playbackButton),
              );
              expect(
                tester
                    .widget<Icon>(
                      find.descendant(
                        of: mainButton,
                        matching: find.byType(Icon),
                      ),
                    )
                    .size,
                18,
              );
            }
            if (width >= 600) {
              for (final key in [
                'workspace-sidebar-toggle',
                'workspace-return-to-playback',
              ]) {
                final button = find.byKey(ValueKey(key));
                expect(tester.getSize(button), const Size(46, 44));
                expect(tester.getCenter(button).dy, tester.getCenter(main).dy);
              }
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$width scale=$scale',
            );
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('main caption keeps window actions and maximize events', (
    tester,
  ) async {
    final calls = <String>[];
    var maximized = false;
    final previousListeners = windowManager.listeners;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return switch (call.method) {
        'isMaximized' => maximized,
        'isMinimized' => false,
        _ => null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: DesktopWindowControls(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(findMaterialTooltip('最小化'));
    await tester.pumpAndSettle();
    expect(calls, contains('minimize'));
    await tester.tap(findMaterialTooltip('最大化'));
    await tester.pumpAndSettle();
    expect(calls, contains('maximize'));
    Future<void> sendMaximized(bool value) async {
      maximized = value;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {
            'eventName': value ? 'maximize' : 'unmaximize',
          }),
        ),
        null,
      );
      await tester.pumpAndSettle();
    }

    await sendMaximized(true);
    expect(findMaterialTooltip('还原'), findsOneWidget);
    await tester.tap(findMaterialTooltip('还原'));
    await tester.pumpAndSettle();
    expect(calls, contains('unmaximize'));
    await sendMaximized(false);
    expect(findMaterialTooltip('最大化'), findsOneWidget);
    await tester.tap(findMaterialTooltip('关闭窗口'));
    await tester.pumpAndSettle();
    expect(calls, contains('close'));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(windowManager.listeners, previousListeners);
    expect(tester.takeException(), isNull);
  });

  testWidgets('44px caption routes controls and drag to its own window', (
    tester,
  ) async {
    final window = _Window();
    var backs = 0;
    var homes = 0;
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: PlaybackWindowChrome(
              window: window,
              onBack: () => backs++,
              onHome: () => homes++,
              onClose: () => closes++,
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('playback-window-caption')))
          .height,
      44,
    );
    for (final tooltip in ['返回上一视频', '回到主页', '最小化', '最大化', '关闭播放']) {
      expect(tester.getSize(findMaterialTooltip(tooltip)).height, 44);
      await tester.tap(findMaterialTooltip(tooltip));
    }
    expect(backs, 1);
    expect(homes, 1);
    expect(closes, 1);
    expect(window.minimizes, 1);
    expect(window.maximizes, 1);
    window.updateWindowPresentation(
      maximized: true,
      minimized: false,
      fullScreen: false,
    );
    await tester.pump();
    expect(findMaterialTooltip('还原'), findsOneWidget);
    final drag = find.byKey(const ValueKey('playback-window-drag-region'));
    await tester.drag(drag, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(window.drags, 1);
    await tester.tap(drag);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(drag);
    await tester.pumpAndSettle();
    expect(window.maximizes, 2);
    expect(tester.takeException(), isNull);
  });
}

class _Window extends WindowService {
  var drags = 0;
  var minimizes = 0;
  var maximizes = 0;

  @override
  Future<void> startDraggingPlaybackWindow() async => drags++;

  @override
  Future<void> minimizePlaybackWindow() async => minimizes++;

  @override
  Future<void> togglePlaybackWindowMaximized() async => maximizes++;
}
