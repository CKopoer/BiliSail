import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// SDK find.byTooltip uses RawTooltip semantics, and its fallback for excluded
// semantics still checks the SDK's old Material Tooltip type. Match the
// standalone Material widget directly, including tooltips whose parent already
// provides the accessible label.
Finder findMaterialTooltip(Pattern message, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) {
        String? text;
        if (widget is Tooltip) {
          final label =
              widget.message ?? widget.richMessage?.toPlainText() ?? '';
          if ((widget.excludeFromSemantics ?? false) || label.isEmpty) {
            text = label;
          }
        } else if (widget is RawTooltip) {
          text = widget.semanticsTooltip ?? '';
        }
        if (text == null) return false;
        return message is String
            ? text == message
            : message.allMatches(text).isNotEmpty;
      },
      description: 'Material Tooltip matching $message',
      skipOffstage: skipOffstage,
    );
