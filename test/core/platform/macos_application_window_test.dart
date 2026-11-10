import 'dart:async';

import 'package:bilisail/core/platform/macos_application_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/detached_window_fake.dart';

void main() {
  testWidgets('headless startup disables frames before window creation', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/application_window');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'prepareHeadlessStartup') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(
        call.method == 'prepareHeadlessStartup'
            ? AppLifecycleState.hidden
            : AppLifecycleState.resumed,
      );
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await MacOSApplicationWindow.prepareHeadlessStartupProbe();
    expect(tester.binding.lifecycleState, AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);
    final native = _window(tester, 41);
    addTearDown(native.dispose);
    await MacOSApplicationWindow(native).prepare();
    expect(calls, ['prepareHeadlessStartup', 'attachMainWindow']);
    expect(tester.binding.framesEnabled, isTrue);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'startup_probe_has_window'),
    );
    await expectLater(
      MacOSApplicationWindow.prepareHeadlessStartupProbe(),
      throwsA(isA<PlatformException>()),
    );
  });

  testWidgets('headless startup waits for the engine lifecycle message', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/application_window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    var completed = false;
    final pending = MacOSApplicationWindow.prepareHeadlessStartupProbe().then(
      (_) => completed = true,
    );
    await tester.idle();
    expect(completed, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.idle();
    await pending;
    expect(completed, isTrue);
    expect(tester.binding.framesEnabled, isFalse);
  });

  for (final state in [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets(
      'headless startup rejects a missing hidden transition: $state',
      (tester) async {
        const channel = MethodChannel('bilisail/application_window');
        tester.binding.handleAppLifecycleStateChanged(state);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final pending = expectLater(
          MacOSApplicationWindow.prepareHeadlessStartupProbe(),
          throwsA(isA<TimeoutException>()),
        );
        await tester.idle();
        await tester.pump(const Duration(seconds: 5));
        await pending;
      },
    );
  }

  testWidgets('main window handshake sends its own view identity', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/application_window');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final native = _window(tester, 41);
    addTearDown(native.dispose);
    final main = MacOSApplicationWindow(native);
    await main.prepare();
    expect(calls.single.method, 'attachMainWindow');
    expect(calls.single.arguments, {'viewId': 41, 'windowHandle': null});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'window_unavailable'),
    );
    await expectLater(main.prepare(), throwsA(isA<PlatformException>()));
  });

  testWidgets('explicit main and playback views retain the browser subtree', (
    tester,
  ) async {
    final primary = _window(tester, 41);
    final playback = _window(tester, 42);
    addTearDown(primary.dispose);
    addTearDown(playback.dispose);
    final main = MacOSApplicationWindow(primary);
    final browserKey = GlobalKey();
    var disposals = 0;
    Widget browser() => _Probe(
      key: browserKey,
      onDispose: () => disposals++,
      child: const SizedBox(key: ValueKey('browser')),
    );
    await tester.pumpWidget(main.wrap(browser()), wrapWithView: false);
    final element = tester.element(find.byKey(const ValueKey('browser')));
    expect(View.of(element).viewId, 41);
    expect(WindowServiceScope.maybeOf(element), same(main.service));

    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.pumpWidget(
        main.wrap(
          browser(),
          additionalView: playback.buildView(
            const SizedBox(key: ValueKey('playback')),
          ),
        ),
        wrapWithView: false,
      );
      expect(
        View.of(tester.element(find.byKey(const ValueKey('playback')))).viewId,
        42,
      );
      expect(
        tester.element(find.byKey(const ValueKey('browser'))),
        same(element),
      );
      expect(tester.widgetList<View>(find.byType(View)), hasLength(2));
      await tester.pumpWidget(main.wrap(browser()), wrapWithView: false);
      expect(
        tester.element(find.byKey(const ValueKey('browser'))),
        same(element),
      );
      expect(tester.widgetList<View>(find.byType(View)), hasLength(1));
      expect(disposals, 0);
    }
    await tester.pumpWidget(const SizedBox());
    expect(disposals, 1);
  });
}

FakeDetachedWindow _window(WidgetTester tester, int viewId) =>
    FakeDetachedWindow(
      mainView: tester.view,
      viewId: viewId,
      size: const Size(1120, 800),
      title: 'Main',
      onCloseRequested: () {},
    );

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.child, required this.onDispose});
  final Widget child;
  final VoidCallback onDispose;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
