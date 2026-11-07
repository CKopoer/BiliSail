import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';

import '../../settings/domain/app_settings.dart';
import '../domain/content_playback.dart';
import '../domain/playback_repository.dart';
import 'playback_session.dart';

final class PlaybackInformation {
  const PlaybackInformation({
    required this.sourceGeneration,
    required this.snapshot,
    required this.hasSource,
    required this.isLive,
    required this.audioOnly,
    required this.sourceType,
    required this.quality,
    this.videoCodec,
    this.audioCodec,
    this.videoBandwidth,
    this.audioBandwidth,
    this.native,
  });

  final int sourceGeneration;
  final PlaybackSnapshot snapshot;
  final bool hasSource, isLive, audioOnly;
  final String sourceType, quality;
  final String? videoCodec, audioCodec;
  final int? videoBandwidth, audioBandwidth;
  final PlayerPlaybackInformation? native;
}

/// Samples only while the information tab is visible. Native reads are bounded,
/// never overlap, and cannot publish across source/account/tab changes.
final class PlaybackInformationController
    extends ValueNotifier<PlaybackInformation?> {
  PlaybackInformationController(this.session) : super(null);

  final PlaybackSession session;
  Timer? _timer;
  bool _active = false, _reading = false;
  int _revision = 0;

  void start() {
    if (_active) return;
    _active = true;
    session.addListener(_sessionChanged);
    _sessionChanged();
  }

  void stop() {
    if (!_active) return;
    _active = false;
    ++_revision;
    session.removeListener(_sessionChanged);
    _timer?.cancel();
    _timer = null;
  }

  PlaybackInformation _capture(PlayerPlaybackInformation? native) {
    final media = session.sourceMatchesAccount ? session.media : null;
    return PlaybackInformation(
      sourceGeneration: session.sourceGeneration,
      snapshot: session.snapshots.value,
      hasSource: media != null,
      isLive: session.isLive,
      audioOnly: session.audioOnly,
      sourceType: switch (session.contentTarget) {
        OfflinePlaybackTarget() => '本地离线',
        _ => switch (media?.kind) {
          PlaybackMediaKind.dash => 'DASH 音视频分轨',
          PlaybackMediaKind.progressive => '渐进式媒体',
          PlaybackMediaKind.liveHls => '直播 HLS',
          PlaybackMediaKind.liveFlv => '直播 FLV',
          null => '—',
        },
      },
      quality: media == null
          ? '—'
          : media.qualityLabels[media.quality] ??
                (session.isLive
                    ? AppSettings.liveQualityOptions[media.quality] ??
                          '${media.quality}'
                    : videoQualityLabel(media.quality)),
      videoCodec: session.audioOnly ? null : media?.video.codec,
      audioCodec: session.audioOnly
          ? media?.audio?.codec ?? media?.video.codec
          : media?.audio?.codec,
      videoBandwidth: session.audioOnly ? null : media?.video.bandwidth,
      audioBandwidth: session.audioOnly
          ? media?.audio?.bandwidth ?? media?.video.bandwidth
          : media?.audio?.bandwidth,
      native: native,
    );
  }

  void _sessionChanged() {
    final previous = value;
    final current = _capture(null);
    if (previous?.sourceGeneration != current.sourceGeneration ||
        previous?.snapshot.generation != current.snapshot.generation ||
        previous?.hasSource != current.hasSource) {
      ++_revision;
      value = current;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_active || _reading) return;
    _timer?.cancel();
    _reading = true;
    final revision = _revision;
    final sourceGeneration = session.sourceGeneration;
    final generation = session.snapshots.value.generation;
    PlayerPlaybackInformation? native;
    try {
      if (session.engine case PlayerInformationSource source
          when session.sourceMatchesAccount && session.media != null) {
        try {
          native = await source.inspectPlaybackInformation().timeout(
            const Duration(seconds: 2),
          );
        } on Object {
          // Optional diagnostics must never affect the playback session.
        }
      }
      if (!_active || revision != _revision) return;
      if (session.sourceGeneration != sourceGeneration ||
          session.snapshots.value.generation != generation ||
          !session.sourceMatchesAccount) {
        value = _capture(null);
        return;
      }
      value = _capture(native?.generation == generation ? native : null);
    } finally {
      _reading = false;
      if (_active) {
        _timer = Timer(const Duration(seconds: 1), () => unawaited(_refresh()));
      }
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
