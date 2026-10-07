import '../../features/settings/domain/shortcut_settings.dart';
import '../../core/presentation/keyboard_shortcuts.dart';

String shortcutHint(
  ShortcutSettings settings,
  ShortcutAction action,
  String label,
) {
  final keys = settings.keysFor(action);
  if (!settings.enabled || !settings.isEnabled(action) || keys.isEmpty) {
    return label;
  }
  final key = shortcutLabel(keys.first)
      .replaceAll('Space', '空格')
      .replaceAll('Escape', 'Esc');
  return '$label（$key）';
}
