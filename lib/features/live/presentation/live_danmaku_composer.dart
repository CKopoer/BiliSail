import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_dialog.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/danmaku_composer_draft.dart';
import '../../../shared/ui/emoticon_picker_dialog.dart';
import '../application/live_danmaku_controller.dart';
import '../domain/live_danmaku_repository.dart';
import '../domain/live_room.dart';

final class LiveDanmakuComposer extends ConsumerStatefulWidget {
  const LiveDanmakuComposer({
    super.key,
    required this.roomId,
    required this.onLogin,
    this.playerStyle = false,
    this.compact = false,
  });

  /// Requested ID retains the same scoped controller for short/canonical IDs.
  final RoomId roomId;
  final VoidCallback onLogin;
  final bool playerStyle;
  final bool compact;

  @override
  ConsumerState<LiveDanmakuComposer> createState() =>
      _LiveDanmakuComposerState();
}

final class _LiveDanmakuComposerState
    extends ConsumerState<LiveDanmakuComposer> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _syncText(String text) {
    if (_text.text == text) return;
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _send() async {
    if (!WorkspaceActivity.isActive(context)) return;
    final room = widget.roomId;
    final provider = liveDanmakuControllerProvider(room);
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    await ref.read(provider.notifier).send();
    if (!mounted || widget.roomId != room) return;
    final message = ref.read(provider).message;
    if (message != null) showAppNotice(context, message);
  }

  Future<void> _emoticons() async {
    if (!WorkspaceActivity.isActive(context)) return;
    final provider = liveDanmakuControllerProvider(widget.roomId);
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    final container = ProviderScope.containerOf(context);
    unawaited(ref.read(provider.notifier).loadEmoticons());
    await showAppDialog<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _EmoticonDialog(roomId: widget.roomId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = liveDanmakuControllerProvider(widget.roomId);
    final state = ref.watch(provider);
    ref.listen(
      provider.select((state) => state.draft),
      (_, draft) => _syncText(draft),
    );
    _syncText(state.draft);
    final controller = ref.read(provider.notifier);
    final player = widget.playerStyle;
    final muted = player
        ? Colors.white60
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final colors = Theme.of(context).colorScheme;
    final compact = widget.compact && !player;
    final compactTarget = compact ? MaterialTapTargetSize.shrinkWrap : null;
    final background = player
        ? Colors.white.withValues(alpha: .16)
        : colors.surfaceContainerHigh;
    final row = Container(
      constraints: BoxConstraints(
        minHeight: (MediaQuery.textScalerOf(context).scale(12) + 20).clamp(
          36,
          double.infinity,
        ),
      ),
      decoration: BoxDecoration(
        color: compact ? null : background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: compact ? colors.surfaceContainerLow : null,
                borderRadius: BorderRadius.circular(10),
                border: compact
                    ? Border.all(color: colors.outlineVariant)
                    : null,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '直播表情包',
                    style: IconButton.styleFrom(tapTargetSize: compactTarget),
                    onPressed: state.busy ? null : _emoticons,
                    icon: Icon(
                      Icons.emoji_emotions_outlined,
                      size: 18,
                      color: muted,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  if (state.selected?.imageUrl case final url?)
                    AppNetworkImage(
                      url: url.toString(),
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  Expanded(
                    child: TextField(
                      autofocus: DanmakuComposerDraft.autofocusOf(context),
                      key: ValueKey(
                        player
                            ? 'live-player-danmaku-input'
                            : 'live-sidebar-danmaku-input',
                      ),
                      controller: _text,
                      maxLength: 100,
                      enabled:
                          !state.busy && (state.canSend || !state.signedIn),
                      style: TextStyle(
                        fontSize: 12,
                        color: player ? Colors.white : null,
                      ),
                      onChanged: controller.setDraft,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: !state.signedIn
                            ? '登录后发送弹幕'
                            : !state.canSend
                            ? '主播尚未开播'
                            : '发个友善的弹幕',
                        hintStyle: TextStyle(fontSize: 12, color: muted),
                        counterText: '',
                        isDense: true,
                        border: InputBorder.none,
                        filled: compact ? false : null,
                        enabledBorder: compact ? InputBorder.none : null,
                        focusedBorder: compact ? InputBorder.none : null,
                        disabledBorder: compact ? InputBorder.none : null,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: compact ? 7 : 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed:
                state.busy ||
                    state.uncertain ||
                    (state.signedIn &&
                        (!state.canSend || state.draft.trim().isEmpty))
                ? null
                : _send,
            style: TextButton.styleFrom(
              minimumSize: Size(compact ? 36 : 48, 36),
              tapTargetSize: compactTarget,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              state.busy ? '发送中' : '发送',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (state.uncertain && !compact)
            TextButton(
              onPressed: controller.acknowledgeUncertain,
              child: const Text('已核对', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
    if (player) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (compact && state.uncertain)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.acknowledgeUncertain,
              child: const Text('已核对'),
            ),
          ),
        if (state.message case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

final class _EmoticonDialog extends ConsumerWidget {
  const _EmoticonDialog({required this.roomId});
  final RoomId roomId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveDanmakuControllerProvider(roomId));
    final controller = ref.read(liveDanmakuControllerProvider(roomId).notifier);
    return EmoticonPickerDialog(
      title: '直播表情包',
      loading: state.emoticonsLoading,
      message: state.emoticonsMessage,
      emptyMessage: '这个房间暂无可用表情包',
      hint: '选择后点击发送；锁定表情按账号权限显示',
      onRetry: controller.loadEmoticons,
      packageNames: [for (final package in state.packages) package.name],
      packageBuilder: (context, index) => SingleChildScrollView(
        key: PageStorageKey('live-emoticon-package-$index'),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final item in state.packages[index].items)
              _emoticon(context, state, controller, item),
          ],
        ),
      ),
    );
  }

  Widget _emoticon(
    BuildContext context,
    LiveDanmakuState state,
    LiveDanmakuController controller,
    LiveEmoticon item,
  ) => Tooltip(
    message: item.allowed
        ? item.text
        : '${item.text} · ${item.unlockHint.isEmpty ? '尚未解锁' : item.unlockHint}',
    child: SizedBox(
      width: 64,
      child: InkWell(
        key: ValueKey(
          'live-emoticon-${item.unique.isEmpty ? item.text : item.unique}',
        ),
        onTap: state.busy || !state.canSend || !item.allowed
            ? null
            : () {
                controller.chooseEmoticon(item);
                Navigator.pop(context);
              },
        child: Opacity(
          opacity: item.allowed ? 1 : .45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 42,
                child: item.imageUrl == null
                    ? const Icon(Icons.emoji_emotions_outlined)
                    : AppNetworkImage(
                        url: item.imageUrl.toString(),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.emoji_emotions_outlined),
                      ),
              ),
              if (!item.allowed) const Icon(Icons.lock_outline, size: 12),
              Text(
                item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
