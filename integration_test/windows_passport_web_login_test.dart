import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/platform/passport_web_login.dart';
import 'package:bilisail/core/platform/passport_webview_environment.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _interactivePage = '''<!doctype html><html><body>
  <button id="probe" onclick="this.textContent='Clicked'"
    style="width:200px;height:80px">Click probe</button>
  <input id="editor" style="width:200px;height:80px">
</body></html>''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows passport settings allow webpage mouse interaction', (
    tester,
  ) async {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    final profile = await PassportWebViewEnvironment.create(
      await getApplicationSupportDirectory(),
    );
    InAppWebViewController? controller;
    var loaded = false;
    final routes = InputRouteObserver();
    final dispatcher = ShortcutDispatcher<String>(
      scopeFor: (_) => CommandScope.workspace,
      repeats: (_) => false,
      editorException: (_, _) => false,
    );
    addTearDown(dispatcher.dispose);
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
                        child: InAppWebView(
                          webViewEnvironment: profile.environment,
                          initialData: InAppWebViewInitialData(
                            data: _interactivePage,
                          ),
                          initialSettings: InAppWebViewSettings(
                            incognito: true,
                            generalAutofillEnabled: false,
                            passwordAutosaveEnabled: false,
                            isInspectable: false,
                            sharedCookiesEnabled: false,
                            javaScriptBridgeEnabled: false,
                          ),
                          onWebViewCreated: (value) => controller = value,
                          onLoadStop: (_, _) => loaded = true,
                        ),
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
    for (var tick = 0; tick < 30 && !loaded; tick++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(loaded, isTrue);
    final view = controller!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    for (var navigation = 0; navigation < 2; navigation++) {
      if (navigation > 0) {
        loaded = false;
        await view.loadData(data: _interactivePage);
        for (var tick = 0; tick < 15 && !loaded; tick++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(loaded, isTrue);
      }
      await _clickHtml(tester, view, mouse, 'probe');
      expect(
        await view.evaluateJavascript(
          source: "document.getElementById('probe').textContent",
        ),
        'Clicked',
      );
      await _clickHtml(tester, view, mouse, 'editor');
      expect(
        await view.evaluateJavascript(source: 'document.activeElement.id'),
        'editor',
      );
    }
    await mouse.removePointer();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    await profile.dispose();
  });

  testWidgets('Windows login profiles isolate native incognito cookies', (
    tester,
  ) async {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    expect(await WebViewEnvironment.getAvailableVersion(), isNotNull);
    final support = await getApplicationSupportDirectory();
    String? previousDirectory;
    final url = WebUri('https://api.bilibili.com/');
    for (var attempt = 0; attempt < 2; attempt++) {
      final profile = await PassportWebViewEnvironment.create(support);
      expect(profile.userDataDirectory.path, isNot(previousDirectory));
      previousDirectory = profile.userDataDirectory.path;
      InAppWebViewController? controller;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              webViewEnvironment: profile.environment,
              initialData: InAppWebViewInitialData(
                data: '<p>Login profile probe</p>',
              ),
              initialSettings: InAppWebViewSettings(
                incognito: true,
                javaScriptBridgeEnabled: false,
              ),
              onWebViewCreated: (value) => controller = value,
            ),
          ),
        ),
      );
      for (var tick = 0; tick < 30 && controller == null; tick++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final viewController = controller;
      expect(viewController, isNotNull);
      final cookies = CookieManager.instance(
        webViewEnvironment: profile.environment,
      );
      expect(
        (await cookies.getCookies(
          url: url,
          webViewController: viewController,
        )).any((cookie) => cookie.name == 'bilisail_login_probe'),
        isFalse,
      );
      expect(
        await cookies.setCookie(
          url: url,
          name: 'bilisail_login_probe',
          value: 'fixture',
          isSecure: true,
          webViewController: viewController,
        ),
        isTrue,
      );
      expect(
        (await cookies.getCookies(
          url: url,
          webViewController: viewController,
        )).any(
          (cookie) =>
              cookie.name == 'bilisail_login_probe' &&
              cookie.value == 'fixture',
        ),
        isTrue,
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
      await profile.dispose();
      expect(await profile.userDataDirectory.exists(), isFalse);
    }
  });

  testWidgets('Windows opens and reopens the official passport dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(showPassportWebLogin(context)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    String? previousDirectory;
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Open'));
      await tester.pump();
      for (var tick = 0; tick < 30; tick++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(InAppWebView).evaluate().isNotEmpty) break;
      }
      expect(find.text('无法打开网页登录，请重试或使用扫码登录'), findsNothing);
      expect(find.byType(InAppWebView), findsOneWidget);
      final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final directory =
          view.platform.params.webViewEnvironment?.settings?.userDataFolder;
      expect(directory, isNotNull);
      expect(directory, isNot(previousDirectory));
      previousDirectory = directory;
      for (var tick = 0; tick < 10; tick++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('无法读取网页登录会话，请重试或使用扫码登录'), findsNothing);
      expect(find.text('登录页面加载失败，请检查网络后重试'), findsNothing);
      await tester.tap(find.byTooltip('关闭网页登录'));
      await tester.pumpAndSettle();
      for (
        var tick = 0;
        tick < 5 && await Directory(directory!).exists();
        tick++
      ) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(await Directory(directory!).exists(), isFalse);
    }
  });
}

Future<void> _clickHtml(
  WidgetTester tester,
  InAppWebViewController view,
  TestGesture mouse,
  String id,
) async {
  final raw = await view.evaluateJavascript(
    source:
        '''JSON.stringify((() => {
      const r = document.getElementById(${jsonEncode(id)}).getBoundingClientRect();
      return {x: r.x+r.width/2, y: r.y+r.height/2};
    })())''',
  );
  final point = jsonDecode(raw as String) as Map<String, Object?>;
  final position =
      tester.getTopLeft(find.byType(InAppWebView)) +
      Offset((point['x']! as num).toDouble(), (point['y']! as num).toDouble());
  await mouse.moveTo(position);
  await tester.pump(const Duration(milliseconds: 100));
  await mouse.down(position);
  await tester.pump(const Duration(milliseconds: 100));
  await mouse.up();
  await tester.pump(const Duration(milliseconds: 300));
}
