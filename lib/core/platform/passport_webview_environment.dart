import 'package:flutter/foundation.dart';
import 'package:webview_all/webview_all.dart';

/// Owns the login view and its cookies until the view has been removed.
final class PassportWebViewEnvironment {
  PassportWebViewEnvironment._(this.session, this.platform);

  final WebViewSession session;
  final TargetPlatform platform;
  Future<void>? _disposal;
  static bool _androidInUse = false;

  static Future<PassportWebViewEnvironment> create({
    TargetPlatform? platform,
  }) async {
    final target = platform ?? defaultTargetPlatform;
    final android = target == TargetPlatform.android;
    // Android's WebView has a shared store even in incognito mode. Reserve it
    // through cleanup so a closing attempt cannot clear a new login's cookies.
    if (android && _androidInUse) {
      throw StateError('A WebView login is already closing or active');
    }
    if (android) _androidInUse = true;
    WebViewSession? session;
    try {
      session = await WebViewSession.create(
        mode: android
            ? WebViewSessionMode.incognito
            : WebViewSessionMode.isolatedIncognito,
        onPermissionRequest: (request) => request.deny(),
      );
      if (session == null || !session.capabilities.scopedCookies) {
        throw UnsupportedError('A private login store is unavailable');
      }
      final environment = PassportWebViewEnvironment._(session, target);
      if (android) await environment._clearAndroidStore();
      return environment;
    } catch (_) {
      try {
        await session?.close();
      } finally {
        if (android) _androidInUse = false;
      }
      rethrow;
    }
  }

  Future<void> _clearAndroidStore() async {
    final result = await session.dataManager.clearAllWebsiteData();
    const required = {
      WebViewDataType.cookies,
      WebViewDataType.localStorage,
      WebViewDataType.indexedDb,
      WebViewDataType.cache,
    };
    if (!result.clearedDataTypes.containsAll(required) ||
        result.failures.isNotEmpty) {
      throw StateError('Unable to clear the login WebView store');
    }
  }

  /// Remove the native widget and finish pending cookie reads before calling.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    try {
      if (platform == TargetPlatform.android) await _clearAndroidStore();
    } finally {
      try {
        await session.close();
      } finally {
        if (platform == TargetPlatform.android) _androidInUse = false;
      }
    }
  }
}
