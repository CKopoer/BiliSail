import 'dart:async';
import 'dart:io';

import 'package:bilisail/core/platform/passport_web_login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageError = '登录页面加载失败，请检查网络后重试';
final _loginUrl = WebUri('https://passport.bilibili.com/login');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _FakePlatform();
  final original = InAppWebViewPlatform.instance;
  late Directory support;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    InAppWebViewPlatform.instance = platform;
    support = await Directory.systemTemp.createTemp(
      'passport-navigation-test-',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => support.path,
    );
  });
  tearDownAll(() async {
    if (original != null) InAppWebViewPlatform.instance = original;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
    await support.delete(recursive: true);
  });
  setUp(() => platform.cookies.reset());

  testWidgets('cancelled navigation keeps waiting for the login session', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final controller = _controller(view);
    _error(view, controller, WebResourceErrorType.CANCELLED);
    await tester.pump();
    expect(find.text(_pageError), findsNothing);
    expect(find.byType(InAppWebView), findsOneWidget);
    platform.cookies.value = [_sessionCookie()];
    view.platform.params.onLoadStart?.call(controller, _loginUrl);
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('session already set wins over a failed success redirect', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    platform.cookies.value = [_sessionCookie()];
    _error(
      view,
      _controller(view),
      WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
    );
    await tester.pumpAndSettle();
    expect(find.text(_pageError), findsNothing);
    expect((await result.value)?.single.value, 'fixture');
  });

  testWidgets('success redirect captures cookies before its document loads', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    platform.cookies.value = [_sessionCookie()];
    final policy = await view.platform.params.shouldOverrideUrlLoading?.call(
      _controller(view),
      NavigationAction(
        request: URLRequest(url: WebUri('https://www.bilibili.com/')),
        isForMainFrame: true,
      ),
    );
    expect(policy, NavigationActionPolicy.ALLOW);
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('load error awaits an existing native cookie read', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final controller = _controller(view);
    final pending = Completer<List<Cookie>>();
    platform.cookies.pending = pending;
    view.platform.params.onLoadStop?.call(controller, _loginUrl);
    _error(view, controller, WebResourceErrorType.CANNOT_CONNECT_TO_HOST);
    await tester.pump();
    expect(platform.cookies.reads, 1);
    expect(find.text(_pageError), findsNothing);
    pending.complete([_sessionCookie()]);
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('real failure retains native view and polls for late cookies', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final native = tester.element(find.byType(_FakeNativeView));
    _error(
      view,
      _controller(view),
      WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
    );
    await tester.pumpAndSettle();
    expect(find.text(_pageError), findsOneWidget);
    expect(tester.element(find.byType(_FakeNativeView)), same(native));
    expect(tester.widget<InAppWebView>(find.byType(InAppWebView)), same(view));
    platform.cookies.value = [_sessionCookie()];
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('late failure cannot cover a newer successful navigation', (
    tester,
  ) async {
    await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final controller = _controller(view);
    final pending = Completer<List<Cookie>>();
    platform.cookies.pending = pending;
    _error(view, controller, WebResourceErrorType.CANNOT_CONNECT_TO_HOST);
    view.platform.params.onLoadStart?.call(controller, _loginUrl);
    view.platform.params.onLoadStop?.call(controller, _loginUrl);
    pending.complete([]);
    await tester.pump();
    expect(find.text(_pageError), findsNothing);
    await _close(tester);
  });

  testWidgets('subframe errors do not terminate login', (tester) async {
    await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    _error(
      view,
      _controller(view),
      WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
      mainFrame: false,
    );
    await tester.pump();
    expect(platform.cookies.reads, 0);
    expect(find.text(_pageError), findsNothing);
    await _close(tester);
  });

  testWidgets('retry opens the original page with GET and preserves the view', (
    tester,
  ) async {
    await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final native = tester.element(find.byType(_FakeNativeView));
    final controller = _controller(view);
    _error(view, controller, WebResourceErrorType.CANNOT_CONNECT_TO_HOST);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新打开登录页'));
    await tester.pump();
    expect(find.text(_pageError), findsNothing);
    expect(platform.controller.requests.single.url, _loginUrl);
    expect(platform.controller.requests.single.method, 'GET');
    expect(tester.element(find.byType(_FakeNativeView)), same(native));
    expect(tester.widget<InAppWebView>(find.byType(InAppWebView)), same(view));
    await _close(tester);
  });

  testWidgets('closing while cookies are pending discards late success', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final pending = Completer<List<Cookie>>();
    platform.cookies.pending = pending;
    _error(
      view,
      _controller(view),
      WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
    );
    await tester.tap(find.byTooltip('关闭网页登录'));
    pending.complete([_sessionCookie()]);
    await tester.pumpAndSettle();
    expect(await result.value, isNull);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('dialog timeout rejects late cookies after resuming', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    // No reads are started in the background; the overall dialog still expires.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 10));
    await tester.pump();
    platform.cookies.value = [_sessionCookie()];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    view.platform.params.onLoadStop?.call(_controller(view), _loginUrl);
    await tester.pumpAndSettle();
    expect(find.text('登录页面已超时，请关闭后重试'), findsOneWidget);
    expect(platform.cookies.reads, 0);
    await _close(tester);
    expect(await result.value, isNull);
  });

  testWidgets('native cookie reads have a deadline and ignore late results', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final pending = Completer<List<Cookie>>();
    platform.cookies.pending = pending;
    view.platform.params.onLoadStop?.call(_controller(view), _loginUrl);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('无法读取网页登录会话，请重试或使用扫码登录'), findsOneWidget);
    pending.complete([_sessionCookie()]);
    await tester.pump();
    await _close(tester);
    expect(await result.value, isNull);
  });
}

