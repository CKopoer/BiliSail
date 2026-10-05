import '../../../domain/playback_rates.dart';

/// Key names are stable storage values; Flutter key IDs never enter domain data.
enum ShortcutAction {
  playPause('播放 / 暂停', ['Space']),
  fullscreen('切换全屏', ['F', 'F11', 'Enter']),
  exitFullscreen('退出全屏', ['Escape']),
  fullWindow('收起 / 展开视频信息', ['W', 'F12']),
  seekBack('后退', ['ArrowLeft']),
  seekForward('前进（长按临时倍速）', ['ArrowRight']),
  seekLarge('前进 90 秒', ['O', 'P']),
  volumeUp('提高音量', ['ArrowUp']),
  volumeDown('降低音量', ['ArrowDown']),
  mute('静音 / 恢复音量', []),
  danmaku('显示 / 隐藏弹幕', ['D', 'F9']),
  subtitles('开启 / 关闭字幕', ['F6']),
  slower('降低播放速度', ['F1', 'Semicolon']),
  faster('提高播放速度', ['F2', 'Quote']),
  toggleRate('切换 1 / 2 倍速', ['Ctrl+1']),
  previousPart('上一分 P', ['Z', 'N', 'Comma']),
  nextPart('下一分 P', ['X', 'M', 'Period']),
  newTab('新建浏览标签', ['Ctrl+T']),
  closeTab('关闭当前标签页', ['Ctrl+W']),
  refresh('刷新当前页面', ['Ctrl+R', 'F5']);

  const ShortcutAction(this.label, this.defaultKeys);
  final String label;
  final List<String> defaultKeys;
}

final class ShortcutSettings {
  const ShortcutSettings.defaults()
    : seekSeconds = 3,
      holdDelayMs = 400,
      holdRate = 3,
      enabled = true,
      _disabled = const {},
      _overrides = const {};
  ShortcutSettings({
    this.seekSeconds = 3,
    this.holdDelayMs = 400,
    this.holdRate = 3,
    this.enabled = true,
    Set<ShortcutAction> disabled = const {},
    Map<ShortcutAction, List<String>> overrides = const {},
  }) : _disabled = Set.unmodifiable(disabled),
       _overrides = Map.unmodifiable(
         overrides.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       );
  final int seekSeconds;
  final int holdDelayMs;
  final double holdRate;
  final bool enabled;
  final Set<ShortcutAction> _disabled;
  bool isEnabled(ShortcutAction action) => !_disabled.contains(action);
  final Map<ShortcutAction, List<String>> _overrides;
  ShortcutAction? actionFor(String? key) => enabled
      ? ShortcutAction.values
            .where(
              (action) => isEnabled(action) && keysFor(action).contains(key),
            )
            .firstOrNull
      : null;
  List<String> keysFor(ShortcutAction action) =>
      _overrides[action] ?? action.defaultKeys;
  Map<String, Object?> toJson() => {
    'seekSeconds': seekSeconds,
    'holdDelayMs': holdDelayMs,
    'holdRate': holdRate,
    'enabled': enabled,
    'disabled': _disabled.map((action) => action.name).toList(),
    'bindings': {
      for (final entry in _overrides.entries) entry.key.name: entry.value,
    },
  };
  static ShortcutSettings fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const ShortcutSettings.defaults();
    }
    final bindings = value['bindings'];
    final overrides = <ShortcutAction, List<String>>{};
    if (bindings is Map<String, Object?>) {
      for (final action in ShortcutAction.values) {
        final keys = bindings[action.name];
        if (keys is List &&
            keys.every((key) => key is String && canonicalKey(key) != null)) {
          overrides[action] = keys
              .whereType<String>()
              .map(canonicalKey)
              .whereType<String>()
              .toSet()
              .toList();
        }
      }
    }
    final result = ShortcutSettings(
      seekSeconds: value['seekSeconds'] is int
          ? (value['seekSeconds'] as int).clamp(1, 90)
          : 3,
      holdDelayMs: value['holdDelayMs'] is int
          ? (value['holdDelayMs'] as int).clamp(200, 1500)
          : 400,
      holdRate: value['holdRate'] is num && (value['holdRate'] as num).isFinite
          ? PlaybackRates.nearest(
              (value['holdRate'] as num).toDouble().clamp(1.25, 3),
            )
          : 3,
      enabled: value['enabled'] != false,
      overrides: overrides,
      disabled: ShortcutAction.values
          .where(
            (action) =>
                value['disabled'] is List &&
                (value['disabled'] as List).contains(action.name),
          )
          .toSet(),
    );
    return result.conflict == null ? result : const ShortcutSettings.defaults();
  }

  ShortcutSettings withEnabled(bool value) => ShortcutSettings(
    seekSeconds: seekSeconds,
    holdDelayMs: holdDelayMs,
    holdRate: holdRate,
    enabled: value,
    overrides: _overrides,
    disabled: _disabled,
  );
  ShortcutSettings withKeys(ShortcutAction action, List<String> keys) =>
      ShortcutSettings(
        seekSeconds: seekSeconds,
        holdDelayMs: holdDelayMs,
        holdRate: holdRate,
        enabled: enabled,
        disabled: _disabled,
        overrides: {..._overrides, action: keys},
      );
  ShortcutSettings withActionEnabled(ShortcutAction action, bool value) =>
      ShortcutSettings(
        seekSeconds: seekSeconds,
        holdDelayMs: holdDelayMs,
        holdRate: holdRate,
        enabled: enabled,
        overrides: _overrides,
        disabled: value
            ? ({..._disabled}..remove(action))
            : {..._disabled, action},
      );
  ShortcutSettings withPlayback({
    int? seekSeconds,
    int? holdDelayMs,
    double? holdRate,
  }) => ShortcutSettings(
    seekSeconds: (seekSeconds ?? this.seekSeconds).clamp(1, 90),
    holdDelayMs: (holdDelayMs ?? this.holdDelayMs).clamp(200, 1500),
    holdRate: PlaybackRates.nearest((holdRate ?? this.holdRate).clamp(1.25, 3)),
    enabled: enabled,
    disabled: _disabled,
    overrides: _overrides,
  );
  String? get conflict {
    final used = <String, ShortcutAction>{};
    for (final action in ShortcutAction.values) {
      for (final key in keysFor(action)) {
        if (key == 'Ctrl+Tab' || key == 'Ctrl+Shift+Tab') {
          return '$key 保留用于循环切换标签';
        }
        final previous = used[key];
        if (previous != null && previous != action) {
          return '$key 已用于${previous.label}';
        }
        used[key] = action;
      }
    }
    return null;
  }

  static String? canonicalKey(String input) {
    final parts = input.trim().split('+');
    final key = parts.last.toUpperCase();
    final modifiers = parts
        .take(parts.length - 1)
        .map((part) => part.toUpperCase())
        .toSet();
    if (modifiers.any(
      (part) => !['CTRL', 'ALT', 'SHIFT', 'META'].contains(part),
    )) {
      return null;
    }
    final special = {
      for (final key in [
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
      ])
        key.toUpperCase(): key,
    };
    final name =
        special[key] ??
        (RegExp(r'^[A-Z0-9]$|^F([1-9]|1[0-2])$').hasMatch(key) ? key : null);
    if (name == null) {
      return null;
    }
    return [
      ...[
        'Ctrl',
        'Alt',
        'Shift',
        'Meta',
      ].where((part) => modifiers.contains(part.toUpperCase())),
      name,
    ].join('+');
  }
}
