import 'package:flutter/foundation.dart';

import '../domain/responsive_layout_settings.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/domain/shortcut_settings.dart';

ShortcutSettings shortcutSettingsForPlatform(TargetPlatform platform) =>
    ShortcutSettings.defaults(
      useAppleDefaults:
          platform == TargetPlatform.macOS || platform == TargetPlatform.iOS,
      desktopShortcuts: switch (platform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      },
    );

ShortcutSettings get defaultShortcuts =>
    shortcutSettingsForPlatform(defaultTargetPlatform);

/// Platform defaults apply only when no valid user preference has been saved.
WorkspaceNavigationMode workspaceNavigationModeForPlatform(
  TargetPlatform platform,
) => platform == TargetPlatform.android
    ? WorkspaceNavigationMode.singlePage
    : WorkspaceNavigationMode.dualTabs;

WorkspaceNavigationMode get defaultWorkspaceNavigationMode =>
    workspaceNavigationModeForPlatform(defaultTargetPlatform);

/// Mobile navigation uses system back without desktop workspace chrome.
bool workspaceHeaderVisibleForPlatform(TargetPlatform platform) =>
    platform != TargetPlatform.android && platform != TargetPlatform.iOS;

bool get workspaceHeaderVisible =>
    workspaceHeaderVisibleForPlatform(defaultTargetPlatform);

bool highEnergyProgressEnabledForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.windows || platform == TargetPlatform.macOS;

bool get defaultHighEnergyProgressEnabled =>
    highEnergyProgressEnabledForPlatform(defaultTargetPlatform);

bool videoCardHoverPlaybackForPlatform(TargetPlatform platform) =>
    platform != TargetPlatform.android;

bool get defaultVideoCardHoverPlayback =>
    videoCardHoverPlaybackForPlatform(defaultTargetPlatform);

CardCoverRatio cardCoverRatioForPlatform(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS => CardCoverRatio.standard,
      _ => CardCoverRatio.widescreen,
    };

CardCoverRatio get defaultCardCoverRatio =>
    cardCoverRatioForPlatform(defaultTargetPlatform);

double danmakuAreaForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.android ? .5 : .75;

double get defaultDanmakuArea => danmakuAreaForPlatform(defaultTargetPlatform);

double danmakuFontScaleForPlatform(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android => .6,
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => .8,
      _ => 1.0,
    };

double get defaultDanmakuFontScale =>
    danmakuFontScaleForPlatform(defaultTargetPlatform);

PlayerControlsMode playerControlsModeForPlatform(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => PlayerControlsMode.dynamic,
      _ => PlayerControlsMode.click,
    };

PlayerControlsMode get defaultPlayerControlsMode =>
    playerControlsModeForPlatform(defaultTargetPlatform);
