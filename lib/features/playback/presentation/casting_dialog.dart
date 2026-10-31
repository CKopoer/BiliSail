import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_dialog.dart';
import '../application/casting_controller.dart';
import '../application/playback_session.dart';
import '../domain/casting.dart';

Future<void> showCastingDialog(BuildContext context, PlaybackSession session) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => _CastingHost(session: session),
    );

class _CastingHost extends ConsumerStatefulWidget {
  const _CastingHost({required this.session});
  final PlaybackSession session;
  @override
  ConsumerState<_CastingHost> createState() => _CastingHostState();
}

class _CastingHostState extends ConsumerState<_CastingHost> {
  CastingController? _controller;
  @override
  void initState() {
    super.initState();
    final session = widget.session;
    final request = castRequestFor(session);
    if (request == null) return;
    final generation = session.sourceGeneration;
    final epoch = session.sessionEpoch();
    _controller = CastingController(
      request: request,
      title: session.title,
      mediaRepository: ref.read(castMediaRepositoryProvider),
      deviceRepository: ref.read(castDeviceRepositoryFactoryProvider)(),
      source: session,
      isCurrent: () =>
          session.sourceGeneration == generation &&
          session.sessionEpoch() == epoch &&
          castRequestFor(session) != null,
      pauseLocal: session.pause,
      trackLifetime: ref.read(castLifetimeTrackerProvider),
    );
    unawaited(_controller!.search());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_controller) {
    final controller? => CastingDialog(controller: controller),
    null => AlertDialog(
      title: const Text('投屏'),
      content: const Text('当前内容暂不支持投屏'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  };
}

class CastingDialog extends StatelessWidget {
  const CastingDialog({super.key, required this.controller});
  final CastingController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final devices = controller.devices;
      final selected = controller.selected;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.cast_rounded, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '投屏',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '重新搜索',
                      onPressed: controller.searching || controller.invalidated
                          ? null
                          : controller.search,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (controller.searching || controller.busy)
                const LinearProgressIndicator(minHeight: 2),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '请让电视与本机连接同一局域网，并打开电视的 DLNA 投屏功能。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (selected != null) ...[
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  selected.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  controller.transport ==
                                          CastingTransport.paused
                                      ? '投屏已暂停'
                                      : '正在投屏',
                                  style: TextStyle(color: colors.primary),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed:
                                          controller.busy ||
                                              controller.invalidated
                                          ? null
                                          : () => controller.control(
                                              controller.transport ==
                                                      CastingTransport.playing
                                                  ? CastCommand.pause
                                                  : CastCommand.play,
                                            ),
                                      icon: Icon(
                                        controller.transport ==
                                                CastingTransport.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                      label: Text(
                                        controller.transport ==
                                                CastingTransport.playing
                                            ? '暂停'
                                            : '继续',
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed:
                                          controller.busy ||
                                              controller.invalidated
                                          ? null
                                          : () => controller.control(
                                              CastCommand.stop,
                                            ),
                                      icon: const Icon(Icons.stop_rounded),
                                      label: const Text('停止投屏'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        controller.searching ? '正在搜索设备…' : '可用设备',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (devices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            controller.searching
                                ? '正在寻找附近的电视或播放器'
                                : '未发现设备，可检查电视投屏开关后重新搜索',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      for (final device in devices)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.tv_rounded,
                              color: selected?.id == device.id
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            title: Text(device.name),
                            subtitle: Text(device.controlUri.host),
                            trailing: selected?.id == device.id
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: colors.primary,
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            enabled:
                                !controller.busy && !controller.invalidated,
                            onTap: () => unawaited(controller.connect(device)),
                          ),
                        ),
                      if (controller.message case final message?)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            message,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '电视从头播放；连接成功后本机暂停。关闭面板后电视继续播放，可使用电视遥控器控制。',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
