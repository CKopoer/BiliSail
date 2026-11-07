import 'dart:convert';

import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final apple in [false, true]) {
    final key = apple ? 'Meta+B' : 'Ctrl+B';
    test('sidebar defaults and custom bindings survive JSON: apple=$apple', () {
      final defaults = ShortcutSettings.fromJson({}, useAppleDefaults: apple);
      expect(defaults.actionFor(key), ShortcutAction.toggleSidebar);
      expect(defaults.conflict, isNull);
      expect(defaults.withEnabled(false).actionFor(key), isNull);
      for (final keys in <List<String>>[
        ['Alt+B'],
        [],
      ]) {
        final settings = defaults
            .withKeys(ShortcutAction.toggleSidebar, keys)
            .withActionEnabled(ShortcutAction.toggleSidebar, false);
        final restored = ShortcutSettings.fromJson(
          jsonDecode(jsonEncode(settings.toJson())),
          useAppleDefaults: apple,
        );
        expect(restored.keysFor(ShortcutAction.toggleSidebar), keys);
        expect(restored.isEnabled(ShortcutAction.toggleSidebar), isFalse);
        expect(restored.actionFor(key), isNull);
        expect(restored.actionFor('Alt+B'), isNull);
        if (keys.isNotEmpty) {
          expect(
            restored
                .withActionEnabled(ShortcutAction.toggleSidebar, true)
                .actionFor('Alt+B'),
            ShortcutAction.toggleSidebar,
          );
        }
        expect(restored.issues, isEmpty);
      }
    });
    test('new sidebar default preserves older assignments: apple=$apple', () {
      final legacy = ShortcutSettings.fromJson({
        'bindings': {
          'playPause': [key],
        },
      }, useAppleDefaults: apple);
      expect(legacy.actionFor(key), ShortcutAction.playPause);
      expect(legacy.keysFor(ShortcutAction.toggleSidebar), isEmpty);
      expect(legacy.issues, isEmpty);
      expect(legacy.conflict, isNull);
      final conflict = ShortcutSettings.fromJson({
        'bindings': {
          'playPause': [key],
          'toggleSidebar': [key],
        },
      }, useAppleDefaults: apple);
      expect(conflict.actionFor(key), isNull);
      expect(conflict.issues, isNotEmpty);
    });
  }
  test('Apple defaults apply only to missing bindings and survive edits', () {
    for (final snapshot in [
      null,
      <String, Object?>{},
      {'bindings': <String, Object?>{}},
    ]) {
      final settings = ShortcutSettings.fromJson(
        snapshot,
        useAppleDefaults: true,
      );
      expect(settings.actionFor('Meta+W'), ShortcutAction.closeTab);
      expect(settings.actionFor('MouseBack'), ShortcutAction.closeTab);
      expect(settings.actionFor('Meta+T'), ShortcutAction.newTab);
      expect(settings.actionFor('Meta+R'), ShortcutAction.refresh);
      expect(settings.actionFor('Meta+1'), ShortcutAction.toggleRate);
      expect(
        settings.actionFor('Shift+Meta+BracketRight'),
        ShortcutAction.nextTab,
      );
      expect(
        settings.actionFor('Shift+Meta+BracketLeft'),
        ShortcutAction.previousTab,
      );
      expect(settings.actionFor('Ctrl+W'), isNull);
      expect(settings.actionFor('Meta+Tab'), isNull);
      expect(settings.conflict, isNull);
      final edited = settings
          .withKeys(ShortcutAction.playPause, ['Meta+K'])
          .withActionEnabled(ShortcutAction.fullscreen, false)
          .withPlayback(seekSeconds: 8)
          .withEnabled(false)
          .withEnabled(true);
      expect(edited.useAppleDefaults, isTrue);
      expect(edited.actionFor('Meta+W'), ShortcutAction.closeTab);
      expect(edited.actionFor('Meta+K'), ShortcutAction.playPause);
    }
    final custom = ShortcutSettings.fromJson({
      'bindings': {
        'closeTab': ['Ctrl+W'],
        'newTab': <String>[],
        'nextTab': ['Meta+K'],
        'previousTab': <String>[],
      },
      'disabled': ['nextTab'],
    }, useAppleDefaults: true);
    final restored = ShortcutSettings.fromJson(
      jsonDecode(jsonEncode(custom.toJson())),
      useAppleDefaults: true,
    );
    expect(restored.keysFor(ShortcutAction.closeTab), ['Ctrl+W']);
    expect(restored.keysFor(ShortcutAction.newTab), isEmpty);
    expect(restored.keysFor(ShortcutAction.nextTab), ['Meta+K']);
    expect(restored.keysFor(ShortcutAction.previousTab), isEmpty);
    expect(restored.isEnabled(ShortcutAction.nextTab), isFalse);
    expect(restored.issues, isEmpty);
  });
  test('new platform defaults preserve older explicit assignments', () {
    final apple = ShortcutSettings.fromJson({
      'bindings': {
        'playPause': ['Meta+W', 'Shift+Meta+BracketRight'],
      },
    }, useAppleDefaults: true);
    expect(apple.actionFor('Meta+W'), ShortcutAction.playPause);
    expect(
      apple.actionFor('Shift+Meta+BracketRight'),
      ShortcutAction.playPause,
    );
    expect(apple.keysFor(ShortcutAction.closeTab), ['MouseBack']);
    expect(apple.keysFor(ShortcutAction.nextTab), isEmpty);
    expect(apple.conflict, isNull);
    expect(apple.issues, isEmpty);
    final standard = ShortcutSettings.fromJson({
      'bindings': {
        'playPause': ['Ctrl+Tab'],
      },
    });
    expect(standard.actionFor('Ctrl+Tab'), ShortcutAction.playPause);
    expect(standard.keysFor(ShortcutAction.nextTab), isEmpty);
  });
  test('tab cycling can be rebound, disabled, cleared and reassigned', () {
    final settings = const ShortcutSettings.defaults()
        .withKeys(ShortcutAction.nextTab, ['Alt+ArrowRight'])
        .withKeys(ShortcutAction.previousTab, ['Alt+ArrowLeft'])
        .withKeys(ShortcutAction.playPause, ['Ctrl+Tab']);
    expect(settings.conflict, isNull);
    final restored = ShortcutSettings.fromJson(settings.toJson());
    expect(restored.actionFor('Alt+ArrowRight'), ShortcutAction.nextTab);
    expect(restored.actionFor('Alt+ArrowLeft'), ShortcutAction.previousTab);
    expect(restored.actionFor('Ctrl+Tab'), ShortcutAction.playPause);
    expect(
      restored
          .withActionEnabled(ShortcutAction.nextTab, false)
          .actionFor('Alt+ArrowRight'),
      isNull,
    );
    expect(restored.withEnabled(false).actionFor('Alt+ArrowLeft'), isNull);
    expect(
      restored
          .withKeys(ShortcutAction.previousTab, [])
          .actionFor('Alt+ArrowLeft'),
      isNull,
    );
    expect(
      ShortcutSettings.canonicalKey('Command+Shift+]'),
      'Shift+Meta+BracketRight',
    );
    expect(
      ShortcutSettings.canonicalKey('Cmd+Shift+['),
      'Shift+Meta+BracketLeft',
    );
    expect(ShortcutSettings.canonicalKey('⌘+Option+K'), 'Alt+Meta+K');
  });
  test(
    'all conflicting keys are removed without reintroducing earlier ones',
    () {
      final settings = ShortcutSettings.fromJson({
        'bindings': {
          'nextTab': ['Ctrl+K', 'Meta+K'],
          'previousTab': ['Ctrl+K', 'Meta+K'],
        },
      });
      expect(settings.actionFor('Ctrl+K'), isNull);
      expect(settings.actionFor('Meta+K'), isNull);
      expect(settings.conflict, isNull);
      expect(settings.issues, hasLength(2));
    },
  );
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
  test('default shortcuts and immutable caller bindings', () {
    const defaults = ShortcutSettings.defaults();
    expect(defaults.holdRate, 2);
    expect(ShortcutSettings().holdRate, 2);
    expect(ShortcutSettings.fromJson(null).holdRate, 2);
    expect(ShortcutSettings.fromJson({}).holdRate, 2);
    expect(defaults.actionFor('F11'), ShortcutAction.fullscreen);
    expect(defaults.actionFor('Ctrl+T'), ShortcutAction.newTab);
    expect(defaults.actionFor('Ctrl+W'), ShortcutAction.closeTab);
    expect(defaults.actionFor('MouseBack'), ShortcutAction.closeTab);
    final keys = ['Ctrl+K'];
    final settings = ShortcutSettings(
      overrides: {ShortcutAction.playPause: keys},
    );
    keys.add('F7');
    expect(settings.keysFor(ShortcutAction.playPause), ['Ctrl+K']);
  });
  test('new close-tab default preserves saved custom bindings', () {
    final legacy = ShortcutSettings.fromJson({
      'bindings': {
        'playPause': ['MouseBack'],
      },
    });
    expect(legacy.actionFor('MouseBack'), ShortcutAction.playPause);
    expect(legacy.keysFor(ShortcutAction.closeTab), ['Ctrl+W']);
    expect(legacy.issues, isEmpty);
    expect(legacy.conflict, isNull);
    expect(
      ShortcutSettings.fromJson(legacy.toJson()).actionFor('MouseBack'),
      ShortcutAction.playPause,
    );
    for (final keys in <List<String>>[
      ['Ctrl+W'],
      ['Ctrl+Q'],
      [],
    ]) {
      final custom = ShortcutSettings.fromJson({
        'bindings': {'closeTab': keys},
      });
      expect(custom.keysFor(ShortcutAction.closeTab), keys);
      expect(custom.actionFor('MouseBack'), isNull);
    }
    final explicitConflict = ShortcutSettings.fromJson({
      'bindings': {
        'playPause': ['MouseBack'],
        'closeTab': ['MouseBack'],
      },
    });
    expect(explicitConflict.actionFor('MouseBack'), isNull);
    expect(explicitConflict.issues, isNotEmpty);
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
      contains('已用于'),
    );
    expect(
      const ShortcutSettings.defaults().withKeys(ShortcutAction.playPause, [
        'Ctrl+Shift+Tab',
      ]).conflict,
      contains('已用于'),
    );
    expect(ShortcutSettings.fromJson(conflict.toJson()).actionFor('F'), isNull);
    final restored = ShortcutSettings.fromJson({
      'bindings': {
        'playPause': ['Unknown'],
      },
      'holdRate': double.nan,
      'seekSeconds': -3,
    });
    expect(restored.actionFor('Space'), isNull);
    expect(restored.issues, isNotEmpty);
    expect(restored.holdRate, 2);
    expect(restored.seekSeconds, 1);
    expect(ShortcutSettings.canonicalKey(' shift+ctrl+k '), 'Ctrl+Shift+K');
  });
}
