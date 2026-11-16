import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/presentation/input_scope.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';

void main() {
  testWidgets('retained empty scopes do not exhaust command capacity', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    final calls = <int>[];
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      InputTestApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (context, value, _) => Column(
              children: [
                for (var index = 0; index < 140; index++)
                  CommandTargetScope<Object>(
                    scope: CommandScope.page,
                    commands: {
                      if (index == value)
                        ShortcutAction.refresh: (stroke) {
                          if (stroke.phase != InputPhase.down) {
                            return CommandOutcome.noOp;
                          }
                          calls.add(index);
                          return CommandOutcome.completed;
                        },
                    },
                    child: const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    selected.value = 139;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    selected.value = -1;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    selected.value = 0;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(calls, [0, 139, 0]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
