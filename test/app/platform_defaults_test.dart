import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  test(
    'Windows/macOS default to multiple tabs and Android to a single page',
    () {
      expect(
        workspaceNavigationModeForPlatform(TargetPlatform.windows),
        WorkspaceNavigationMode.multipleTabs,
      );
      expect(
        workspaceNavigationModeForPlatform(TargetPlatform.macOS),
        WorkspaceNavigationMode.multipleTabs,
      );
      expect(
        workspaceNavigationModeForPlatform(TargetPlatform.android),
        WorkspaceNavigationMode.singlePage,
      );
    },
  );
}
