import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browser and playback dialogs stay inside their native windows', (
    tester,
  ) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    final baseline = PlatformDispatcher.instance.views.length;
    final errors = <Object>[];
    final browser = GlobalKey<NavigatorState>();
    final playback = GlobalKey<NavigatorState>();
    final contexts = <String, BuildContext>{};
    await WindowService().initialize();

    Widget page(String label) => Builder(
      builder: (context) {
        contexts[label] = context;
        return Scaffold(
          body: TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('$label dialog'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('close'),
                  ),
                ],
              ),
            ),
            child: Text('open $label'),
          ),
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: browser,
        home: DesktopPlaybackWindow(
          onCloseRequested: () {},
          onError: errors.add,
          playback: MaterialApp(navigatorKey: playback, home: page('playback')),
          child: page('browser'),
        ),
      ),
    );
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (contexts['playback'] case final context?) {
        if (View.of(context).viewId !=
            PlatformDispatcher.instance.implicitView!.viewId) {
          break;
        }
      }
    }
    await tester.pumpAndSettle();
    expect(errors, isEmpty);
    expect(PlatformDispatcher.instance.views.length, baseline + 1);
    expect(
      View.of(contexts['playback']!).viewId,
      isNot(View.of(contexts['browser']!).viewId),
    );
    for (final label in ['browser', 'playback']) {
      await tester.tap(find.text('open $label'));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('$label dialog'));
      expect(View.of(context), same(View.of(contexts[label]!)));
      expect(
        Navigator.of(context),
        same(label == 'browser' ? browser.currentState : playback.currentState),
      );
      expect(PlatformDispatcher.instance.views.length, baseline + 1);
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      expect(find.text('$label dialog'), findsNothing);
      expect(PlatformDispatcher.instance.views.length, baseline + 1);
    }
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (PlatformDispatcher.instance.views.length == baseline) break;
    }
    expect(PlatformDispatcher.instance.views.length, baseline);
    expect(tester.takeException(), isNull);
  });
}
