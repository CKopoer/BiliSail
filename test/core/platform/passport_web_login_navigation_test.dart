import 'dart:async';

import 'package:bilisail/core/platform/passport_web_login.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import 'fake_passport_webview.dart';

import 'package:flutter_test/flutter_test.dart';

const _pageError = '登录页面加载失败，请检查网络后重试';
final _loginUrl = Uri.parse('https://passport.bilibili.com/login');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePassportPlatform platform;
  final original = WebViewPlatform.instance;
  setUp(() {
    platform = FakePassportPlatform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() => WebViewPlatform.instance = original ?? FakePassportPlatform());

  testWidgets(
    'native desktop focus handoff keeps polling login cookies',
    (tester) async {
      final result = await _open(tester);
      expect(
        find.ancestor(
          of: find.byType(WebViewWidget, skipOffstage: false),
          matching: find.byType(NativeInputRegion),
        ),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      platform.cookies.value = [_sessionCookie()];
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect((await result.value)?.single.name, 'SESSDATA');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  for (final target in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('private session cookies complete login on $target', (
      tester,
    ) async {
      final result = await _open(tester);
      expect(
        platform.controller.params.sessionMode,
        WebViewSessionMode.isolatedIncognito,
      );
      platform.cookies.value = [_sessionCookie()];
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect((await result.value)?.single.value, 'fixture');
      expect(platform.controller.closes, 1);
      expect(find.byType(WebViewWidget, skipOffstage: false), findsNothing);
    }, variant: TargetPlatformVariant({target}));
  }

  testWidgets('cancelled navigation keeps waiting for the login session', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final controller = _controller(view);
    _error(view, controller, WebResourceErrorType.unknown, code: 14);
    await tester.pump();
    expect(find.text(_pageError), findsNothing);
    expect(find.byType(WebViewWidget, skipOffstage: false), findsOneWidget);
    platform.cookies.value = [_sessionCookie()];
    controller.navigation.started?.call(_loginUrl.toString());
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('session already set wins over a failed success redirect', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    platform.cookies.value = [_sessionCookie()];
    _error(view, _controller(view), WebResourceErrorType.connect);
    await tester.pumpAndSettle();
    expect(find.text(_pageError), findsNothing);
    expect((await result.value)?.single.value, 'fixture');
  });

  testWidgets('Windows certificate error is not a cancelled navigation', (
    tester,
  ) async {
    await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    _error(
      view,
      _controller(view),
      WebResourceErrorType.failedSslHandshake,
      code: 5,
    );
    await tester.pumpAndSettle();
    expect(find.text(_pageError), findsOneWidget);
    expect(
      tester
          .widget<Offstage>(
            find
                .ancestor(
                  of: find.byType(WebViewWidget, skipOffstage: false),
                  matching: find.byType(Offstage, skipOffstage: false),
                )
                .first,
          )
          .offstage,
      isTrue,
    );
    await _close(tester);
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('success redirect captures cookies before its document loads', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    platform.cookies.value = [_sessionCookie()];
    final policy = await _controller(view).navigation.request?.call(
      const NavigationRequest(
        url: 'https://www.bilibili.com/',
        isMainFrame: true,
      ),
    );
    expect(policy, NavigationDecision.navigate);
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('load error awaits an existing native cookie read', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final controller = _controller(view);
    final pending = Completer<List<WebViewCookie>>();
    platform.cookies.pending = pending;
    controller.navigation.finished?.call(_loginUrl.toString());
    _error(view, controller, WebResourceErrorType.connect);
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
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final native = tester.element(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    _error(view, _controller(view), WebResourceErrorType.connect);
    await tester.pumpAndSettle();
    expect(find.text(_pageError), findsOneWidget);
    expect(
      tester.element(find.byType(WebViewWidget, skipOffstage: false)),
      same(native),
    );
    expect(
      tester.widget<WebViewWidget>(
        find.byType(WebViewWidget, skipOffstage: false),
      ),
      same(view),
    );
    platform.cookies.value = [_sessionCookie()];
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect((await result.value)?.single.name, 'SESSDATA');
  });

  testWidgets('late failure cannot cover a newer successful navigation', (
    tester,
  ) async {
    await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final controller = _controller(view);
    final pending = Completer<List<WebViewCookie>>();
    platform.cookies.pending = pending;
    _error(view, controller, WebResourceErrorType.connect);
    controller.navigation.started?.call(_loginUrl.toString());
    controller.navigation.finished?.call(_loginUrl.toString());
    pending.complete([]);
    await tester.pump();
    expect(find.text(_pageError), findsNothing);
    await _close(tester);
  });

  testWidgets('subframe errors do not terminate login', (tester) async {
    await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    _error(
      view,
      _controller(view),
      WebResourceErrorType.connect,
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
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final native = tester.element(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final controller = _controller(view);
    _error(view, controller, WebResourceErrorType.connect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新打开登录页'));
    await tester.pump();
    expect(find.text(_pageError), findsNothing);
    expect(platform.controller.requests.last.uri, _loginUrl);
    expect(platform.controller.requests.last.method, LoadRequestMethod.get);
    expect(
      tester.element(find.byType(WebViewWidget, skipOffstage: false)),
      same(native),
    );
    expect(
      tester.widget<WebViewWidget>(
        find.byType(WebViewWidget, skipOffstage: false),
      ),
      same(view),
    );
    await _close(tester);
  });

  testWidgets('closing while cookies are pending discards late success', (
    tester,
  ) async {
    final result = await _open(tester);
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final pending = Completer<List<WebViewCookie>>();
    platform.cookies.pending = pending;
    _error(view, _controller(view), WebResourceErrorType.connect);
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
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    // No reads are started in the background; the overall dialog still expires.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 10));
    await tester.pump();
    platform.cookies.value = [_sessionCookie()];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    _controller(view).navigation.finished?.call(_loginUrl.toString());
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
    final view = tester.widget<WebViewWidget>(
      find.byType(WebViewWidget, skipOffstage: false),
    );
    final pending = Completer<List<WebViewCookie>>();
    platform.cookies.pending = pending;
    _controller(view).navigation.finished?.call(_loginUrl.toString());
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
  for (var attempt = 0; attempt < 50; attempt++) {
    if (find.byType(WebViewWidget, skipOffstage: false).evaluate().isNotEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(find.byType(WebViewWidget, skipOffstage: false), findsOneWidget);
  await tester.pumpAndSettle();
  return (value: result.future);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip('关闭网页登录'));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

FakePassportController _controller(WebViewWidget view) =>
    view.platform.params.controller as FakePassportController;

void _error(
  WebViewWidget view,
  FakePassportController controller,
  WebResourceErrorType type, {
  bool mainFrame = true,
  int code = -1,
}) => controller.navigation.error?.call(
  WebResourceError(
    errorCode: code,
    errorType: type,
    isForMainFrame: mainFrame,
    url: _loginUrl.toString(),
    description: 'Fixture navigation error',
  ),
);

WebViewCookie _sessionCookie() => const WebViewCookie(
  name: 'SESSDATA',
  value: 'fixture',
  domain: '.bilibili.com',
  path: '/',
  isSecure: true,
  isHttpOnly: true,
  isSession: true,
);
