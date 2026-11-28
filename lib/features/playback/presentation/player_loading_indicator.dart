import 'dart:async';

import 'package:material_ui/material_ui.dart';

class PlayerLoadingIndicator extends StatefulWidget {
  const PlayerLoadingIndicator({
    super.key,
    required this.preparing,
    this.deferPreparation = false,
    required this.recovering,
    required this.buffering,
  });

  final bool preparing, recovering, buffering;
  final bool deferPreparation;

  @override
  State<PlayerLoadingIndicator> createState() => _PlayerLoadingIndicatorState();
}

class _PlayerLoadingIndicatorState extends State<PlayerLoadingIndicator> {
  Timer? _timer;
  bool _showWait = false;
  bool get _waiting =>
      !widget.recovering &&
      (widget.preparing ? widget.deferPreparation : widget.buffering);

  @override
  void initState() {
    super.initState();
    _updateWaiting();
  }

  @override
  void didUpdateWidget(PlayerLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateWaiting();
  }

  void _updateWaiting() {
    if (!_waiting) {
      _timer?.cancel();
      _timer = null;
      _showWait = false;
    } else if (_timer == null && !_showWait) {
      // Native cache-pause can pulse during an otherwise immediate seek.
      _timer = Timer(const Duration(milliseconds: 300), () {
        _timer = null;
        if (mounted && _waiting) setState(() => _showWait = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.preparing && !widget.deferPreparation) &&
        !widget.recovering &&
        !_showWait) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.recovering
                  ? '正在恢复播放…'
                  : widget.preparing
                  ? '正在准备音视频…'
                  : '播放缓冲中…',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
