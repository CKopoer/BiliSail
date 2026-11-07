import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS and iOS use Command defaults while other platforms retain Ctrl',
    () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final apple =
            platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
        final settings = shortcutSettingsForPlatform(platform);
        expect(defaultShortcuts.useAppleDefaults, apple);
        expect(settings.keysFor(ShortcutAction.toggleSidebar), [
          apple ? 'Meta+B' : 'Ctrl+B',
        ]);
        expect(settings.keysFor(ShortcutAction.closeTab), [
          apple ? 'Meta+W' : 'Ctrl+W',
          'MouseBack',
        ]);
        expect(settings.keysFor(ShortcutAction.newTab), [
          apple ? 'Meta+T' : 'Ctrl+T',
        ]);
        expect(settings.keysFor(ShortcutAction.refresh), [
          apple ? 'Meta+R' : 'Ctrl+R',
          'F5',
        ]);
        expect(settings.keysFor(ShortcutAction.nextTab), [
          apple ? 'Shift+Meta+BracketRight' : 'Ctrl+Tab',
        ]);
        expect(settings.keysFor(ShortcutAction.previousTab), [
          apple ? 'Shift+Meta+BracketLeft' : 'Ctrl+Shift+Tab',
        ]);
      }
    },
  );
  test('desktop and Android use their own player defaults', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(defaultDanmakuArea, platform == TargetPlatform.android ? .5 : .75);
      expect(defaultVideoCardHoverPlayback, platform != TargetPlatform.android);
      expect(
        videoCardHoverPlaybackForPlatform(platform),
        platform != TargetPlatform.android,
      );
      expect(defaultDanmakuFontScale, switch (platform) {
        TargetPlatform.android => .6,
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => .8,
        _ => 1.0,
      });
      expect(
        defaultPlayerControlsMode,
        [
              TargetPlatform.windows,
              TargetPlatform.macOS,
              TargetPlatform.linux,
            ].contains(platform)
            ? PlayerControlsMode.dynamic
            : PlayerControlsMode.click,
      );
    }
  });
  test('high energy defaults on only for Windows and macOS', () {
    for (final platform in TargetPlatform.values) {
      expect(
        highEnergyProgressEnabledForPlatform(platform),
        platform == TargetPlatform.windows || platform == TargetPlatform.macOS,
      );
    }
  });
  test(
    'workspace header is hidden on Android/iOS and visible on Windows/macOS',
    () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(workspaceHeaderVisibleForPlatform(platform), isFalse);
      }
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        expect(workspaceHeaderVisibleForPlatform(platform), isTrue);
      }
    },
  );
  test('Android defaults to single page and other platforms to dual tabs', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final expected = platform == TargetPlatform.android
          ? WorkspaceNavigationMode.singlePage
          : WorkspaceNavigationMode.dualTabs;
      expect(workspaceNavigationModeForPlatform(platform), expected);
      expect(defaultWorkspaceNavigationMode, expected);
    }
  });
}
