enum InputDevice { keyboard, mouse }

enum InputPhase { down, repeat, up, cancel }

/// Stable storage names, independent of Flutter key IDs and typed characters.
final class ShortcutChord {
  const ShortcutChord(this.key, {this.modifiers = 0});
  static const control = 1, alt = 2, shift = 4, meta = 8;
  final String key;
  final int modifiers;
  bool get isMouse => key == 'MouseBack' || key == 'MouseForward';
  static final _names = {
    for (final name in [
      'Space',
      'Enter',
      'Escape',
      'ArrowLeft',
      'ArrowRight',
      'ArrowUp',
      'ArrowDown',
      'Semicolon',
      'Quote',
      'Comma',
      'Period',
      'Tab',
      'MouseBack',
      'MouseForward',
      'PageUp',
      'PageDown',
      'Equal',
      'Minus',
      'NumpadAdd',
      'NumpadSubtract',
    ])
      name.toUpperCase(): name,
    'QUOTESINGLE': 'Quote',
    ';': 'Semicolon',
    "'": 'Quote',
  };
  static String? keyName(String value) =>
      _names[value.toUpperCase()] ??
      (RegExp(r'^[A-Z0-9]$|^F([1-9]|1[0-2])$').hasMatch(value.toUpperCase())
          ? value.toUpperCase()
          : null);
  static ShortcutChord? parse(String value) {
    final parts = value.trim().split('+').map((part) => part.trim()).toList();
    final key = keyName(parts.last);
    if (key == null) return null;
    var modifiers = 0;
    for (final part in parts.take(parts.length - 1)) {
      final mask = switch (part.toUpperCase()) {
        'CTRL' => control,
        'ALT' => alt,
        'SHIFT' => shift,
        'META' => meta,
        _ => null,
      };
      if (mask == null) return null;
      modifiers |= mask;
    }
    return ShortcutChord(key, modifiers: modifiers);
  }

  @override
  String toString() => [
    if (modifiers & control != 0) 'Ctrl',
    if (modifiers & alt != 0) 'Alt',
    if (modifiers & shift != 0) 'Shift',
    if (modifiers & meta != 0) 'Meta',
    key,
  ].join('+');
  @override
  bool operator ==(Object other) =>
      other is ShortcutChord &&
      key == other.key &&
      modifiers == other.modifiers;
  @override
  int get hashCode => Object.hash(key, modifiers);
}

final class InputStroke {
  const InputStroke({
    required this.identity,
    required this.device,
    required this.phase,
    required this.sequence,
    this.chord,
    this.synthesized = false,
    this.physicalFallback = false,
    this.elapsedMicros,
    this.logicalKeyId,
    this.physicalKeyId,
    this.viewId,
    this.buttons,
  });
  final String identity;
  final InputDevice device;
  final InputPhase phase;
  final int sequence;
  final ShortcutChord? chord;
  final bool synthesized, physicalFallback;
  final int? elapsedMicros, logicalKeyId, physicalKeyId, viewId, buttons;
}
