import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../playback/application/playback_session.dart';
import '../application/video_actions_controller.dart';

class VideoDanmakuComposer extends ConsumerStatefulWidget {
  const VideoDanmakuComposer({
    super.key,
    required this.detail,
    required this.part,
    required this.onLogin,
  });
  final VideoDetail detail;
  final VideoPart part;
  final VoidCallback onLogin;
  @override
  ConsumerState<VideoDanmakuComposer> createState() =>
      _VideoDanmakuComposerState();
}

class _VideoDanmakuComposerState extends ConsumerState<VideoDanmakuComposer> {
  final _text = TextEditingController();
  int _mode = 1, _color = 0xffffff;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VideoDanmakuComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.part.cid != widget.part.cid ||
        oldWidget.detail.summary.id != widget.detail.summary.id) {
      _text.clear();
    }
  }

  Future<void> _send() async {
    final aid = widget.detail.aid;
    if (aid == null) return;
    final provider = videoActionsControllerProvider((
      id: widget.detail.summary.id,
      aid: aid,
    ));
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final session = ref.read(playbackSessionProvider);
    if (session.detail?.summary.id != widget.detail.summary.id ||
        session.part?.cid != widget.part.cid ||
        session.media == null) {
      return;
    }
    final sendingCid = widget.part.cid;
    final successful = await ref
        .read(provider.notifier)
        .send(
          widget.part.cid,
          text,
          session.snapshots.value.position,
          _mode,
          _color,
        );
    if (!mounted || widget.part.cid != sendingCid) return;
    if (successful && _text.text.trim() == text) _text.clear();
    final message = ref.read(provider).message;
    if (message != null) {
      showAppNotice(context, successful ? '弹幕已发送' : message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aid = widget.detail.aid;
    if (aid == null) return const SizedBox.shrink();
    final state = ref.watch(
      videoActionsControllerProvider((id: widget.detail.summary.id, aid: aid)),
    );
    return Container(
      height: (MediaQuery.textScalerOf(context).scale(12) + 20).clamp(
        36,
        double.infinity,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          PopupMenuButton<(int, int)>(
            tooltip: '发送弹幕样式',
            icon: const Icon(Icons.text_fields, size: 18),
            onSelected: (v) => setState(() {
              _mode = v.$1;
              _color = v.$2;
            }),
            itemBuilder: (_) => [
              for (final (mode, label) in const [
                (1, '滚动'),
                (5, '顶部'),
                (4, '底部'),
              ])
                PopupMenuItem(
                  value: (mode, _color),
                  child: Text('${_mode == mode ? '✓ ' : ''}$label'),
                ),
              for (final (color, label) in const [
                (0xffffff, '白色'),
                (0xff6699, '粉色'),
                (0xffd700, '金色'),
                (0x00a1d6, '蓝色'),
              ])
                PopupMenuItem(
                  value: (_mode, color),
                  child: Text('${_color == color ? '✓ ' : ''}$label'),
                ),
            ],
          ),
          Expanded(
            child: TextField(
              controller: _text,
              maxLength: 100,
              enabled: !state.busy,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: state.signedIn ? '发个友善的弹幕见证当下' : '登录后发送弹幕',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white60),
                counterText: '',
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          TextButton(
            onPressed: state.busy || state.uncertain.contains('send')
                ? null
                : _send,
            child: Text(
              state.busy ? '发送中' : '发送',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
