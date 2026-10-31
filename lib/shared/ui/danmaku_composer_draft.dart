import 'package:flutter/material.dart';

/// Keeps the player's draft when its inline editor is replaced by a dialog.
class DanmakuComposerDraft extends InheritedWidget {
  const DanmakuComposerDraft({
    super.key,
    required this.controller,
    required this.clearSent,
    required super.child,
  });

  final TextEditingController controller;
  final ValueChanged<String> clearSent;

  static TextEditingController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DanmakuComposerDraft>()
      ?.controller;

  static ValueChanged<String>? clearSentOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DanmakuComposerDraft>()?.clearSent;

  @override
  bool updateShouldNotify(DanmakuComposerDraft oldWidget) =>
      controller != oldWidget.controller;
}
