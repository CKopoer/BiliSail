import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

class FakePassportPlatform extends WebViewPlatform {
  final controllers = <FakePassportController>[];
  final cookies = FakePassportCookies();
  final data = FakePassportData();
  Set<WebViewSessionMode> modes = WebViewSessionMode.values.toSet();
  Completer<void>? preparing;
  FakePassportController get controller => controllers.last;

  @override
  Future<WebViewSessionCapabilities> getSessionCapabilities() async =>
      WebViewSessionCapabilities(
        canClose: true,
        scopedCookies: true,
        supportedModes: modes,
      );

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakePassportController(params, this);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakePassportNavigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class FakePassportController extends PlatformWebViewController {
  FakePassportController(super.params, this.owner) : super.implementation();
  final FakePassportPlatform owner;
  final requests = <LoadRequestParams>[];
  final channels = <String, JavaScriptChannelParams>{};
  String? html;
  late FakePassportNavigation navigation;
  int closes = 0;

  @override
  Future<void> prepareSession() async => owner.preparing?.future;
  @override
  Future<void> closeWebViewSession() async => closes++;
  @override
  PlatformWebViewCookieManager createSessionCookieManager() => owner.cookies;
  @override
  PlatformWebViewDataManager createSessionDataManager() => owner.data;
  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}
  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async =>
      channels[params.name] = params;
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async =>
      this.html = html;
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async => navigation = handler as FakePassportNavigation;
  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      requests.add(params);
}

class FakePassportNavigation extends PlatformNavigationDelegate {
  FakePassportNavigation(super.params) : super.implementation();
  NavigationRequestCallback? request;
  PageEventCallback? started;
  PageEventCallback? finished;
  UrlChangeCallback? changed;
  WebResourceErrorCallback? error;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async => request = callback;
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async =>
      started = callback;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async =>
      finished = callback;
  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async =>
      changed = callback;
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      error = callback;
}

class FakePassportCookies extends PlatformWebViewCookieManager {
  FakePassportCookies()
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());
  List<WebViewCookie> value = [];
  Completer<List<WebViewCookie>>? pending;
  Set<WebViewCookieAttribute> attributes = WebViewCookieAttribute.values
      .toSet();
  int reads = 0;
  @override
  Future<WebViewCookieCapabilities> getCapabilities() async =>
      WebViewCookieCapabilities(readableAttributes: attributes);
  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    expectApiRoot(url);
    reads++;
    return pending?.future ?? value;
  }

  void expectApiRoot(Uri url) {
    if (url.toString() != 'https://api.bilibili.com/') {
      throw StateError('Incorrect cookie scope');
    }
  }
}

class FakePassportData extends PlatformWebViewDataManager {
  FakePassportData()
    : super.implementation(const PlatformWebViewDataManagerCreationParams());
  int clears = 0;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    clears++;
    await pending?.future;
    return WebViewDataClearingResult(
      clearedDataTypes: fail ? {} : WebViewDataType.values.toSet(),
      unsupportedDataTypes: fail ? WebViewDataType.values.toSet() : {},
    );
  }
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}
