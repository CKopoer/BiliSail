import '../../../core/input/input_stroke.dart';
import '../../../domain/shortcut_command.dart';
export '../../../domain/shortcut_command.dart' show ShortcutAction;
import '../../../domain/playback_rates.dart';

final class ShortcutSettings {
  const ShortcutSettings.defaults()
    : seekSeconds = 3,
      holdDelayMs = 400,
      holdRate = 3,
      enabled = true,
      _disabled = const {},
      _overrides = const {},
      issues = const [],
      storedJson = null;
  ShortcutSettings({
    this.seekSeconds = 3,
    this.holdDelayMs = 400,
    this.holdRate = 3,
    this.enabled = true,
    List<String> issues = const [],
    this.storedJson,
    Set<ShortcutAction> disabled = const {},
    Map<ShortcutAction, List<String>> overrides = const {},
  }) : issues = List.unmodifiable(issues),
       _disabled = Set.unmodifiable(disabled),
       _overrides = Map.unmodifiable(
         overrides.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       );
  final List<String> issues;
  final Map<String, Object?>? storedJson;
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
  Map<String, Object?> toJson() =>
      storedJson ??
      {
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
    final issues = <String>[];
    if (bindings is Map<String, Object?>) {
      for (final action in ShortcutAction.values) {
        final keys = bindings[action.name];
        if (!bindings.containsKey(action.name)) continue;
        final valid = keys is List
            ? keys
                  .whereType<String>()
                  .map(canonicalKey)
                  .whereType<String>()
                  .toSet()
                  .toList()
            : <String>[];
        overrides[action] = valid;
        if (keys is! List || valid.length != keys.length) {
          issues.add('${action.label}：无效键位已停用');
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
    final used = <String, Set<ShortcutAction>>{};
    for (final action in ShortcutAction.values) {
      for (final key in result.keysFor(action)) {
        (used[key] ??= {}).add(action);
      }
    }
    for (final entry in used.entries) {
      if (entry.value.length > 1 ||
          entry.key == 'Ctrl+Tab' ||
          entry.key == 'Ctrl+Shift+Tab') {
        issues.add('${entry.key}：冲突键位已停用，请重新设置');
        for (final action in entry.value) {
          overrides[action] = result
              .keysFor(action)
              .where((key) => key != entry.key)
              .toList();
        }
      }
    }
    if (issues.isEmpty) return result;
    return ShortcutSettings(
      seekSeconds: result.seekSeconds,
      holdDelayMs: result.holdDelayMs,
      holdRate: result.holdRate,
      enabled: result.enabled,
      disabled: result._disabled,
      overrides: overrides,
      issues: List.unmodifiable(issues),
      storedJson: Map.unmodifiable(value),
    );
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
      for (final raw in keysFor(action)) {
        final key = canonicalKey(raw);
        if (key == null) return '$raw 键名无效';
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

  static String? canonicalKey(String input) =>
      ShortcutChord.parse(input)?.toString();
}
