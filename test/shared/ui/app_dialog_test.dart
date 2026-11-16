import 'dart:async';

import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_windowing.dart';
import '../../support/detached_window_fake.dart';

void main() {
  for (final windowing in [false, true]) {
    testWidgets(
      'dialog stays on its window Navigator (windowing: $windowing)',
      (tester) async {
        if (windowing) enableDesktopWindowing(tester);
        final browser = GlobalKey<NavigatorState>();
        final playback = GlobalKey<NavigatorState>();
        final routes = InputRouteObserver();
        final secondary = FakeSecondaryFlutterView(
          tester.view,
          viewId: 100,
          size: const Size(800, 600),
        );
        Future<int?>? result;
        late BuildContext source;
        const barrierColor = Color(0x66112233);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: browser,
            home: ViewAnchor(
              view: View(
                view: secondary,
                child: MaterialApp(
                  navigatorKey: playback,
                  navigatorObservers: [routes],
                  home: Theme(
                    data: ThemeData(
                      brightness: Brightness.dark,
                      dialogTheme: const DialogThemeData(
                        barrierColor: barrierColor,
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        source = context;
                        return Scaffold(
                          body: TextButton(
                            onPressed: () {
                              result = showAppDialog<int>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  content: const Text('window dialog'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, 42),
                                      child: const Text('confirm'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Text('open'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              child: const Scaffold(body: Text('browser')),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final context = tester.element(find.text('window dialog'));
        expect(Navigator.of(context), same(playback.currentState));
        expect(View.of(context), same(View.of(source)));
        expect(browser.currentState!.canPop(), isFalse);
        expect(Theme.of(context).brightness, Brightness.dark);
        expect(routes.modal, isTrue);
        final route = ModalRoute.of(context)! as DialogRoute<int>;
        expect(route.barrierColor, barrierColor);
        expect(route.traversalEdgeBehavior, TraversalEdgeBehavior.closedLoop);
        await tester.tap(find.text('confirm'));
        await tester.pumpAndSettle();
        expect(await result, 42);
        expect(routes.modal, isFalse);
        expect(find.text('open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final useRoot in [false, true]) {
    testWidgets('nested navigation respects useRootNavigator: $useRoot', (
      tester,
    ) async {
      enableDesktopWindowing(tester);
      final root = GlobalKey<NavigatorState>();
      final nested = GlobalKey<NavigatorState>();
      late BuildContext source;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          home: Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) {
                source = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      unawaited(
        showAppDialog<void>(
          context: source,
          useRootNavigator: useRoot,
          builder: (_) => const AlertDialog(content: Text('nested dialog')),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('nested dialog'));
      expect(
        Navigator.of(context),
        same(useRoot ? root.currentState : nested.currentState),
      );
      Navigator.pop(context);
      await tester.pumpAndSettle();
      expect(find.text('nested dialog'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('barrier dismissal and Escape keep their dialog behavior', (
    tester,
  ) async {
    enableDesktopWindowing(tester);
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold(body: Text('page'));
          },
        ),
      ),
    );
    for (final dismissible in [true, false]) {
      unawaited(
        showAppDialog<void>(
          context: source,
          barrierDismissible: dismissible,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('dialog'), dismissible ? findsNothing : findsOneWidget);
      if (!dismissible) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('dialog'), findsOneWidget);
        Navigator.pop(tester.element(find.text('dialog')));
        await tester.pumpAndSettle();
      }
    }
    unawaited(
      showAppDialog<void>(
        context: source,
        builder: (_) => const AlertDialog(content: Text('Escape dialog')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Escape dialog'), findsNothing);
    expect(find.text('page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
