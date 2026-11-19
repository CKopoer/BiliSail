String shortcutLabel(String key, {bool useAppleLabels = false}) => key
    .split('+')
    .map(
      (part) => switch (part) {
        'Meta' when useAppleLabels => '⌘ Command',
        'Alt' when useAppleLabels => '⌥ Option',
        'BracketLeft' => '[',
        'BracketRight' => ']',
        'Comma' => ',',
        'Period' => '.',
        'MouseBack' => '鼠标侧键（后退）',
        'MouseForward' => '鼠标侧键（前进）',
        _ => part,
      },
    )
    .join('+');
