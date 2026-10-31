import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/danmaku_composer_draft.dart';
import '../../../shared/ui/danmaku_send_style_button.dart';
import '../../playback/application/playback_session.dart';
import '../application/pgc_danmaku_controller.dart';
import '../domain/pgc_danmaku_repository.dart';
import '../domain/pgc_repository.dart';

final class PgcDanmakuComposer extends ConsumerStatefulWidget {
  const PgcDanmakuComposer({
    super.key,
    required this.episode,
    required this.onLogin,
  });
  final PgcEpisode episode;
  final VoidCallback onLogin;

  @override
  ConsumerState<PgcDanmakuComposer> createState() => _PgcDanmakuComposerState();
}

final class _PgcDanmakuComposerState extends ConsumerState<PgcDanmakuComposer> {
  final _localText = TextEditingController();
  late TextEditingController _text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _text = DanmakuComposerDraft.maybeOf(context) ?? _localText;
  }

  PgcDanmakuTarget get _target => (
    episodeId: widget.episode.episodeId,
    video: VideoId(widget.episode.bvid ?? ''),
    cid: widget.episode.cid ?? '',
  );

  @override
  void dispose() {
    _localText.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PgcDanmakuComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(_text, _localText) &&
        (oldWidget.episode.id != widget.episode.id ||
            oldWidget.episode.cid != widget.episode.cid ||
            oldWidget.episode.bvid != widget.episode.bvid)) {
      _text.clear();
    }
  }

  Future<void> _send() async {
    final target = _target;
    final provider = pgcDanmakuControllerProvider(target);
    if (!ref.read(provider).signedIn) {
      widget.onLogin();
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final style = ref.read(playbackSessionProvider).danmakuSendStyle.value;
    final clearSentDraft = DanmakuComposerDraft.clearSentOf(context);
    final success = await ref
        .read(provider.notifier)
        .send(text, mode: style.mode, color: style.color);
    if (success) clearSentDraft?.call(text);
    if (!mounted || _target != target) return;
    if (success && _text.text.trim() == text) _text.clear();
    final message = ref.read(provider).message;
    if (message != null) showAppNotice(context, message);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.episode.playable) return const SizedBox.shrink();
    final state = ref.watch(pgcDanmakuControllerProvider(_target));
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
            onPressed: state.busy || state.uncertain ? null : _send,
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
