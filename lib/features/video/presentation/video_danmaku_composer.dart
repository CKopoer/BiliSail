import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/danmaku_send_style_button.dart';
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
    final generation = session.sourceGeneration;
    final position = session.snapshots.value.position;
    final style = session.danmakuSendStyle.value;
    final successful = await ref
        .read(provider.notifier)
        .send(
          widget.part.cid,
          text,
          position,
          style.mode,
          style.color,
          onSent: (id) => session.showSentDanmaku(
            cid: sendingCid,
            generation: generation,
            id: id,
            text: text,
            position: position,
            mode: style.mode,
            color: style.color,
          ),
        );
    if (!mounted ||
        widget.part.cid != sendingCid ||
        session.sourceGeneration != generation) {
      return;
    }
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
    final session = ref.watch(playbackSessionProvider);
    return Container(
      height: (MediaQuery.textScalerOf(context).scale(12) + 20).clamp(
        44,
        double.infinity,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          DanmakuSendStyleButton(
            style: session.danmakuSendStyle,
            onChanged: session.setDanmakuSendStyle,
            enabled: !state.busy,
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
