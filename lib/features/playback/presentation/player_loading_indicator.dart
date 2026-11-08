import 'dart:async';

import 'package:flutter/material.dart';

class PlayerLoadingIndicator extends StatefulWidget {
  const PlayerLoadingIndicator({
    super.key,
    required this.preparing,
    required this.recovering,
    required this.buffering,
  });

  final bool preparing, recovering, buffering;

  @override
  State<PlayerLoadingIndicator> createState() => _PlayerLoadingIndicatorState();
}

class _PlayerLoadingIndicatorState extends State<PlayerLoadingIndicator> {
  Timer? _timer;
  bool _showBuffering = false;
  bool get _waiting =>
      widget.buffering && !widget.preparing && !widget.recovering;

  @override
  void initState() {
    super.initState();
    _updateBuffering();
  }

  @override
  void didUpdateWidget(PlayerLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBuffering();
  }

  void _updateBuffering() {
    if (!_waiting) {
      _timer?.cancel();
      _timer = null;
      _showBuffering = false;
    } else if (_timer == null && !_showBuffering) {
      // Native cache-pause can pulse during an otherwise immediate seek.
      _timer = Timer(const Duration(milliseconds: 300), () {
        _timer = null;
        if (mounted && _waiting) setState(() => _showBuffering = true);
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
    if (!widget.preparing && !widget.recovering && !_showBuffering) {
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
                  : '网络缓冲中…',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
