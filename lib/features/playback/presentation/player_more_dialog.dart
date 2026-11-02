import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

import '../../../domain/playback_rates.dart';
import '../application/playback_session.dart';
import '../domain/playback_repository.dart';
import 'live_stream_picker.dart';
import 'playback_snapshot_builder.dart';
import 'player_control_labels.dart';

class PlayerMoreDialog extends StatelessWidget {
  const PlayerMoreDialog({
    super.key,
    required this.session,
    required this.playerBounds,
    required this.onSettings,
  });

  final PlaybackSession session;
  final ValueGetter<Rect?> playerBounds;
  final Future<void> Function(int) onSettings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => _buildDialog(context),
  );

  Widget _buildDialog(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final dialog = Dialog(
      key: const ValueKey('player-more-dialog'),
      alignment: narrow ? Alignment.bottomCenter : Alignment.centerRight,
      insetPadding: EdgeInsets.all(narrow ? 12 : 24),
      constraints: BoxConstraints(
        maxWidth: narrow ? 560 : 400,
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      clipBehavior: Clip.antiAlias,
      child: PlaybackSnapshotBuilder(
        snapshots: session.snapshots,
        select: (snapshot) => (snapshot.rate, snapshot.volume),
        builder: (context, snapshot) => LayoutBuilder(
          builder: (context, constraints) {
            final header = Padding(
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
            );
            final tools = _tools(context, snapshot);
            // A short area below a tall video must remain scrollable even
            // when it cannot fit the header at its natural height.
            if (constraints.maxHeight < 100) {
              return SingleChildScrollView(
                key: const ValueKey('player-more-scroll'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [header, ...tools],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('player-more-scroll'),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(children: tools),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (!narrow) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: ColoredBox(
              key: ValueKey('player-more-wide-backdrop'),
              color: Colors.black54,
            ),
          ),
          SafeArea(child: dialog),
        ],
      );
    }
    return _BelowVideoArea(playerBounds: playerBounds, child: dialog);
  }

  List<Widget> _tools(BuildContext context, PlaybackSnapshot snapshot) {
    final media = session.media;
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
      if (!session.isLive && media != null && media.audioTracks.isNotEmpty)
        ExpansionTile(
          title: const Text('音质'),
          subtitle: switch (media.audioQuality) {
            final quality? => Text(playbackAudioQualityLabel(quality)),
            null => null,
          },
          children: [
            for (final option in media.audioTracks)
              choice(
                playbackAudioQualityLabel(option.quality),
                media.audioQuality == option.quality,
                () => unawaited(session.changeAudioQuality(option.quality)),
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

class _BelowVideoArea extends StatefulWidget {
  const _BelowVideoArea({required this.playerBounds, required this.child});

  final ValueGetter<Rect?> playerBounds;
  final Widget child;

  @override
  State<_BelowVideoArea> createState() => _BelowVideoAreaState();
}

class _BelowVideoAreaState extends State<_BelowVideoArea> {
  Rect? _playerBounds;
  (Size, EdgeInsets, EdgeInsets)? _measuredMetrics;
  bool _measurementPending = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final metrics = (
        constraints.biggest,
        media.viewPadding,
        media.viewInsets,
      );
      if (!_measurementPending) {
        _measurementPending = true;
        // Global transforms can read ancestor sizes; measure after layout,
        // outside another render object's layout pass.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _measurementPending = false;
          if (!mounted) return;
          final bounds = widget.playerBounds();
          if (_playerBounds != bounds || _measuredMetrics != metrics) {
            setState(() {
              _playerBounds = bounds;
              _measuredMetrics = metrics;
            });
          }
        });
      }
      return CustomSingleChildLayout(
        delegate: _BelowVideoLayout(
          // Hide the sheet for the measurement frame after a resize instead
          // of briefly covering video with the previous window's geometry.
          playerBounds: _measuredMetrics == metrics ? _playerBounds : null,
          padding: media.viewPadding,
          keyboardBottom: media.viewInsets.bottom,
        ),
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: widget.child,
        ),
      );
    },
  );
}

class _BelowVideoLayout extends SingleChildLayoutDelegate {
  _BelowVideoLayout({
    required this.playerBounds,
    required this.padding,
    required this.keyboardBottom,
  });

  final Rect? playerBounds;
  final EdgeInsets padding;
  final double keyboardBottom;

  double _bottom(double height) =>
      (height -
              (keyboardBottom > padding.bottom
                  ? keyboardBottom
                  : padding.bottom))
          .clamp(0.0, height);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bottom = _bottom(constraints.maxHeight);
    final top = (playerBounds?.bottom ?? bottom).clamp(
      padding.top.clamp(0.0, bottom),
      bottom,
    );
    return BoxConstraints(
      maxWidth: (constraints.maxWidth - padding.horizontal).clamp(
        0.0,
        constraints.maxWidth,
      ),
      maxHeight: bottom - top,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(padding.left, _bottom(size.height) - childSize.height);

  @override
  bool shouldRelayout(_BelowVideoLayout oldDelegate) =>
      playerBounds != oldDelegate.playerBounds ||
      padding != oldDelegate.padding ||
      keyboardBottom != oldDelegate.keyboardBottom;
}
