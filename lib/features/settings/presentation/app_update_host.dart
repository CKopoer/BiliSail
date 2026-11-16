import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/app_notice.dart';
import '../application/app_update_controller.dart';

/// Process-level prompt host: independent of the selected workspace tab.
final class AppUpdateHost extends ConsumerStatefulWidget {
  const AppUpdateHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AppUpdateHost> createState() => _AppUpdateHostState();
}

final class _AppUpdateHostState extends ConsumerState<AppUpdateHost> {
  bool _scheduled = false, _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(appUpdateControllerProvider.notifier).checkOnStartup(),
        );
      }
    });
  }

  void _schedulePrompt() {
    if (_scheduled || _showing) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_showPrompt());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openNotesLink(
    BuildContext context,
    Uri releaseUrl,
    String? href,
  ) async {
    final target = href == null ? null : Uri.tryParse(href);
    if (target == null) return;
    final uri = releaseUrl.resolveUri(target);
    if (!isAllowedWebLink(uri)) return;
    var opened = false;
    try {
      opened = await ref
          .read(webLinkOpenerProvider)(uri)
          .timeout(const Duration(seconds: 12));
    } on Exception {
      opened = false;
    }
    if (context.mounted && !opened) {
      showAppNotice(context, '无法打开浏览器，请稍后重试');
    }
  }

  Future<void> _showPrompt() async {
    final dialogContext = widget.navigatorKey.currentState?.overlay?.context;
    if (dialogContext == null || _showing) return;
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final release = controller.takePendingRelease();
    if (release == null) return;
    _showing = true;
    try {
      final openRelease = await showAppDialog<bool>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: Text('发现新版本 ${release.version.label}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (release.prerelease) ...[
                    const Text('这是预览版本，功能仍在完善中。'),
                    const SizedBox(height: 12),
                  ],
                  if (release.notes.trim().isEmpty)
                    const SelectableText('新版本已发布，可前往 Release 页面查看详情并下载。')
                  else
                    MarkdownBody(
                      data: release.notes,
                      selectable: true,
                      fitContent: false,
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(Theme.of(context))
                              .copyWith(
                                a: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                tableColumnWidth: const IntrinsicColumnWidth(),
                              ),
                      onTapLink: (_, href, _) =>
                          unawaited(_openNotesLink(context, release.url, href)),
                      imageBuilder: (uri, title, alt) {
                        final url = release.url.resolveUri(uri);
                        final fallback = Text(alt ?? title ?? '图片加载失败');
                        // Remote notes must not read local files or app assets.
                        if (!isAllowedWebLink(url)) return fallback;
                        return AppNetworkImage(
                          url: url.toString(),
                          fit: BoxFit.contain,
                          semanticLabel: alt ?? title,
                          errorBuilder: (_, _, _) => fallback,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('前往 Release'),
            ),
          ],
        ),
      );
      if (openRelease == true && mounted) {
        final opened = await controller.openRelease(release);
        if (!opened && dialogContext.mounted) {
          showAppNotice(dialogContext, '无法打开浏览器，请在关于页查看 GitHub 地址');
        }
      }
    } finally {
      _showing = false;
      if (mounted &&
          ref.read(appUpdateControllerProvider).pendingRelease != null) {
        _schedulePrompt();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appUpdateControllerProvider, (_, next) {
      if (next.pendingRelease != null) _schedulePrompt();
    });
    return widget.child;
  }
}
