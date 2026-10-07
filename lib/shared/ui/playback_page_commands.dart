import 'package:flutter/widgets.dart';

import '../../core/input/input_stroke.dart';
import '../../core/input/shortcut_dispatcher.dart';
import '../../domain/shortcut_command.dart';
import '../../core/presentation/input_scope.dart';
import '../../core/presentation/workspace_activity.dart';

class PlaybackPageCommands extends StatelessWidget {
  const PlaybackPageCommands({
    super.key,
    required this.previousPart,
    required this.nextPart,
    required this.toggleInfo,
    required this.child,
  });
  final VoidCallback previousPart, nextPart, toggleInfo;
  final Widget child;
  static PlaybackPageCommands? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PageCommands>()?.commands;
  @override
  Widget build(BuildContext context) => CommandTargetScope<Object>(
    scope: CommandScope.page,
    active: WorkspaceActivity.isActive(context),
    commands: {
      for (final (command, action) in [
        (ShortcutAction.previousPart, previousPart),
        (ShortcutAction.nextPart, nextPart),
        (ShortcutAction.fullWindow, toggleInfo),
      ])
        command: (stroke) {
          if (stroke.phase != InputPhase.down) return CommandOutcome.noOp;
          if (command == ShortcutAction.fullWindow) {
            InputScope.of<Object>(context)?.dispatcher.beforeNavigation();
          }
          action();
          return CommandOutcome.completed;
        },
    },
    child: _PageCommands(commands: this, child: child),
  );
}

class _PageCommands extends InheritedWidget {
  const _PageCommands({required this.commands, required super.child});
  final PlaybackPageCommands commands;
  @override
  bool updateShouldNotify(_PageCommands oldWidget) => true;
}
