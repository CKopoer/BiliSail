import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/passport_captcha.dart';
import '../../../domain/app_failure.dart';
import '../application/auth_controller.dart';
import '../domain/password_sms_auth_repository.dart';

typedef LoginCaptchaPresenter = Future<LoginCaptchaProof?> Function(
  BuildContext context,
  String gt,
  String challenge,
);
final loginCaptchaPresenterProvider = Provider<LoginCaptchaPresenter>(
  (ref) => (context, gt, challenge) async {
    try {
      final proof = await showPassportCaptcha(context, gt, challenge);
      return proof == null
          ? null
          : LoginCaptchaProof(proof.challenge, proof.validate, proof.seccode);
    } on PassportCaptchaException catch (error) {
      throw LoginCaptchaException(
        configurationUnavailable: error.configurationUnavailable,
      );
    }
  },
);

class PasswordSmsLoginDialog extends ConsumerStatefulWidget {
  const PasswordSmsLoginDialog({super.key, required this.attempt});
  final PasswordSmsLoginAttempt attempt;
  @override
  ConsumerState<PasswordSmsLoginDialog> createState() =>
      _PasswordSmsLoginDialogState();
}

class _PasswordSmsLoginDialogState extends ConsumerState<PasswordSmsLoginDialog>
    with WidgetsBindingObserver {
  final _username = TextEditingController(),
      _password = TextEditingController(),
      _country = TextEditingController(text: '86'),
      _phone = TextEditingController(),
      _code = TextEditingController();
  late final AuthController _auth;
  bool _sms = false, _busy = false, _sent = false, _finished = false;
  String? _maskedPhone, _error;
  Timer? _cooldownTimer;
  int _cooldown = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    _auth = ref.read(authControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_busy &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      _generation++;
      _auth.cancelSignIn();
      setState(() {
        _busy = false;
        _finished = true;
        _error = '登录已取消，请关闭后重新登录';
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _auth.cancelSignIn();
    _cooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final field in [_username, _password, _country, _phone, _code]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _run(
    Future<PasswordSmsLoginStep> Function(LoginCaptchaProof?) operation,
  ) async {
    if (_busy || _finished) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      LoginCaptchaProof? proof;
      PasswordSmsLoginStep? refreshed;
      for (var challenges = 0; challenges < 3; challenges++) {
        final step = refreshed ?? await operation(proof);
        refreshed = null;
        if (!mounted || generation != _generation || _finished) return;
        switch (step.stage) {
          case PasswordSmsLoginStage.captcha:
            final gt = step.gt, challenge = step.challenge;
            if (gt == null || challenge == null) {
              throw const AppFailure(AppFailureKind.protocol, '验证信息不完整');
            }
            try {
              proof = await ref.read(loginCaptchaPresenterProvider)(
                context,
                gt,
                challenge,
              );
            } on LoginCaptchaException catch (error) {
              if (!mounted || generation != _generation || _finished) return;
              if (error.configurationUnavailable && step.canRefreshCaptcha) {
                refreshed = await _auth.refreshLoginCaptcha(widget.attempt);
                proof = null;
                continue;
              }
              throw AppFailure(
                AppFailureKind.protocol,
                error.configurationUnavailable
                    ? '验证码配置已失效，请重新发起登录或使用扫码登录'
                    : '人机验证加载失败，请检查网络后重试',
              );
            }
            if (proof == null || !mounted || generation != _generation) return;
            continue;
          case PasswordSmsLoginStage.smsSent:
            setState(() {
              _sent = true;
              _cooldown = 60;
            });
            _cooldownTimer?.cancel();
            _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (
              timer,
            ) {
              if (!mounted || _cooldown <= 1) {
                timer.cancel();
                if (mounted) setState(() => _cooldown = 0);
              } else {
                setState(() => _cooldown--);
              }
            });
            return;
          case PasswordSmsLoginStage.verifyPhone:
            _password.clear();
            _code.clear();
            setState(() {
              _maskedPhone = step.maskedPhone;
              _sent = false;
            });
            return;
          case PasswordSmsLoginStage.completed:
            _password.clear();
            _code.clear();
            _finished = true;
            TextInput.finishAutofillContext();
            Navigator.pop(context);
            return;
          case PasswordSmsLoginStage.ready:
            return;
        }
      }
      if (mounted) setState(() => _error = '验证未完成，请稍后重试');
    } on AppFailure catch (error) {
      if (mounted &&
          generation == _generation &&
          error.kind != AppFailureKind.cancelled) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _submit() {
    final attempt = widget.attempt;
    if (_maskedPhone != null) {
      unawaited(
        _run((_) => _auth.verifyLoginPhone(attempt, _code.text.trim())),
      );
    } else if (_sms) {
      unawaited(
        _run(
          (proof) =>
              _auth.loginWithSms(attempt, _code.text.trim(), proof: proof),
        ),
      );
    } else {
      unawaited(
        _run(
          (proof) => _auth.loginWithPassword(
            attempt,
            _username.text.trim(),
            _password.text,
            proof: proof,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _finished;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _finished = true;
          _generation++;
          _auth.cancelSignIn();
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(_maskedPhone == null ? '登录哔哩哔哩' : '验证绑定手机号'),
                  ),
                  IconButton(
                    tooltip: '关闭密码短信登录',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_maskedPhone == null) ...[
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('密码登录')),
                              ButtonSegment(value: true, label: Text('短信登录')),
                            ],
                            selected: {_sms},
                            onSelectionChanged: disabled
                                ? null
                                : (value) {
                                    setState(() {
                                      _sms = value.single;
                                      _error = null;
                                      _password.clear();
                                      _code.clear();
                                    });
                                  },
                          ),
                          const SizedBox(height: 20),
                          if (!_sms) ...[
                            TextField(
                              controller: _username,
                              enabled: !disabled,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: '手机号 / 邮箱',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              enabled: !disabled,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(
                                labelText: '密码',
                              ),
                              onSubmitted: disabled ? null : (_) => _submit(),
                            ),
                          ] else ...[
                            TextField(
                              controller: _country,
                              enabled: !disabled && !_sent,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '国家 / 地区代码',
                                prefixText: '+',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phone,
                              enabled: !disabled && !_sent,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: '手机号',
                              ),
                            ),
                          ],
                        ] else
                          Text(_maskedPhone!, textAlign: TextAlign.center),
                        if (_sms || _maskedPhone != null) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _code,
                            enabled: !disabled,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: '短信验证码',
                            ),
                          ),
                          TextButton(
                            onPressed: disabled || _cooldown > 0
                                ? null
                                : () {
                                    unawaited(
                                      _run(
                                        (proof) => _maskedPhone != null
                                            ? _auth.sendVerificationSms(
                                                widget.attempt,
                                                proof: proof,
                                              )
                                            : _auth.sendLoginSms(
                                                widget.attempt,
                                                _country.text.trim(),
                                                _phone.text.trim(),
                                                proof: proof,
                                              ),
                                      ),
                                    );
                                  },
                            child: Text(
                              _cooldown > 0 ? '${_cooldown}s 后重发' : '获取短信验证码',
                            ),
                          ),
                        ],
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed:
                              disabled ||
                                  ((_sms || _maskedPhone != null) && !_sent)
                              ? null
                              : _submit,
                          child: Text(_busy ? '正在处理…' : '登录'),
                        ),
                        if (_busy) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
