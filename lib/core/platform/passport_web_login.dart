import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_all/webview_all.dart';

import '../../shared/ui/app_dialog.dart';
import '../presentation/app_input_host.dart';
import 'passport_web_cookies.dart';
import 'passport_webview_environment.dart';

bool passportWebLoginSupportedForPlatform(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };

final class BrowserLoginCookie {
  const BrowserLoginCookie(
    this.name,
    this.value,
    this.domain,
    this.path,
    this.hostOnly,
    this.secure,
    this.expires,
  );

  factory BrowserLoginCookie.fromNative(WebViewCookie cookie) {
    cookie.validate();
    final secure = cookie.isSecure;
    if (secure == null ||
        cookie.isSession == null ||
        (cookie.isSession == false && cookie.expires == null)) {
      throw const FormatException('Incomplete native cookie metadata');
    }
    final domain = cookie.domain.toLowerCase();
    return BrowserLoginCookie(
      cookie.name,
      cookie.value,
      domain.replaceFirst(RegExp(r'^\.'), ''),
      cookie.path,
      !domain.startsWith('.'),
      secure,
      cookie.isSession == true ? null : cookie.expires?.toUtc(),
    );
  }
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expires;
}

Future<List<BrowserLoginCookie>?> showPassportWebLogin(BuildContext context) {
  return showAppDialog<List<BrowserLoginCookie>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PassportDialog(),
  );
}

class _PassportDialog extends StatefulWidget {
  const _PassportDialog();
  @override
  State<_PassportDialog> createState() => _PassportDialogState();
}

