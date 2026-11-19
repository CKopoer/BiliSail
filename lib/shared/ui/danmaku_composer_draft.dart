import 'package:material_ui/material_ui.dart';

/// Keeps the player's draft when its inline editor is replaced by a dialog.
class DanmakuComposerDraft extends InheritedWidget {
  const DanmakuComposerDraft({
    super.key,
    required this.controller,
    required this.clearSent,
    required super.child,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> clearSent;
  final bool autofocus;

  static TextEditingController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DanmakuComposerDraft>()
      ?.controller;

  static ValueChanged<String>? clearSentOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DanmakuComposerDraft>()?.clearSent;

  static bool autofocusOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DanmakuComposerDraft>()
          ?.autofocus ??
      false;

  @override
  bool updateShouldNotify(DanmakuComposerDraft oldWidget) =>
      controller != oldWidget.controller || autofocus != oldWidget.autofocus;
}
