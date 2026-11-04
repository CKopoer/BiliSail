import 'package:flutter/material.dart';

import '../../core/presentation/workspace_activity.dart';
import '../../domain/video.dart';
import '../../features/video/domain/video_card_interactions.dart';
import 'video_card_interaction_scope.dart';

Future<T?> showVideoCardMenuSheet<T>(
  BuildContext context,
  List<({T value, IconData icon, String label})> actions,
) {
  var selecting = false;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                leading: Icon(action.icon),
                title: Text(action.label),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () {
                  if (selecting) return;
                  selecting = true;
                  Navigator.of(context).pop(action.value);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Horizontal cards share the narrow-screen watch-later menu with grid cards.
Future<void> showVideoCardWatchLaterMenu(
  BuildContext context,
  VideoId id, {
  bool Function()? isCurrent,
}) async {
  if (!id.isValid ||
      MediaQuery.sizeOf(context).width >= 600 ||
      !WorkspaceActivity.isActive(context)) {
    return;
  }
  final scope = VideoCardInteractionScope.maybeOf(context);
  final interactions = scope?.interactions;
  if (scope == null || interactions is! VideoCardWatchLaterToggle) return;
  final toggle = interactions as VideoCardWatchLaterToggle;
  bool current() =>
      context.mounted &&
      (isCurrent?.call() ?? true) &&
      WorkspaceActivity.isActive(context) &&
      VideoCardInteractionScope.maybeOf(context)?.interactions == interactions;
  final loaded = await toggle.refreshWatchLater();
  if (!context.mounted || !current() || toggle.isWatchLaterBusy(id)) return;
  if (!loaded) {
    scope.onNotice(context, '无法读取稍后再看状态，请稍后重试');
    return;
  }
  final removing = toggle.isAdded(id);
  final selected = await showVideoCardMenuSheet(context, [
    (
      value: true,
      icon: Icons.watch_later_outlined,
      label: removing ? '取消稍后再看' : '稍后再看',
    ),
  ]);
  if (selected != true ||
      !context.mounted ||
      !current() ||
      removing != toggle.isAdded(id)) {
    return;
  }
  final result = removing
      ? await toggle.removeWatchLater(id)
      : await toggle.addWatchLater(id);
  if (!context.mounted || !current()) return;
  final message = watchLaterResultMessage(result, removing: removing);
  if (message != null) scope.onNotice(context, message);
}

String? watchLaterResultMessage(
  WatchLaterResult result, {
  bool removing = false,
}) => switch (result) {
  WatchLaterResult.added || WatchLaterResult.alreadyAdded => '已加入稍后再看',
  WatchLaterResult.removed => '已取消稍后再看',
  WatchLaterResult.signIn => '请先登录后再操作稍后再看',
  WatchLaterResult.uncertain => '操作结果暂时无法确认，请在稍后再看列表核对',
  WatchLaterResult.failed => removing ? '取消失败，请稍后重试' : '添加失败，请稍后重试',
  WatchLaterResult.busy || WatchLaterResult.cancelled => null,
};
