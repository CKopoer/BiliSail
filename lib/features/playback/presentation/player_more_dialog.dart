import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/playback_rates.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../settings/domain/app_settings.dart';
import '../application/playback_session.dart';
import '../domain/content_playback.dart';
import '../domain/playback_repository.dart';
import '../application/casting_controller.dart';
import 'casting_dialog.dart';
import 'live_stream_picker.dart';
import 'playback_snapshot_builder.dart';
import 'player_control_labels.dart';

class PlayerMoreDialog extends StatelessWidget {
  const PlayerMoreDialog({
    super.key,
    required this.session,
    required this.settings,
    required this.commands,
    required this.navigation,
    required this.onNavigate,
    required this.onSettings,
    required this.onToggleComments,
    required this.onFullScreen,
    required this.fullScreen,
    this.onCompose,
  });

  final PlaybackSession session;
  final ValueListenable<AppSettings> settings;
  final ValueListenable<PlaybackPageCommands?> commands;
  final ValueListenable<PlaybackNavigation?> navigation;
  final ValueChanged<VoidCallback> onNavigate;
  final Future<void> Function(int) onSettings;
  final VoidCallback onToggleComments;
  final VoidCallback onFullScreen;
  final bool fullScreen;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      key: const ValueKey('player-more-dialog'),
      alignment: narrow ? Alignment.bottomCenter : Alignment.centerRight,
      insetPadding: EdgeInsets.all(narrow ? 12 : 24),
      constraints: BoxConstraints(
        maxWidth: narrow ? 560 : 400,
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: Listenable.merge([session, settings, commands, navigation]),
        builder: (context, _) => PlaybackSnapshotBuilder(
          snapshots: session.snapshots,
          select: (snapshot) =>
              (snapshot.rate, snapshot.volume, snapshot.desiredPlaying),
          builder: (context, snapshot) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '更多播放选项',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭更多播放选项',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('player-more-scroll'),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(children: _tools(context, snapshot)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _tools(BuildContext context, PlaybackSnapshot snapshot) {
    final media = session.media;
    final page = commands.value;
    void leave(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    Widget action(String label, IconData icon, VoidCallback onTap) =>
        ListTile(leading: Icon(icon), title: Text(label), onTap: onTap);
    Widget choice(String label, bool selected, VoidCallback onTap) => ListTile(
      title: Text(label),
      trailing: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onTap: onTap,
    );

    return [
      if (session.error != null)
        action(
          '重新加载',
          Icons.refresh,
          () => leave(() => unawaited(session.retry())),
        ),
      action(
        snapshot.desiredPlaying ? '暂停' : '播放',
        snapshot.desiredPlaying ? Icons.pause : Icons.play_arrow,
        () => unawaited(session.togglePlaying()),
      ),
      if (!session.isLive &&
          session.contentTarget is! OfflinePlaybackTarget &&
          page != null) ...[
        if ((session.detail?.parts.length ?? 0) > 1)
          action('上一分 P', Icons.skip_previous, () => leave(page.previousPart)),
        ListTile(
          leading: const Icon(Icons.skip_next),
          title: const Text('下一集'),
          enabled: page.hasNext && !session.isResolving,
          onTap: () => leave(page.nextPart),
        ),
      ],
      if (onCompose case final compose?)
        action('发送弹幕', Icons.edit_outlined, () => leave(compose)),
      action(
        settings.value.danmakuEnabled ? '关闭弹幕' : '开启弹幕',
        Icons.subtitles_outlined,
        onToggleComments,
      ),
      if (media != null && (session.isLive || media.qualities.length > 1))
        ExpansionTile(
          title: const Text('清晰度'),
          children: [
            if (session.isLive)
              choice(
                '清晰度 自动',
                session.requestedQuality == 0,
                () => unawaited(session.changeQuality(0)),
              ),
            for (final quality in media.qualities)
              choice(
                '清晰度 ${media.qualityLabels[quality] ?? playbackQualityLabel(quality)}',
                quality == media.quality &&
                    (!session.isLive || session.requestedQuality != 0),
                () => unawaited(session.changeQuality(quality)),
              ),
          ],
        ),
      if (!session.isLive)
        ExpansionTile(
          title: const Text('播放速度'),
          subtitle: Text('${snapshot.rate}x'),
          children: [
            for (final rate in PlaybackRates.values)
              choice(
                '${rate}x',
                snapshot.rate == rate,
                () => unawaited(session.setRate(rate)),
              ),
          ],
        ),
      if (session.subtitleTracks.isNotEmpty)
        ExpansionTile(
          title: const Text('字幕'),
          children: [
            choice(
              '关闭字幕',
              session.selectedSubtitle == -1,
              () => unawaited(session.selectSubtitle(-1)),
            ),
            for (var i = 0; i < session.subtitleTracks.length; i++)
              choice(
                playbackSubtitleLabel(session.subtitleTracks[i]),
                session.selectedSubtitle == i,
                () => unawaited(session.selectSubtitle(i)),
              ),
          ],
        ),
      if (session.voiceTracks.isNotEmpty)
        ExpansionTile(
          title: const Text('语音翻译'),
          children: [
            for (final voice in [
              const PlaybackVoice.original(),
              ...session.voiceTracks,
            ])
              choice(
                '语音 ${playbackVoiceLabel(voice)}',
                voice.key == session.selectedVoice.key,
                () => unawaited(session.changeVoice(voice)),
              ),
          ],
        ),
      if (session.isLive && media != null) ...[
        action(
          '直播流与线路',
          Icons.settings_input_antenna,
          () => unawaited(
            showLiveStreamPicker(
              context,
              session: session,
              media: media,
              onMenuChanged: (_) {},
            ),
          ),
        ),
        if (media.video.urls.length > 1)
          ExpansionTile(
            title: const Text('直播线路'),
            children: [
              for (var line = 0; line < media.video.urls.length; line++)
                choice(
                  '直播线路 ${liveLineLabel(line)}',
                  line == session.liveLine,
                  () => unawaited(session.changeLiveLine(line)),
                ),
            ],
          ),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('音量 ${snapshot.volume.round()}%'),
            Slider(
              key: const ValueKey('player-more-volume'),
              value: snapshot.volume.clamp(0, 100),
              max: 100,
              semanticFormatterCallback: (value) => '${value.round()}%',
              onChanged: (value) => unawaited(session.setVolume(value)),
            ),
          ],
        ),
      ),
      if (session.canListen)
        action(
          '听视频',
          Icons.headphones_rounded,
          () => leave(() => unawaited(session.setAudioOnly(true))),
        ),
      if (castRequestFor(session) != null)
        action(
          '投屏',
          Icons.cast_rounded,
          () => unawaited(showCastingDialog(context, session)),
        ),
      action(
        fullScreen ? '退出全屏' : '全屏',
        Icons.fullscreen,
        () => leave(onFullScreen),
      ),
      if (page != null)
        action(
          '显示／隐藏信息区',
          Icons.view_sidebar_outlined,
          () => leave(page.toggleInfo),
        ),
      if (navigation.value case final actions? when actions.showInPlayer) ...[
        action(
          '返回',
          Icons.arrow_back_rounded,
          () => leave(() => onNavigate(actions.onBack)),
        ),
        action(
          '回到主页',
          Icons.home_outlined,
          () => leave(() => onNavigate(actions.onHome)),
        ),
      ],
      const Divider(),
      action('播放配置', Icons.settings_outlined, () => unawaited(onSettings(0))),
      action('弹幕配置', Icons.tune, () => unawaited(onSettings(1))),
      if (!session.isLive)
        action('字幕样式', Icons.text_fields, () => unawaited(onSettings(2))),
      if (session.contentTarget == null)
        action('空降助手', Icons.fast_forward, () => unawaited(onSettings(3))),
    ];
  }
}
