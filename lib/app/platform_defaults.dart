import 'package:flutter/foundation.dart';

import '../features/settings/domain/app_settings.dart';

/// Platform defaults apply only when no valid user preference has been saved.
WorkspaceNavigationMode workspaceNavigationModeForPlatform(
  TargetPlatform platform,
) => platform == TargetPlatform.android
    ? WorkspaceNavigationMode.singlePage
    : WorkspaceNavigationMode.multipleTabs;

WorkspaceNavigationMode get defaultWorkspaceNavigationMode =>
    workspaceNavigationModeForPlatform(defaultTargetPlatform);
