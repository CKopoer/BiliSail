import 'dart:convert';

import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mouse side keys support modifiers, conflicts and round-trip storage',
    () {
      expect(ShortcutSettings.canonicalKey('ctrl+mouseback'), 'Ctrl+MouseBack');
      expect(ShortcutSettings.canonicalKey('MouseForward'), 'MouseForward');
      expect(ShortcutSettings.canonicalKey('MouseLeft'), isNull);
      final settings = const ShortcutSettings.defaults().withKeys(
        ShortcutAction.closeTab,
        ['Ctrl+W', 'MouseBack', 'Ctrl+MouseForward'],
      );
      final restored = ShortcutSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())),
      );
      expect(restored.actionFor('MouseBack'), ShortcutAction.closeTab);
      expect(restored.actionFor('Ctrl+MouseForward'), ShortcutAction.closeTab);
      expect(restored.withEnabled(false).actionFor('MouseBack'), isNull);
      expect(
        restored
            .withActionEnabled(ShortcutAction.closeTab, false)
            .actionFor('MouseBack'),
        isNull,
      );
      expect(
        restored.withKeys(ShortcutAction.playPause, ['MouseBack']).conflict,
        contains('已用于'),
      );
    },
  );
  test('legacy temporary speeds normalize to the same supported choices', () {
    expect(ShortcutSettings.fromJson({'holdRate': 2.75}).holdRate, 3);
    expect(ShortcutSettings.fromJson({'holdRate': 1.75}).holdRate, 1.5);
    expect(
      const ShortcutSettings.defaults().withPlayback(holdRate: 2.5).holdRate,
      2,
    );
  });
  test('defaults mirror UWP and immutable caller bindings', () {
    const defaults = ShortcutSettings.defaults();
    expect(defaults.actionFor('F11'), ShortcutAction.fullscreen);
    expect(defaults.actionFor('Ctrl+T'), ShortcutAction.newTab);
    final keys = ['Ctrl+K'];
    final settings = ShortcutSettings(
      overrides: {ShortcutAction.playPause: keys},
    );
    keys.add('F7');
    expect(settings.keysFor(ShortcutAction.playPause), ['Ctrl+K']);
  });
  test('custom bindings, action switches and playback values survive JSON', () {
    final settings = const ShortcutSettings.defaults()
        .withKeys(ShortcutAction.playPause, ['Ctrl+K'])
        .withActionEnabled(ShortcutAction.fullscreen, false)
        .withPlayback(seekSeconds: 8, holdDelayMs: 700, holdRate: 2)
        .withEnabled(false)
        .withEnabled(true);
    final decoded = ShortcutSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())),
    );
    expect(decoded.actionFor('Ctrl+K'), ShortcutAction.playPause);
    expect(decoded.actionFor('F'), isNull);
    expect(decoded.seekSeconds, 8);
    expect(decoded.holdDelayMs, 700);
    expect(decoded.holdRate, 2);
    expect(decoded.keysFor(ShortcutAction.fullscreen), ['F', 'F11', 'Enter']);
  });
  test('conflict and corrupt settings cannot steal existing actions', () {
    final conflict = const ShortcutSettings.defaults().withKeys(
      ShortcutAction.playPause,
      ['F'],
    );
    expect(conflict.conflict, contains('F'));
    expect(
      const ShortcutSettings.defaults().withKeys(ShortcutAction.playPause, [
        'Ctrl+Tab',
      ]).conflict,
      contains('保留'),
    );
    expect(
      const ShortcutSettings.defaults().withKeys(ShortcutAction.playPause, [
        'Ctrl+Shift+Tab',
      ]).conflict,
      contains('保留'),
    );
    expect(
      ShortcutSettings.fromJson(conflict.toJson()).actionFor('F'),
      ShortcutAction.fullscreen,
    );
    final restored = ShortcutSettings.fromJson({
      'bindings': {
        'playPause': ['Unknown'],
      },
      'holdRate': double.nan,
      'seekSeconds': -3,
    });
    expect(restored.actionFor('Space'), ShortcutAction.playPause);
    expect(restored.holdRate, 3);
    expect(restored.seekSeconds, 1);
    expect(ShortcutSettings.canonicalKey(' shift+ctrl+k '), 'Ctrl+Shift+K');
  });
}
