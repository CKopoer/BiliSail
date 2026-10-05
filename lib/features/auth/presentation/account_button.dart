import '../../../domain/user.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/ui/network_avatar.dart';
import '../application/auth_controller.dart';
import '../domain/auth_repository.dart';
import '../application/account_overview_controller.dart';
import 'account_menu.dart';

class AccountButton extends ConsumerWidget {
  const AccountButton({super.key, this.onOpenUser, this.onNavigate});
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final indicator = auth.isSignedIn
        ? ref.watch(accountMessageIndicatorProvider)
        : const AccountMessageIndicator();
    final count = indicator.count;
    return Builder(
      builder: (buttonContext) => IconButton(
        tooltip: auth.isSignedIn ? '我的账号' : '登录',
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: NetworkAvatar(
            url: auth.avatarUrl,
            name: auth.userName ?? '',
            radius: 12,
          ),
        ),
        onPressed: () {
          if (auth.isSignedIn) {
            indicator.refresh?.call();
            final box = buttonContext.findRenderObject() as RenderBox?;
            final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
            final size = MediaQuery.sizeOf(context);
            showDialog<void>(
              context: context,
              barrierColor: Colors.transparent,
              builder: (_) => AccountMenu(
                top: (position.dy + (box?.size.height ?? 40) + 8).clamp(
                  12,
                  size.height / 2,
                ),
                right: (size.width - position.dx - (box?.size.width ?? 40))
                    .clamp(12, (size.width - 292).clamp(12, double.infinity)),
                onOpenUser: onOpenUser,
                onNavigate: onNavigate,
              ),
            );
            return;
          }
          showDialog<void>(
            context: context,
            builder: (_) => AccountDialog(onOpenUser: onOpenUser),
          );
        },
      ),
    );
  }
}

class AccountDialog extends ConsumerStatefulWidget {
  const AccountDialog({super.key, this.onOpenUser});
  final ValueChanged<UserId>? onOpenUser;
  @override
  ConsumerState<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends ConsumerState<AccountDialog>
    with WidgetsBindingObserver {
  late final AuthRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(authRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _repository.cancelSignIn();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repository.cancelSignIn();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.cancelSignIn();
      },
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(auth.isSignedIn ? '我的账号' : '扫码登录')),
            IconButton(
              tooltip: '关闭',
              onPressed: () {
                controller.cancelSignIn();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (auth.isSignedIn) ...[
                NetworkAvatar(
                  url: auth.avatarUrl,
                  name: auth.userName ?? '',
                  radius: 30,
                ),
                const SizedBox(height: 18),
                Text(auth.userName ?? '已登录'),
              ] else if (auth.qrUri case final Uri uri) ...[
                DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.white),
                  child: QrImageView(data: uri.toString(), size: 220),
                ),
                const SizedBox(height: 16),
                Text(
                  auth.status == AuthStatus.waitingConfirm
                      ? '已扫描，请在手机上确认'
                      : '使用哔哩哔哩手机客户端扫一扫',
                ),
              ] else if (auth.status == AuthStatus.creatingQr) ...[
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              ] else ...[
                const Icon(Icons.qr_code_2_rounded, size: 80),
                const SizedBox(height: 16),
                const Text(
                  '登录后可请求账号可用的画质和字幕。\n也可以继续以游客身份观看。',
                  textAlign: TextAlign.center,
                ),
              ],
              if (auth.message case final String message)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(message, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
        actions: [
          if (auth.isSignedIn &&
              UserId.tryParse(auth.mid) != null &&
              widget.onOpenUser != null)
            FilledButton(
              onPressed: () {
                final id = UserId.tryParse(auth.mid);
                if (id == null) return;
                Navigator.pop(context);
                widget.onOpenUser?.call(id);
              },
              child: const Text('个人主页'),
            ),
          if (auth.isSignedIn)
            TextButton(
              onPressed: () async {
                await controller.signOut();
              },
              child: const Text('退出登录'),
            )
          else if (auth.status != AuthStatus.creatingQr && auth.qrUri == null)
            FilledButton(
              onPressed: controller.signIn,
              child: const Text('获取登录二维码'),
            ),
        ],
      ),
    );
  }
}
