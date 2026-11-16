import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:webview_all/webview_all.dart';

import '../../shared/ui/app_dialog.dart';
import '../presentation/app_input_host.dart';
import 'passport_captcha_page.dart';
import 'passport_webview_environment.dart';

export 'passport_captcha_page.dart';

Future<PassportCaptchaProof?> showPassportCaptcha(
  BuildContext context,
  String gt,
  String challenge,
) async {
  final released = Completer<void>();
  var created = false;
  final event = await showAppDialog<PassportCaptchaEvent>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      created = true;
      return _CaptchaDialog(gt, challenge, released);
    },
  );
  // A route completes before its closing animation and native view disposal.
  // Wait before opening another registration in Android's shared WebView store.
  if (created) {
    try {
      await released.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const PassportCaptchaException();
    }
  }
  switch (event?.kind) {
    case PassportCaptchaEventKind.success:
      return event?.proof;
    case PassportCaptchaEventKind.configurationUnavailable:
      throw const PassportCaptchaException(configurationUnavailable: true);
    case PassportCaptchaEventKind.loadFailed:
      throw const PassportCaptchaException();
    case PassportCaptchaEventKind.cancelled || null:
      return null;
  }
}

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog(this.gt, this.challenge, this.released);
  final String gt, challenge;
  final Completer<void> released;
  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  PassportWebViewEnvironment? _environment;
  WebViewController? _controller;
  WebViewWidget? _webView;
  String? _error;
  bool _loading = true;
  bool _finished = false;
  Timer? _timeout;
  Timer? _loadTimeout;
  late final Future<void> _initialization;
  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(minutes: 3), () {
      _failPage('验证已超时，请关闭后重试');
    });
    _loadTimeout = Timer(
      const Duration(seconds: 30),
      () => _failPage('验证码加载超时，请关闭后重试'),
    );
    _initialization = _initialize();
    unawaited(_initialization);
  }

  Future<void> _initialize() async {
    try {
      final environment = await PassportWebViewEnvironment.create();
      _environment = environment;
      if (!mounted || _finished) return;
      final controller = environment.session.controller;
      final html = passportCaptchaHtml(widget.gt, widget.challenge);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'BiliSailCaptcha',
        onMessageReceived: (message) {
          if (!mounted || _finished || _error != null) return;
          final event = parsePassportCaptchaEvent(message.message);
          if (event == null) return;
          _finished = true;
          Navigator.pop(context, event);
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              !request.isMainFrame ||
                  passportCaptchaPageAllowsNavigation(request.url, html)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            _loadTimeout?.cancel();
            if (mounted && !_finished && _error == null) {
              setState(() => _loading = false);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _failPage('无法加载人机验证，请关闭后重试');
            }
          },
        ),
      );
      if (!mounted || _finished || _error != null) return;
      setState(() => _controller = controller);
      await controller.loadHtmlString(html);
    } catch (_) {
      _failPage('无法加载人机验证，请关闭后重试');
    }
  }

  void _failPage(String message) {
    _loadTimeout?.cancel();
    if (mounted && !_finished && _error == null) {
      setState(() {
        _loading = false;
        _error = message;
      });
    }
  }

  @override
  void dispose() {
    _finished = true;
    _timeout?.cancel();
    _loadTimeout?.cancel();
    unawaited(_releaseEnvironment());
    super.dispose();
  }

  Future<void> _releaseEnvironment() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      await _initialization;
      await _environment?.dispose();
    } catch (_) {
      // Native errors can contain private paths; expose only a typed failure.
    } finally {
      if (!widget.released.isCompleted) widget.released.complete();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<PassportCaptchaEvent>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _finished = true;
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                const Expanded(child: Text('安全验证')),
                if (_loading && _error == null)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  tooltip: '关闭安全验证',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : _controller == null
                  ? const Center(child: CircularProgressIndicator())
                  : NativeInputRegion(
                      child: _webView ??= WebViewWidget(
                        controller: _controller!,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
