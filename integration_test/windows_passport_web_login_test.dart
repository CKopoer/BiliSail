import 'dart:async';
import 'dart:convert';

import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/platform/passport_captcha.dart';
import 'package:bilisail/core/platform/passport_web_cookies.dart';
import 'package:bilisail/core/platform/passport_webview_environment.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

const _interactivePage = '''<!doctype html><html><body>
  <button id="probe" onclick="this.textContent='Clicked'"
    style="width:200px;height:80px">Click probe</button>
  <input id="editor" style="width:200px;height:80px">
</body></html>''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native captcha document loads, accepts input and returns proof', (
    tester,
  ) async {
    final environment = await PassportWebViewEnvironment.create();
    final controller = environment.session.controller;
    addTearDown(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
      await environment.dispose();
    });
    // Replace only the remote provider with a fixture. Keep our real generated
    // page, navigation policy, WebView2, JavaScript channel and native input.
    final html = passportCaptchaHtml('fixture-gt', 'fixture-challenge')
        .replaceAll(RegExp(r'<script src="[^"]+"[^>]*></script>'), '')
        .replaceFirst('</body>', '''<script>
window.Geetest=function(options){
  var handlers={},instance={
    onSuccess:function(f){handlers.success=f;return instance;},
    onError:function(f){return instance;},
    onClose:function(f){return instance;},
    onReady:function(f){f();return instance;},
    verify:function(){document.body.dataset.verifications=
      String(Number(document.body.dataset.verifications||0)+1);},
    getValidate:function(){return {geetest_challenge:'fixture-challenge',
      geetest_validate:'fixture-validate',geetest_seccode:'fixture-seccode'};}
  };
  var button=document.createElement('button');
  button.id='complete';button.textContent='Complete fixture';
  button.style.cssText='display:block;width:200px;height:80px';
  button.onclick=function(){handlers.success();};
  document.body.appendChild(button);
  return instance;
};
libraryReady();BiliSailCaptchaConfiguration({status:'success',data:{}});
</script></body>''');
    PassportCaptchaEvent? event;
    var loaded = false;
    var failed = false;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'BiliSailCaptcha',
      onMessageReceived: (message) =>
          event = parsePassportCaptchaEvent(message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            !request.isMainFrame ||
                passportCaptchaPageAllowsNavigation(request.url, html)
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) => loaded = true,
        onWebResourceError: (_) => failed = true,
      ),
    );
    // Match the production dialog: start loading before the view is attached.
    await controller.loadHtmlString(html);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 440,
              height: 472,
              child: NativeInputRegion(
                child: WebViewWidget(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
    for (var tick = 0; tick < 30 && !loaded; tick++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(loaded, isTrue);
    expect(failed, isFalse);
    expect(
      await controller.runJavaScriptReturningResult(
        "document.getElementById('status').textContent",
      ),
      '请完成人机验证',
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await _clickHtml(tester, controller, mouse, 'retry');
    expect(
      await controller.runJavaScriptReturningResult(
        'document.body.dataset.verifications',
      ),
      '2',
    );
    await _clickHtml(tester, controller, mouse, 'complete');
    expect(event?.kind, PassportCaptchaEventKind.success);
    expect(event?.proof?.validate, 'fixture-validate');
    await mouse.removePointer();
  });

  testWidgets(
    'private WebView accepts clicks and editing inside the input host',
    (tester) async {
      final environment = await PassportWebViewEnvironment.create();
      final controller = environment.session.controller;
      var loaded = false;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => loaded = true),
      );
      final routes = InputRouteObserver();
      final dispatcher = ShortcutDispatcher<String>(
        scopeFor: (_) => CommandScope.workspace,
        repeats: (_) => false,
        editorException: (_, _) => false,
      );
      addTearDown(dispatcher.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpAndSettle();
        await environment.dispose();
      });
      final window = WindowService();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          builder: (_, child) => AppInputHost<String>(
            dispatcher: dispatcher,
            routes: routes,
            onEditingChanged: window.setTextInputActive,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showAppDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SizedBox(
                        width: 600,
                        height: 400,
                        child: NativeInputRegion(
                          child: WebViewWidget(controller: controller),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open fixture'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open fixture'));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      for (var navigation = 0; navigation < 2; navigation++) {
        loaded = false;
        await controller.loadHtmlString(_interactivePage);
        for (var tick = 0; tick < 30 && !loaded; tick++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(loaded, isTrue);
        await _clickHtml(tester, controller, mouse, 'probe');
        expect(
          await controller.runJavaScriptReturningResult(
            "document.getElementById('probe').textContent",
          ),
          'Clicked',
        );
        await _clickHtml(tester, controller, mouse, 'editor');
        expect(
          await controller.runJavaScriptReturningResult(
            'document.activeElement.id',
          ),
          'editor',
        );
      }
      await mouse.removePointer();
    },
  );

  testWidgets('native private stores isolate full HttpOnly cookies', (
    tester,
  ) async {
    final url = Uri.https('api.bilibili.com', '/');
    final sessions = <PassportWebViewEnvironment>[];
    addTearDown(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
      for (final environment in sessions) {
        await environment.dispose();
      }
    });
    for (var attempt = 0; attempt < 2; attempt++) {
      final environment = await PassportWebViewEnvironment.create();
      sessions.add(environment);
      final session = environment.session;
      var loaded = false;
      await session.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await session.controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => loaded = true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebViewWidget(controller: session.controller)),
        ),
      );
      await tester.pumpAndSettle();
      await session.controller.loadHtmlString('<h1>Private login probe</h1>');
      for (var tick = 0; tick < 30 && !loaded; tick++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(loaded, isTrue);
      expect(await session.controller.runJavaScriptReturningResult('1 + 1'), 2);
      final reader = PassportWebCookieReader();
      await reader.checkSupport(session);
      expect(await reader.read(session), isEmpty);
      final expiry = DateTime.utc(2027);
      await session.cookieManager.setCookie(
        WebViewCookie(
          name: 'bilisail_login_probe',
          value: 'fixture',
          domain: '.bilibili.com',
          isSecure: true,
          isHttpOnly: true,
          expires: expiry,
        ),
      );
      final cookie = (await session.cookieManager.getCookies(domain: url))
          .single;
      expect(cookie.value, 'fixture');
      expect(cookie.isHttpOnly, isTrue);
      expect(cookie.isSecure, isTrue);
      expect(cookie.isSession, isFalse);
      expect(cookie.expires?.toUtc(), expiry);
      // Retain the first native session while opening the second: store
      // isolation must work even before the old browser process has exited.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
    }
  });
}

Future<void> _clickHtml(
  WidgetTester tester,
  WebViewController view,
  TestGesture mouse,
  String id,
) async {
  final raw = await view.runJavaScriptReturningResult('''JSON.stringify((() => {
      const r = document.getElementById(${jsonEncode(id)}).getBoundingClientRect();
      return {x: r.x+r.width/2, y: r.y+r.height/2};
    })())''');
  final point = jsonDecode(raw as String) as Map<String, Object?>;
  final position =
      tester.getTopLeft(find.byType(WebViewWidget)) +
      Offset((point['x']! as num).toDouble(), (point['y']! as num).toDouble());
  await mouse.moveTo(position);
  await tester.pump(const Duration(milliseconds: 100));
  await mouse.down(position);
  await tester.pump(const Duration(milliseconds: 100));
  await mouse.up();
  await tester.pump(const Duration(milliseconds: 300));
}
