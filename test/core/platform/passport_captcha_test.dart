import '../../support/material_tooltip_finder.dart';

import 'dart:convert';
import 'dart:async';

import 'package:bilisail/core/platform/passport_captcha.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import 'fake_passport_webview.dart';

void main() {
  final original = WebViewPlatform.instance;
  late FakePassportPlatform platform;
  setUp(() {
    platform = FakePassportPlatform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() => WebViewPlatform.instance = original ?? FakePassportPlatform());

  test('captcha navigation accepts only the owned local document', () {
    final html = passportCaptchaHtml('fixture-gt', 'fixture-challenge');
    for (final base64 in [true, false]) {
      final url = Uri.dataFromString(
        html,
        mimeType: 'text/html',
        encoding: utf8,
        base64: base64,
      ).toString();
      expect(passportCaptchaPageAllowsNavigation(url, html), isTrue);
    }
    expect(passportCaptchaPageAllowsNavigation('about:blank', html), isTrue);
    for (final url in [
      'https://example.com',
      'javascript:alert(1)',
      'file:///captcha.html',
      'data:text/html;base64,%%%invalid',
      Uri.dataFromString(
        '$html<script>alert(1)</script>',
        encoding: utf8,
      ).toString(),
      Uri.dataFromString(
        html,
        mimeType: 'text/plain',
        encoding: utf8,
      ).toString(),
      Uri.dataFromString(
        passportCaptchaHtml('other-registration', 'fixture-challenge'),
        mimeType: 'text/html',
        encoding: utf8,
      ).toString(),
    ]) {
      expect(passportCaptchaPageAllowsNavigation(url, html), isFalse);
    }
  });

  for (final failure in ['timeout', 'main-frame error']) {
    testWidgets('captcha reports $failure instead of an empty view', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showPassportCaptcha(context, 'fixture-gt', 'fixture-challenge'),
              ),
              child: const Text('验证'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('验证'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final native = platform.controller;
      final html = native.html!;
      expect(
        await native.navigation.request!(
          NavigationRequest(
            url: Uri.dataFromString(
              html,
              mimeType: 'text/html',
              encoding: utf8,
              base64: true,
            ).toString(),
            isMainFrame: true,
          ),
        ),
        NavigationDecision.navigate,
      );
      if (failure == 'timeout') {
        await tester.pump(const Duration(seconds: 30));
      } else {
        native.navigation.error!(
          WebResourceError(
            errorCode: -2,
            description: 'fixture error',
            isForMainFrame: true,
          ),
        );
        await tester.pump();
      }
      expect(
        find.text(failure == 'timeout' ? '验证码加载超时，请关闭后重试' : '无法加载人机验证，请关闭后重试'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(findMaterialTooltip('关闭安全验证'));
      await tester.pumpAndSettle();
      expect(native.closes, 1);
    });
  }

  for (final code in ['configuration_unavailable', 'load_failed']) {
    testWidgets(
      'captcha error closes its private view and reaches the caller: $code',
      (tester) async {
        Future<PassportCaptchaProof?>? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    result = showPassportCaptcha(
                      context,
                      'fixture-gt',
                      'fixture-challenge',
                    );
                  },
                  child: const Text('验证'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('验证'));
        await tester.pump();
        await tester.pump();
        platform.controller.navigation.finished!('about:blank');
        await tester.pumpAndSettle();
        final expected = expectLater(
          result!,
          throwsA(
            isA<PassportCaptchaException>().having(
              (e) => e.configurationUnavailable,
              'unavailable',
              code == 'configuration_unavailable',
            ),
          ),
        );
        final native = platform.controller;
        native.channels['BiliSailCaptcha']!.onMessageReceived(
          JavaScriptMessage(
            message: jsonEncode({'type': 'error', 'code': code}),
          ),
        );
        await tester.pumpAndSettle();
        await expected;
        expect(native.closes, 1);
      },
    );
  }

  testWidgets('captcha caller waits for native store release before retrying', (
    tester,
  ) async {
    Future<PassportCaptchaProof?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                result = showPassportCaptcha(
                  context,
                  'fixture-gt',
                  'fixture-challenge',
                );
              },
              child: const Text('验证'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('验证'));
    await tester.pump();
    await tester.pump();
    platform.controller.navigation.finished!('about:blank');
    await tester.pumpAndSettle();
    final cleanup = Completer<void>();
    platform.data.pending = cleanup;
    var finished = false;
    final handled = result!.then<void>(
      (_) {
        finished = true;
      },
      onError: (Object _) {
        finished = true;
      },
    );
    platform.controller.channels['BiliSailCaptcha']!.onMessageReceived(
      const JavaScriptMessage(
        message: '{"type":"error","code":"configuration_unavailable"}',
      ),
    );
    await tester.pumpAndSettle();
    expect(finished, isFalse);
    cleanup.complete();
    await tester.pumpAndSettle();
    await handled;
    expect(finished, isTrue);
    expect(platform.controller.closes, 1);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  test('fullpage config uses a supported JSONP callback and binds it before loading', () {
    final html = passportCaptchaHtml('fixture-gt', 'fixture-challenge');
    final source = RegExp(r'src="([^"]*)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .firstWhere((s) => s.contains('api.geetest.com'));
    final decoded = source.replaceAll('&amp;', '&').replaceAll('&#47;', '/');
    final uri = Uri.parse(decoded);
    final callback = uri.queryParameters['callback']!;
    expect(callback, matches(r'^geetest_[0-9]+$'));
    expect(uri.queryParameters['gt'], 'fixture-gt');
    expect(
      html.indexOf('window["$callback"]=BiliSailCaptchaConfiguration;'),
      lessThan(html.indexOf('src="$source"')),
    );
    expect(html, contains("product:'bind'"));
    expect(html, contains('captcha.verify()'));
    expect(html, isNot(contains('initGeetest(')));
  });

  test(
    'captcha cancellation and malformed success have distinct bridge results',
    () {
      expect(
        parsePassportCaptchaEvent('{"type":"cancelled"}')?.kind,
        PassportCaptchaEventKind.cancelled,
      );
      expect(
        parsePassportCaptchaEvent('{"type":"success","proof":{}}')?.kind,
        PassportCaptchaEventKind.loadFailed,
      );
      expect(parsePassportCaptchaEvent('invalid'), isNull);
    },
  );

  for (final complete in [true, false]) {
    testWidgets(
      'private captcha session closes and rejects late proof: complete=$complete',
      (tester) async {
        final result = Completer<PassportCaptchaProof?>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    unawaited(
                      showPassportCaptcha(
                        context,
                        'fixture-gt',
                        'fixture-challenge',
                      ).then(result.complete),
                    );
                  },
                  child: const Text('验证'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('验证'));
        await tester.pump();
        await tester.pump();
        platform.controller.navigation.finished!('about:blank');
        await tester.pumpAndSettle();
        final native = platform.controller;
        expect(native.html, contains('fixture-gt'));
        expect(
          await native.navigation.request!(
            NavigationRequest(url: 'https://example.com', isMainFrame: true),
          ),
          NavigationDecision.prevent,
        );
        final channel = native.channels['BiliSailCaptcha']!;
        const proof =
            '{"type":"success","proof":{"geetest_challenge":"fixture-challenge","geetest_validate":"v","geetest_seccode":"s"}}';
        if (complete) {
          channel.onMessageReceived(const JavaScriptMessage(message: proof));
        } else {
          await tester.tap(findMaterialTooltip('关闭安全验证'));
        }
        channel.onMessageReceived(const JavaScriptMessage(message: proof));
        await tester.pumpAndSettle();
        expect((await result.future)?.validate, complete ? 'v' : null);
        expect(native.closes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('captcha bridge accepts only complete bounded proof values', () {
    final data = {
      'geetest_challenge': 'fixture-challenge',
      'geetest_validate': 'fixture-validate',
      'geetest_seccode': 'fixture-seccode',
    };
    expect(
      parsePassportCaptchaProof(jsonEncode(data))?.validate,
      'fixture-validate',
    );
    for (final key in data.keys) {
      expect(
        parsePassportCaptchaProof(jsonEncode({...data}..remove(key))),
        isNull,
      );
      expect(parsePassportCaptchaProof(jsonEncode({...data, key: ''})), isNull);
      expect(
        parsePassportCaptchaProof(jsonEncode({...data, key: 'invalid\nvalue'})),
        isNull,
      );
    }
    expect(parsePassportCaptchaProof('not json'), isNull);
    expect(parsePassportCaptchaProof('x' * 16385), isNull);
  });
  test('server captcha values cannot escape the initialization script', () {
    final html = passportCaptchaHtml('</script><img src=x>', 'fixture');
    expect(html, isNot(contains('</script><img')));
    expect(html, contains(r'\u003c/script>'));
    expect(
      html,
      contains('https://static.geetest.com/static/js/fullpage.0.0.0.js'),
    );
    expect(html, isNot(contains('http://')));
    expect(html, contains('BiliSailCaptcha.postMessage'));
  });
}