Future<({Future<List<BrowserLoginCookie>?> value})> _open(
  WidgetTester tester,
) async {
  final platform = InAppWebViewPlatform.instance as _FakePlatform;
  platform.controller = _FakeController();
  final result = Completer<List<BrowserLoginCookie>?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => result.complete(showPassportWebLogin(context)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  // Windows profile allocation uses real asynchronous filesystem operations.
  for (var attempt = 0; attempt < 50; attempt++) {
    if (find.byType(InAppWebView).evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(find.byType(InAppWebView), findsOneWidget);
  await tester.pumpAndSettle();
  return (value: result.future);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip('关闭网页登录'));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

InAppWebViewController _controller(InAppWebView view) =>
    InAppWebViewController.fromPlatform(
      platform: (view.platform as _FakeView).controller,
    );

void _error(
  InAppWebView view,
  InAppWebViewController controller,
  WebResourceErrorType type, {
  bool mainFrame = true,
}) => view.platform.params.onReceivedError?.call(
  controller,
  WebResourceRequest(url: _loginUrl, isForMainFrame: mainFrame),
  WebResourceError(type: type, description: 'Fixture navigation error'),
);

Cookie _sessionCookie() => Cookie(
  name: 'SESSDATA',
  value: 'fixture',
  domain: '.bilibili.com',
  path: '/',
  isSecure: true,
  isSessionOnly: true,
);

class _FakePlatform extends InAppWebViewPlatform {
  final cookies = _FakeCookies();
  late _FakeController controller;

  @override
  PlatformWebViewEnvironment createPlatformWebViewEnvironmentStatic() =>
      _FakeEnvironment();

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => cookies;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _FakeView(params, controller);
}

class _FakeEnvironment extends PlatformWebViewEnvironment {
  _FakeEnvironment()
    : super.implementation(const PlatformWebViewEnvironmentCreationParams());

  @override
  Future<String?> getAvailableVersion({
    String? browserExecutableFolder,
  }) async => 'fixture-version';

  @override
  Future<PlatformWebViewEnvironment> create({
    WebViewEnvironmentSettings? settings,
  }) async => this;

  @override
  Future<void> dispose() async {}
}

class _FakeCookies extends PlatformCookieManager {
  _FakeCookies()
    : super.implementation(const PlatformCookieManagerCreationParams());

  List<Cookie> value = [];
  Completer<List<Cookie>>? pending;
  int reads = 0;

  void reset() {
    value = [];
    pending = null;
    reads = 0;
  }

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    expect(url.toString(), 'https://api.bilibili.com/');
    expect(webViewController, isNotNull);
    reads++;
    return pending?.future ?? value;
  }
}

class _FakeController extends PlatformInAppWebViewController {
  _FakeController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'fixture'),
      );

  final requests = <URLRequest>[];

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async => requests.add(urlRequest);
}

class _FakeView extends PlatformInAppWebViewWidget {
  _FakeView(super.params, this.controller) : super.implementation();

  final _FakeController controller;

  @override
  Widget build(BuildContext context) => _FakeNativeView(this);

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _FakeNativeView extends StatefulWidget {
  const _FakeNativeView(this.view);
  final _FakeView view;

  @override
  State<_FakeNativeView> createState() => _FakeNativeViewState();
}

class _FakeNativeViewState extends State<_FakeNativeView> {
  @override
  void initState() {
    super.initState();
    widget.view.params.onWebViewCreated?.call(
      InAppWebViewController.fromPlatform(platform: widget.view.controller),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
