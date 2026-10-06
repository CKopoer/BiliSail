import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../application/auth_controller.dart';
import '../domain/auth_repository.dart';
import 'web_login_presenter.dart';

class AccountDialog extends ConsumerStatefulWidget {
  const AccountDialog({super.key, this.onOpenUser});
  final ValueChanged<UserId>? onOpenUser;
  @override
  ConsumerState<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends ConsumerState<AccountDialog>
    with WidgetsBindingObserver {
  late final AuthRepository _repository;
  bool _openingWeb = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(authRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _repository.current.status != AuthStatus.waitingWeb) {
      // Reading an SMS in another app is allowed while the official page waits.
      // Authentication requests and QR polling still cancel on backgrounding.
      _generation++;
      _repository.cancelSignIn();
      if (_openingWeb) setState(() => _openingWeb = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _repository.cancelSignIn();
    super.dispose();
  }

  Future<void> _openWebLogin() async {
    if (_openingWeb) return;
    final controller = ref.read(authControllerProvider.notifier);
    final attempt = controller.beginWebLogin();
    if (attempt == null) return;
    final generation = ++_generation;
    final presenter = ref.read(webLoginPresenterProvider);
    setState(() => _openingWeb = true);
    try {
      final cookies = await presenter(context);
      if (!mounted || generation != _generation) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden) {
        return;
      }
      if (cookies != null) await controller.completeWebLogin(attempt, cookies);
    } finally {
      if (mounted && generation == _generation) {
        if (_repository.current.status == AuthStatus.waitingWeb) {
          controller.cancelSignIn();
        }
        setState(() => _openingWeb = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _generation++;
          controller.cancelSignIn();
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        auth.isSignedIn ? '我的账号' : '登录哔哩哔哩',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (auth.isSignedIn) ...[
                        Center(
                          child: NetworkAvatar(
                            url: auth.avatarUrl,
                            name: auth.userName ?? '',
                            radius: 30,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          auth.userName ?? '已登录',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (UserId.tryParse(auth.mid) case final UserId id)
                          if (widget.onOpenUser != null)
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onOpenUser?.call(id);
                              },
                              child: const Text('个人主页'),
                            ),
                        TextButton(
                          onPressed: controller.signOut,
                          child: const Text('退出登录'),
                        ),
                      ] else ...[
                        if (auth.qrUri case final Uri uri) ...[
                          LayoutBuilder(
                            builder: (_, constraints) => Center(
                              child: ColoredBox(
                                color: Colors.white,
                                child: QrImageView(
                                  data: uri.toString(),
                                  size: min(220, constraints.maxWidth),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            auth.status == AuthStatus.waitingConfirm
                                ? '已扫描，请在手机上确认'
                                : '使用哔哩哔哩手机客户端扫一扫',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: auth.isBusy
                                ? null
                                : controller.cancelSignIn,
                            child: const Text('切换登录方式'),
                          ),
                        ] else if (auth.status == AuthStatus.creatingQr ||
                            _openingWeb) ...[
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          if (_openingWeb)
                            const Text(
                              '正在等待官网登录完成',
                              textAlign: TextAlign.center,
                            ),
                        ] else ...[
                          const Icon(Icons.qr_code_2_rounded, size: 80),
                          const SizedBox(height: 16),
                          const Text(
                            '登录后可请求账号可用的画质和字幕。\n也可以继续以游客身份观看。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: auth.isBusy ? null : controller.signIn,
                            child: const Text('获取登录二维码'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: auth.isBusy
                                ? null
                                : () => unawaited(_openWebLogin()),
                            child: const Text('密码 / 短信登录'),
                          ),
                        ],
                      ],
                      if (auth.message case final String message)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(message, textAlign: TextAlign.center),
                        ),
                    ],
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
