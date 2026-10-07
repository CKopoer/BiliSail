import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;

/// Owns one Windows login's profile, independent of other app instances.
final class PassportWebViewEnvironment {
  PassportWebViewEnvironment._(this.environment, this.userDataDirectory);

  final WebViewEnvironment environment;
  final Directory userDataDirectory;
  Future<void>? _disposal;

  static Future<PassportWebViewEnvironment> create(
    Directory applicationSupportDirectory, {
    Future<WebViewEnvironment> Function(WebViewEnvironmentSettings)?
    createEnvironment,
  }) async {
    // An elevated launcher can supply a system/admin-only TEMP directory.
    // WebView2's browser runs without elevation and needs a user-writable path.
    final root = Directory(
      path.join(applicationSupportDirectory.path, 'passport-webview'),
    );
    await root.create(recursive: true);
    final profile = await root.createTemp('login-');
    try {
      final settings = WebViewEnvironmentSettings(userDataFolder: profile.path);
      final environment = await (createEnvironment == null
          ? WebViewEnvironment.create(settings: settings)
          : createEnvironment(settings));
      return PassportWebViewEnvironment._(environment, profile);
    } catch (_) {
      await _deleteProfile(profile);
      rethrow;
    }
  }

  /// Call after the native WebView widget has been removed.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    try {
      await environment.dispose();
    } finally {
      await _deleteProfile(userDataDirectory);
    }
  }

  static Future<void> _deleteProfile(Directory profile) async {
    // Browser shutdown can briefly retain file locks after the view closes.
    // Delete only the directory allocated by this attempt, never shared data.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (await profile.exists()) await profile.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }
  }
}
