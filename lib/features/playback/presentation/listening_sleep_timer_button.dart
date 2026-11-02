import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/app_dialog.dart';
import '../application/playback_session.dart';

class ListeningSleepTimerButton extends StatefulWidget {
  const ListeningSleepTimerButton({
    super.key,
    required this.session,
    required this.compact,
  });

  final PlaybackSession session;
  final bool compact;

  @override
  State<ListeningSleepTimerButton> createState() =>
      _ListeningSleepTimerButtonState();
}

class _ListeningSleepTimerButtonState extends State<ListeningSleepTimerButton>
    with WidgetsBindingObserver {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.sleepTimer.addListener(_changed);
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant ListeningSleepTimerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.sleepTimer.removeListener(_changed);
      widget.session.sleepTimer.addListener(_changed);
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    _refresh?.cancel();
    _refresh = widget.session.sleepTimer.remaining == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            widget.session.sleepTimer.checkDeadline();
            if (mounted) setState(() {});
          });
  }

  void _changed() {
    _scheduleRefresh();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.sleepTimer.checkDeadline();
      _changed();
    } else {
      _refresh?.cancel();
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    widget.session.sleepTimer.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _showOptions() async {
    final session = widget.session;
    final duration = await showAppDialog<Duration>(
      context: context,
      builder: (_) => _SleepTimerDialog(session: session),
    );
    if (!mounted || duration == null) return;
    if (duration == Duration.zero) {
      session.sleepTimer.cancel();
    } else {
      session.startSleepTimer(duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timer = widget.session.sleepTimer;
    final remaining = timer.remaining;
    final text = remaining == null ? '定时关闭' : _formatRemaining(remaining);
    final tooltip = remaining != null
        ? '定时关闭：$text 后暂停'
        : timer.elapsed
        ? '定时已结束，播放已暂停'
        : '定时关闭';
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    final icon = Icon(
      remaining == null ? Icons.timer_outlined : Icons.timer_rounded,
      size: 20,
    );
    return Tooltip(
      message: tooltip,
      child: remaining == null && widget.compact || largeText
          ? IconButton(
              key: const ValueKey('listening-sleep-timer'),
              onPressed: _showOptions,
              color: remaining == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
              icon: icon,
            )
          : TextButton.icon(
              key: const ValueKey('listening-sleep-timer'),
              onPressed: _showOptions,
              style: remaining == null
                  ? null
                  : TextButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      foregroundColor: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
                    ),
              icon: icon,
              label: Text(text),
            ),
    );
  }
}

String _formatRemaining(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _SleepTimerDialog extends StatefulWidget {
  const _SleepTimerDialog({required this.session});
  final PlaybackSession session;

  @override
  State<_SleepTimerDialog> createState() => _SleepTimerDialogState();
}

class _SleepTimerDialogState extends State<_SleepTimerDialog> {
  final _minutes = TextEditingController();
  int? _selected = 30;
  bool _custom = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _confirm() {
    final minutes = _custom ? int.tryParse(_minutes.text) : _selected;
    if (minutes == null || minutes < 1 || minutes > 180) {
      setState(() => _error = '请输入 1–180 分钟');
      return;
    }
    Navigator.of(context).pop(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.bedtime_outlined),
    title: const Text('定时关闭'),
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListenableBuilder(
            listenable: widget.session.sleepTimer,
            builder: (context, _) => Text(
              widget.session.sleepTimer.elapsed
                  ? '定时已结束，播放已暂停。'
                  : widget.session.sleepTimer.remaining != null
                  ? '已开启定时，重新设置将从现在开始计时。'
                  : '到时暂停播放，安心听一会儿。',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final minutes in [15, 30, 45, 60, 90])
                ChoiceChip(
                  label: Text('$minutes 分钟'),
                  selected: !_custom && _selected == minutes,
                  onSelected: (_) => setState(() {
                    _custom = false;
                    _selected = minutes;
                    _error = null;
                  }),
                ),
              ChoiceChip(
                label: const Text('自定义'),
                selected: _custom,
                onSelected: (_) => setState(() => _custom = true),
              ),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: InputDecoration(
                labelText: '时长（分钟）',
                hintText: '1–180',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _confirm(),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '连续播放、暂停和缓冲时继续计时。退出听视频或退出应用后取消。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      if (widget.session.sleepTimer.remaining != null)
        TextButton(
          onPressed: () => Navigator.of(context).pop(Duration.zero),
          child: const Text('取消定时'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('返回'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('开始计时')),
    ],
  );
}