class _PassportDialogState extends State<_PassportDialog>
    with WidgetsBindingObserver {
  PassportWebViewEnvironment? _environment;
  WebViewController? _controller;
  WebViewWidget? _webView;
  Timer? _poll;
  Timer? _timeout;
  bool _ready = false;
  Future<void>? _captureOperation;
  bool _paused = false;
  bool _finished = false;
  int _navigationGeneration = 0;
  String? _error;
  String? _pageError;
  final _cookieReader = PassportWebCookieReader();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeout = Timer(
      const Duration(minutes: 10),
      () => _fail('登录页面已超时，请关闭后重试'),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final environment = await PassportWebViewEnvironment.create();
      _environment = environment;
      await _cookieReader.checkSupport(environment.session);
      final controller = environment.session.controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _pageLoadedOrStarted(),
          onPageFinished: (_) => _pageLoadedOrStarted(),
          onUrlChange: (_) => unawaited(_capture()),
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            unawaited(_capture());
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    uri.scheme == 'https' &&
                    (uri.host == 'bilibili.com' ||
                        uri.host.endsWith('.bilibili.com'))
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) => unawaited(_pageFailed(error)),
        ),
      );
      if (!mounted || _finished || _error != null) {
        await environment.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
      await controller.loadRequest(
        Uri.parse('https://passport.bilibili.com/login'),
      );
      if (!mounted || _finished || _error != null) return;
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_capture()),
      );
    } on FormatException {
      _fail('当前系统 WebView 无法读取完整会话信息，请更新后重试或使用扫码登录');
    } catch (_) {
      _fail(
        Platform.isWindows
            ? '无法创建网页登录窗口，请安装或更新 Microsoft Edge WebView2 Runtime，或使用扫码登录。'
            : '无法打开网页登录，请重试或使用扫码登录',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A focused native desktop child can leave its Flutter view inactive while
    // the login page is still visible and accepting input.
    _paused =
        state != AppLifecycleState.resumed &&
        !((defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux) &&
            state == AppLifecycleState.inactive);
    if (!_paused) unawaited(_capture());
  }

  void _fail(String message) {
    if (mounted && !_finished) setState(() => _error = message);
  }

  Future<void> _capture() {
    // Error callbacks must await a read already in flight before deciding that
    // login failed. Starting a second read can also race native view disposal.
    return _captureOperation ??= _readCookies().whenComplete(
      () => _captureOperation = null,
    );
  }

  Future<void> _readCookies() async {
    final environment = _environment;
    if (_controller == null ||
        environment == null ||
        _paused ||
        _finished ||
        _error != null) {
      return;
    }
    try {
      // Fetch cookies applicable to the API root, retaining their native scope.
      final cookies = await _cookieReader
          .read(environment.session)
          .timeout(const Duration(seconds: 10));
      if (!mounted ||
          _paused ||
          _finished ||
          _error != null ||
          !cookies.any(
            (cookie) => cookie.name == 'SESSDATA' && cookie.value.isNotEmpty,
          )) {
        return;
      }
      final result = <BrowserLoginCookie>[];
      for (final cookie in cookies) {
        result.add(BrowserLoginCookie.fromNative(cookie));
      }
      _finished = true;
      Navigator.pop(context, List<BrowserLoginCookie>.unmodifiable(result));
    } on FormatException {
      _fail('当前系统 WebView 无法读取完整会话信息，请更新后重试或使用扫码登录');
    } catch (_) {
      _fail('无法读取网页登录会话，请重试或使用扫码登录');
    }
  }

  void _pageLoadedOrStarted() {
    _navigationGeneration++;
    if (mounted && !_finished && _pageError != null) {
      setState(() => _pageError = null);
    }
    unawaited(_capture());
  }

  Future<void> _pageFailed(WebResourceError error) async {
    if (error.isForMainFrame != true) return;
    // Native cancellation codes: WKWebView -999, WebKitGTK 302 and WebView2
    // OPERATION_CANCELED 14. The cross-platform enum has no cancelled member.
    final cancelled = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => error.errorCode == -999,
      TargetPlatform.linux => error.errorCode == 302,
      TargetPlatform.windows => error.errorCode == 14,
      _ => false,
    };
    if (cancelled) {
      // WebView2/WKWebView report superseded or policy-cancelled navigation as
      // an error too. It does not invalidate cookies created by the login POST.
      await _capture();
      return;
    }
    final generation = _navigationGeneration;
    await _capture();
    if (mounted &&
        !_finished &&
        _error == null &&
        generation == _navigationGeneration) {
      setState(() => _pageError = '登录页面加载失败，请检查网络后重试');
    }
  }

  Future<void> _retryPage() async {
    await _capture();
    if (!mounted || _finished || _error != null) return;
    _pageLoadedOrStarted();
    try {
      // Reloading the failed navigation can replay a password/SMS form POST.
      // An explicit retry always opens the original login page with a GET.
      await _controller?.loadRequest(
        Uri.parse('https://passport.bilibili.com/login'),
      );
    } catch (_) {
      if (mounted && !_finished && _error == null) {
        setState(() => _pageError = '登录页面加载失败，请检查网络后重试');
      }
    }
  }

  @override
  void dispose() {
    _finished = true;
    _poll?.cancel();
    _timeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Remove the native view before releasing its environment/profile.
    final environment = _environment;
    if (environment != null) {
      unawaited(_releaseEnvironment(environment));
    }
    super.dispose();
  }

  Future<void> _releaseEnvironment(
    PassportWebViewEnvironment environment,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    try {
      await _captureOperation;
      await environment.dispose();
    } catch (_) {
      // Closing the dialog must not surface a native shutdown exception.
      // Do not log the exception: plugin errors can contain private paths.
      debugPrint('passport_webview: environment shutdown failed');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<List<BrowserLoginCookie>>(
    onPopInvokedWithResult: (didPop, _) {
      // A popped route stays mounted during its closing animation.
      if (didPop) _finished = true;
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('哔哩哔哩官网登录')),
                  IconButton(
                    tooltip: '关闭网页登录',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // The platform delegate owns the native controller.
                        // Keep both identities stable while showing errors.
                        // GTK renders above Flutter. Hide its native surface
                        // while keeping the session alive behind retry UI.
                        Offstage(
                          offstage: _pageError != null,
                          child: NativeInputRegion(
                            child: _webView ??= WebViewWidget(
                              controller: _controller!,
                            ),
                          ),
                        ),
                        if (_pageError case final message?)
                          ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(message, textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () => unawaited(_retryPage()),
                                      child: const Text('重新打开登录页'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
