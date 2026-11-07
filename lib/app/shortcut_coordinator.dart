import '../core/input/input_stroke.dart';
import '../core/input/shortcut_dispatcher.dart';
import '../core/presentation/app_input_host.dart';
import '../domain/shortcut_command.dart';
import '../features/settings/domain/shortcut_settings.dart';

/// Composition only: the dispatcher knows neither settings nor application IDs.
final class ShortcutCoordinator extends ShortcutDispatcher<Object> {
  ShortcutCoordinator()
    : super(
        scopeFor: (command) => switch (command) {
          ShortcutAction.newTab ||
          ShortcutAction.closeTab ||
          ShortcutAction.nextTab ||
          ShortcutAction.previousTab ||
          ShortcutAction.toggleSidebar => CommandScope.workspace,
          ShortcutAction.refresh ||
          ShortcutAction.previousPart ||
          ShortcutAction.nextPart ||
          ShortcutAction.fullWindow => CommandScope.page,
          _ => CommandScope.playback,
        },
        repeats: (command) => const {
          ShortcutAction.seekBack,
          ShortcutAction.volumeUp,
          ShortcutAction.volumeDown,
          ShortcutAction.nextTab,
          ShortcutAction.previousTab,
          ReservedShortcut.imagePrevious,
          ReservedShortcut.imageNext,
          ReservedShortcut.imageZoomIn,
          ReservedShortcut.imageZoomOut,
        }.contains(command),
        editorException: (command, chord) =>
            ((command == ShortcutAction.nextTab ||
                    command == ShortcutAction.previousTab) &&
                (chord.isMouse ||
                    chord.modifiers &
                            (ShortcutChord.control |
                                ShortcutChord.alt |
                                ShortcutChord.meta) !=
                        0)) ||
            (command == ShortcutAction.closeTab &&
                (chord.isMouse ||
                    chord.modifiers &
                            (ShortcutChord.control | ShortcutChord.meta) !=
                        0)),
      ) {
    localBindings.addAll({
      const ShortcutChord('Escape'): ReservedShortcut.imageClose,
      const ShortcutChord('ArrowLeft'): ReservedShortcut.imagePrevious,
      const ShortcutChord('PageUp'): ReservedShortcut.imagePrevious,
      const ShortcutChord('ArrowRight'): ReservedShortcut.imageNext,
      const ShortcutChord('PageDown'): ReservedShortcut.imageNext,
      for (final key in ['ArrowUp', 'Equal', 'NumpadAdd'])
        ShortcutChord(key): ReservedShortcut.imageZoomIn,
      for (final key in ['ArrowDown', 'Minus', 'NumpadSubtract'])
        ShortcutChord(key): ReservedShortcut.imageZoomOut,
    });
    configure(const ShortcutSettings.defaults());
  }
  final routes = InputRouteObserver();
  String? _configuration;
  void configure(ShortcutSettings settings) {
    final signature = '${settings.useAppleDefaults}:${settings.toJson()}';
    if (_configuration == signature) return;
    _configuration = signature;
    final bindings = <ShortcutChord, Object>{};
    final disabled = <ShortcutChord>{};
    for (final action in ShortcutAction.values) {
      for (final name in settings.keysFor(action)) {
        final chord = ShortcutChord.parse(name);
        if (chord == null) continue;
        if (settings.enabled && settings.isEnabled(action)) {
          bindings[chord] = action;
        } else {
          disabled.add(chord);
        }
      }
    }
    replaceBindings(bindings, disabled: disabled);
  }
}
