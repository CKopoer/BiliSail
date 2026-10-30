import 'dart:async';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

import '../../../domain/playback_rates.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../application/playback_session.dart';
import 'audio_subtitle_lyrics.dart';
import 'playback_snapshot_builder.dart';

/// A listening surface with localized timeline and subtitle updates.
class AudioPlaybackView extends StatelessWidget {
  const AudioPlaybackView({
    super.key,
    required this.session,
    required this.snapshot,
    required this.onFullScreen,
    required this.fullScreen,
    required this.navigation,
    this.commands,
  });

  final PlaybackSession session;
  final PlaybackSnapshot snapshot;
  final VoidCallback onFullScreen;
  final bool fullScreen;
  final Widget navigation;
  final PlaybackPageCommands? commands;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready =
        !session.isResolving && session.media != null && session.error == null;
    return Material(
      key: const ValueKey('audio-playback-view'),
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: fullScreen,
        bottom: fullScreen,
        left: fullScreen,
        right: fullScreen,
        child: LayoutBuilder(
          builder: (context, bounds) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      navigation,
                      const Icon(Icons.headphones_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '听视频',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (bounds.maxWidth < 380 ||
                          MediaQuery.textScalerOf(context).scale(14) > 18)
                        IconButton(
                          key: const ValueKey('audio-return-video'),
                          tooltip: '返回视频',
                          onPressed: () =>
                              unawaited(session.setAudioOnly(false)),
                          icon: const Icon(Icons.ondemand_video_rounded),
                        )
                      else
                        TextButton.icon(
                          key: const ValueKey('audio-return-video'),
                          onPressed: () =>
                              unawaited(session.setAudioOnly(false)),
                          icon: const Icon(
                            Icons.ondemand_video_rounded,
                            size: 18,
                          ),
                          label: const Text('返回视频'),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _content(context)),
                if (session.error case final error?)
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(session.retry()),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                PlaybackSnapshotBuilder(
                  snapshots: session.snapshots,
                  select: (value) =>
                      (value.position, value.duration, value.buffered),
                  builder: (context, value) => _AudioTimeline(
                    key: ValueKey(session.sourceGeneration),
                    snapshot: value,
                    enabled: ready,
                    onSeek: session.seek,
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '后退 10 秒',
                        onPressed: ready ? () => _skip(-10) : null,
                        icon: const Icon(Icons.replay_10_rounded),
                      ),
                      IconButton.filled(
                        key: const ValueKey('audio-toggle-playing'),
                        tooltip: snapshot.desiredPlaying ? '暂停' : '播放',
                        onPressed: ready
                            ? () => unawaited(session.togglePlaying())
                            : null,
                        icon: session.isResolving || snapshot.isBuffering
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                snapshot.desiredPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                      ),
                      IconButton(
                        tooltip: '前进 10 秒',
                        onPressed: ready ? () => _skip(10) : null,
                        icon: const Icon(Icons.forward_10_rounded),
                      ),
                      if (bounds.maxWidth >= 440 && commands != null)
                        IconButton(
                          tooltip: '下一集',
                          onPressed: commands?.hasNext == true
                              ? commands?.nextPart
                              : null,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      const Spacer(),
                      PopupMenuButton<double>(
                        tooltip: '播放速度',
                        enabled: ready,
                        onSelected: (rate) => unawaited(session.setRate(rate)),
                        itemBuilder: (_) => [
                          for (final rate in PlaybackRates.values)
                            CheckedPopupMenuItem(
                              value: rate,
                              checked: snapshot.rate == rate,
                              child: Text('${rate}x'),
                            ),
                        ],
                        child:
                            bounds.maxWidth < 380 ||
                                MediaQuery.textScalerOf(context).scale(14) > 18
                            ? const SizedBox.square(
                                dimension: 48,
                                child: Icon(Icons.speed_rounded),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                child: Text('${snapshot.rate}x'),
                              ),
                      ),
                      PopupMenuButton<VoidCallback>(
                        tooltip: '听视频选项',
                        onSelected: (action) => action(),
                        itemBuilder: (_) => [
                          if (session.subtitleTracks.isNotEmpty) ...[
                            CheckedPopupMenuItem(
                              checked: session.selectedSubtitle == -1,
                              value: () =>
                                  unawaited(session.selectSubtitle(-1)),
                              child: const Text('关闭字幕'),
                            ),
                            for (
                              var i = 0;
                              i < session.subtitleTracks.length;
                              i++
                            )
                              CheckedPopupMenuItem(
                                checked: session.selectedSubtitle == i,
                                value: () =>
                                    unawaited(session.selectSubtitle(i)),
                                child: Text(session.subtitleTracks[i].label),
                              ),
                          ],
                          if (commands != null) ...[
                            PopupMenuItem(
                              value: commands?.previousPart,
                              child: const Text('上一集'),
                            ),
                            PopupMenuItem(
                              enabled: commands?.hasNext == true,
                              value: commands?.nextPart,
                              child: const Text('下一集'),
                            ),
                          ],
                          PopupMenuItem(
                            enabled: false,
                            child: SizedBox(
                              width: 220,
                              child: PlaybackSnapshotBuilder(
                                snapshots: session.snapshots,
                                select: (value) => value.volume,
                                builder: (context, value) => Row(
                                  children: [
                                    Icon(
                                      value.volume == 0
                                          ? Icons.volume_off_outlined
                                          : Icons.volume_up_outlined,
                                    ),
                                    Expanded(
                                      child: Slider(
                                        semanticFormatterCallback: (volume) =>
                                            '音量 ${volume.round()}%',
                                        value: value.volume.clamp(0, 100),
                                        max: 100,
                                        onChanged: ready
                                            ? (volume) => unawaited(
                                                session.setVolume(volume),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                      IconButton(
                        tooltip: fullScreen ? '退出全屏' : '全屏',
                        onPressed: onFullScreen,
                        icon: Icon(
                          fullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final hasLyrics = session.subtitleCues.isNotEmpty;
      final lyrics = hasLyrics
          ? AudioSubtitleLyrics(
              key: ValueKey((
                session,
                session.sourceGeneration,
                session.subtitleCues,
              )),
              session: session,
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  session.subtitleLoading
                      ? '正在加载字幕…'
                      : session.subtitleMessage ??
                            (session.subtitleTracks.isEmpty
                                ? '暂无字幕'
                                : '字幕已关闭，可在听视频选项中开启'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
      if (bounds.maxWidth >= 720 && bounds.maxHeight >= 220) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              children: [
                Expanded(flex: 2, child: _identity(context)),
                const SizedBox(width: 24),
                Expanded(flex: 3, child: lyrics),
              ],
            ),
          ),
        );
      }
      return Column(
        children: [
          if (!hasLyrics || bounds.maxHeight >= 240)
            SizedBox(
              height: !hasLyrics
                  ? bounds.maxHeight * .65
                  : bounds.maxHeight >= 480
                  ? 168
                  : 64,
              child: _identity(context),
            ),
          Expanded(child: lyrics),
        ],
      );
    },
  );

  Widget _identity(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final tall = bounds.maxHeight >= 300 && bounds.maxWidth < 600;
      final coverSize = tall
          ? math.min(200.0, bounds.maxHeight * .5)
          : math.min(
              bounds.maxWidth >= 600 ? 200.0 : 64.0,
              bounds.maxHeight * .85,
            );
      final title = Text(
        session.title,
        maxLines: tall || bounds.maxHeight > 120 ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        textAlign: tall ? TextAlign.center : TextAlign.start,
        style: Theme.of(context).textTheme.titleMedium,
      );
      final details = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: tall
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          title,
          if (bounds.maxHeight >= 90) ...[
            const SizedBox(height: 8),
            Text(
              session.isResolving
                  ? '正在切换音频…'
                  : snapshot.isBuffering
                  ? '音频缓冲中…'
                  : snapshot.desiredPlaying
                  ? '正在听 · 仅加载音频'
                  : '已暂停 · 仅加载音频',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      );
      final cover = _AudioCover(
        url: session.detail?.summary.coverUrl ?? '',
        size: coverSize,
      );
      return Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: tall
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [cover, const SizedBox(height: 20), details],
                  )
                : Row(
                    children: [
                      if (coverSize >= 32) ...[
                        cover,
                        const SizedBox(width: 16),
                      ],
                      Expanded(child: details),
                    ],
                  ),
          ),
        ),
      );
    },
  );

  void _skip(int seconds) {
    final current = session.snapshots.value;
    final target = (current.position + Duration(seconds: seconds))
        .inMilliseconds
        .clamp(0, current.duration.inMilliseconds);
    unawaited(session.seek(Duration(milliseconds: target)));
  }
}

class _AudioCover extends StatelessWidget {
  const _AudioCover({required this.url, required this.size});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Center(child: Icon(Icons.headphones_rounded, size: size * .45)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? fallback
            : AppCoverImage(
                url: url,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _AudioTimeline extends StatefulWidget {
  const _AudioTimeline({
    super.key,
    required this.snapshot,
    required this.enabled,
    required this.onSeek,
  });
  final PlaybackSnapshot snapshot;
  final bool enabled;
  final Future<void> Function(Duration) onSeek;

  @override
  State<_AudioTimeline> createState() => _AudioTimelineState();
}

class _AudioTimelineState extends State<_AudioTimeline> {
  double? _preview;
  int _revision = 0;

  Future<void> _seek(double value) async {
    final revision = ++_revision;
    setState(() => _preview = value);
    try {
      await widget.onSeek(Duration(milliseconds: value.round()));
    } finally {
      if (mounted && revision == _revision) setState(() => _preview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.snapshot.duration.inMilliseconds.toDouble();
    final value =
        (_preview ?? widget.snapshot.position.inMilliseconds.toDouble())
            .clamp(0.0, math.max(1.0, total))
            .toDouble();
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Text(
            _time(Duration(milliseconds: value.round())),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Expanded(
            child: Slider(
              key: const ValueKey('audio-timeline'),
              value: value,
              max: math.max(1.0, total),
              secondaryTrackValue: math
                  .max(
                    value,
                    widget.snapshot.buffered.inMilliseconds.toDouble(),
                  )
                  .clamp(0.0, math.max(1.0, total))
                  .toDouble(),
              semanticFormatterCallback: (value) =>
                  _time(Duration(milliseconds: value.round())),
              onChanged: widget.enabled && total > 0
                  ? (value) => setState(() {
                      _revision++;
                      _preview = value;
                    })
                  : null,
              onChangeEnd: (value) => unawaited(_seek(value)),
            ),
          ),
          Text(
            _time(widget.snapshot.duration),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

String _time(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
