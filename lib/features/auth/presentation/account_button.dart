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
    return IconButton(
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
          showGeneralDialog<void>(
            context: context,
            barrierDismissible: true,
            barrierLabel: MaterialLocalizations.of(context)
                .modalBarrierDismissLabel,
            barrierColor: Colors.black38,
            transitionDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            pageBuilder: (_, _, _) =>
                AccountMenu(onOpenUser: onOpenUser, onNavigate: onNavigate),
            transitionBuilder: (_, animation, _, child) => Align(
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      animation.drive(CurveTween(curve: Curves.easeOutCubic)),
                    ),
                child: child,
              ),
            ),
          );
          return;
        }
        showDialog<void>(
          context: context,
          builder: (_) => AccountDialog(onOpenUser: onOpenUser),
        );
      },
    );
  }
}
