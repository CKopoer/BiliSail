import '../../../domain/user.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/network_avatar.dart';
import '../application/auth_controller.dart';
import '../application/account_overview_controller.dart';
import 'account_menu.dart';
import 'account_dialog.dart';

export 'account_dialog.dart';

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
