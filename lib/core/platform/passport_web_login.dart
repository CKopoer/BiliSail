import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'passport_webview_environment.dart';

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

  factory BrowserLoginCookie.fromNative(
    Cookie cookie, {
    required bool windowsExpiryInSeconds,
  }) {
    final Object? value = cookie.value;
    final secure = cookie.isSecure;
    if (value is! String || secure == null) {
      throw const FormatException('Incomplete native cookie metadata');
    }
    final domain = cookie.domain?.toLowerCase();
    final expiresDate = cookie.expiresDate;
    // Windows 0.7.0-beta.3 passes CDP's seconds through unchanged. Android
    // and WKWebView return milliseconds; do not reinterpret those timestamps.
    final expires = cookie.isSessionOnly == true || expiresDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            windowsExpiryInSeconds ? expiresDate * 1000 : expiresDate,
            isUtc: true,
          );
    return BrowserLoginCookie(
      cookie.name,
      value,
      (domain ?? 'api.bilibili.com').replaceFirst(RegExp(r'^\.'), ''),
      cookie.path ?? '/',
      domain == null ||
          (domain == 'api.bilibili.com' && !domain.startsWith('.')),
      secure,
      expires,
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
  // WebView event logging can include authenticated URLs and Cookie values.
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  return showDialog<List<BrowserLoginCookie>>(
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
  InAppWebViewController? _controller;
  Timer? _poll;
  Timer? _timeout;
  bool _ready = false;
  bool _capturing = false;
  bool _paused = false;
  bool _finished = false;
  String? _error;

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
      if (Platform.isAndroid &&
          !await WebViewFeature.isFeatureSupported(
            WebViewFeature.GET_COOKIE_INFO,
          )) {
        _fail('请更新 Android System WebView 后使用密码／短信登录，或使用扫码登录');
        return;
      }
      PassportWebViewEnvironment? environment;
      if (Platform.isWindows) {
        if (await WebViewEnvironment.getAvailableVersion() == null) {
          _fail('网页登录需要 Microsoft Edge WebView2 Runtime，请安装后重试或使用扫码登录');
          return;
        }
        environment = await PassportWebViewEnvironment.create(
          await getApplicationSupportDirectory(),
        );
      }
      if (!mounted || _finished || _error != null) {
        await environment?.dispose();
        return;
      }
      setState(() {
        _environment = environment;
        _ready = true;
      });
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_capture()),
      );
    } catch (_) {
      _fail(
        Platform.isWindows
            ? '无法创建网页登录窗口。若以管理员权限运行，请关闭应用后以普通权限重新启动；也可使用扫码登录。'
            : '无法打开网页登录，请重试或使用扫码登录',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) unawaited(_capture());
  }

  void _fail(String message) {
    if (mounted && !_finished) setState(() => _error = message);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        _capturing ||
        _paused ||
        _finished ||
        _error != null) {
      return;
    }
    _capturing = true;
    try {
      // Fetch cookies applicable to the API root, retaining their native scope.
      final cookies =
          await CookieManager.instance(
            webViewEnvironment: _environment?.environment,
          ).getCookies(
            url: WebUri('https://api.bilibili.com/'),
            webViewController: controller,
          );
      if (!mounted ||
          _paused ||
          _finished ||
          _error != null ||
          !cookies.any(
            (cookie) =>
                cookie.name == 'SESSDATA' &&
                cookie.value is String &&
                (cookie.value as String).isNotEmpty,
          )) {
        return;
      }
      final result = <BrowserLoginCookie>[];
      for (final cookie in cookies) {
        result.add(
          BrowserLoginCookie.fromNative(
            cookie,
            windowsExpiryInSeconds: Platform.isWindows,
          ),
        );
      }
      _finished = true;
      Navigator.pop(context, List<BrowserLoginCookie>.unmodifiable(result));
    } on FormatException {
      _fail('当前系统 WebView 无法读取完整会话信息，请更新后重试或使用扫码登录');
    } catch (_) {
      _fail('无法读取网页登录会话，请重试或使用扫码登录');
    } finally {
      _capturing = false;
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
      await environment.dispose();
    } catch (_) {
      // Closing the dialog must not surface a native shutdown exception.
      // Do not log the exception: plugin errors can contain private paths.
      debugPrint('passport_webview: environment shutdown failed');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
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
                : InAppWebView(
                    webViewEnvironment: _environment?.environment,
                    initialUrlRequest: URLRequest(
                      url: WebUri('https://passport.bilibili.com/login'),
                    ),
                    initialSettings: InAppWebViewSettings(
                      incognito: true,
                      generalAutofillEnabled: false,
                      passwordAutosaveEnabled: false,
                      isInspectable: false,
                      sharedCookiesEnabled: false,
                      useShouldOverrideUrlLoading: true,
                      javaScriptBridgeEnabled: false,
                    ),
                    onWebViewCreated: (controller) => _controller = controller,
                    onLoadStop: (_, _) => unawaited(_capture()),
                    shouldOverrideUrlLoading: (_, action) async {
                      final uri = action.request.url;
                      if (!action.isForMainFrame) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      return uri != null &&
                              uri.scheme == 'https' &&
                              (uri.host == 'bilibili.com' ||
                                  uri.host.endsWith('.bilibili.com'))
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                    onReceivedError: (_, request, _) {
                      if (request.isForMainFrame == true) {
                        _fail('登录页面加载失败，请检查网络后重试');
                      }
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
