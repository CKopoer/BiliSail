import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/dynamic/application/dynamic_composer_controller.dart';
import '../../features/dynamic/domain/dynamic_composer_repository.dart';
import 'app_dialog.dart';
import 'dynamic_compose_editor.dart';
export 'dynamic_compose_editor.dart' show DynamicComposeDialog;
import 'app_notice.dart';
import '../../features/dynamic/application/dynamic_content_state.dart';
import 'dynamic_post_menu.dart';

class DynamicComposeToolbar extends ConsumerWidget {
  const DynamicComposeToolbar({
    super.key,
    required this.child,
    this.topic,
    this.onPublished,
    this.onLogin,
    this.label = '发布动态',
    this.enabled = true,
    this.visible = true,
  });

  final Widget child;
  final DynamicComposeTopic? topic;
  final Future<void> Function()? onPublished;
  final VoidCallback? onLogin;
  final String label;
  final bool enabled;
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final extraTextWidth =
          (MediaQuery.textScalerOf(context).scale(13) - 13) * 8;
      return Row(
        children: [
          Expanded(child: child),
          if (ref.watch(dynamicContentProvider).hiddenAuthors.isNotEmpty)
            IconButton(
              tooltip: '临时屏蔽的UP主',
              onPressed: () => showTemporaryDynamicBlocks(context),
              icon: const Icon(Icons.visibility_off_outlined),
            ),
          if (visible)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: DynamicComposeButton(
                compact: constraints.maxWidth < 480 + extraTextWidth,
                topic: topic,
                onPublished: onPublished,
                onLogin: onLogin,
                label: label,
                enabled: enabled,
              ),
            ),
        ],
      );
    },
  );
}

class DynamicComposeButton extends ConsumerWidget {
  const DynamicComposeButton({
    super.key,
    this.topic,
    this.onPublished,
    this.onLogin,
    this.label = '发布动态',
    this.enabled = true,
    this.compact = false,
  });
  final DynamicComposeTopic? topic;
  final Future<void> Function()? onPublished;
  final VoidCallback? onLogin;
  final String label;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: .07),
      disabledBackgroundColor: theme.colorScheme.surfaceContainerLow,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final icon = Icon(
      topic == null ? Icons.edit_outlined : Icons.tag,
      size: 20,
    );
    final VoidCallback? onPressed = !enabled
        ? null
        : () async {
            if (!ref.read(authControllerProvider).isSignedIn) {
              if (onLogin != null) {
                onLogin!();
              } else {
                showAppNotice(context, '请先登录后发布动态');
              }
              return;
            }
            final controller = ref.read(dynamicComposerProvider.notifier);
            if (topic != null) {
              controller.setTopic(topic);
            }
            final success = await showAppDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const DynamicComposeDialog(),
            );
            if (success == true && context.mounted) {
              showAppNotice(context, '动态已提交');
              await onPublished?.call();
            }
          };
    if (compact) {
      return IconButton(
        key: const ValueKey('dynamic-compose'),
        tooltip: label,
        style: style,
        icon: icon,
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      key: const ValueKey('dynamic-compose'),
      style: style,
      icon: icon,
      label: Text(label, maxLines: 1),
      onPressed: onPressed,
    );
  }
}
